// Server-side storage and the rules for applying ops. Uses bun:sqlite; no HTTP here.
//
// Conflict rule (see README):
//   - Ops are applied in the order the server receives them (last writer wins per field).
//     rename only touches title, setDone only touches done, so a concurrent rename
//     and toggle from two clients both survive.
//   - delete is final: once a todo is a tombstone, later rename/setDone are ignored
//     and a create with the same id does not bring it back.
//   - Every op id is remembered. A retried op is not applied again; the server
//     returns the current row instead.

import { Database } from "bun:sqlite";
import type { Op, OpResult, ServerTodo } from "./types";

interface Row {
  id: string;
  title: string;
  done: number;
  version: number;
  deleted: number;
  seq: number;
}

function toTodo(r: Row): ServerTodo {
  return { id: r.id, title: r.title, done: r.done === 1, version: r.version, deleted: r.deleted === 1, seq: r.seq };
}

export const MAX_TITLE = 500;

export class ValidationError extends Error {}

function validateOp(op: Op): void {
  if (!op || typeof op !== "object") throw new ValidationError("op must be an object");
  if (typeof op.opId !== "string" || op.opId.length === 0 || op.opId.length > 200) throw new ValidationError("bad opId");
  if (typeof op.id !== "string" || op.id.length === 0 || op.id.length > 100) throw new ValidationError("bad id");
  switch (op.kind) {
    case "create":
    case "rename":
      if (typeof op.title !== "string") throw new ValidationError("title must be a string");
      if (op.title.trim().length === 0) throw new ValidationError("title must not be empty");
      if (op.title.length > MAX_TITLE) throw new ValidationError("title too long");
      return;
    case "setDone":
      if (typeof op.done !== "boolean") throw new ValidationError("done must be a boolean");
      return;
    case "delete":
      return;
    default:
      throw new ValidationError("unknown op kind");
  }
}

export class TodoStore {
  readonly db: Database;

  constructor(path = ":memory:") {
    this.db = new Database(path, { create: true });
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS todos (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        seq INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS todos_seq ON todos(seq);
      CREATE TABLE IF NOT EXISTS applied_ops (
        op_id TEXT PRIMARY KEY,
        todo_id TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL
      );
      INSERT OR IGNORE INTO meta(key, value) VALUES ('seq', 0);
    `);
  }

  currentSeq(): number {
    return (this.db.query("SELECT value FROM meta WHERE key = 'seq'").get() as { value: number }).value;
  }

  private bumpSeq(): number {
    this.db.run("UPDATE meta SET value = value + 1 WHERE key = 'seq'");
    return this.currentSeq();
  }

  private get(id: string): ServerTodo | null {
    const r = this.db.query("SELECT * FROM todos WHERE id = ?").get(id) as Row | null;
    return r ? toTodo(r) : null;
  }

  private applyOne(op: Op): ServerTodo | null {
    const seen = this.db.query("SELECT todo_id FROM applied_ops WHERE op_id = ?").get(op.opId);
    if (seen) return this.get(op.id);

    const cur = this.get(op.id);

    switch (op.kind) {
      case "create":
        if (!cur) {
          const seq = this.bumpSeq();
          this.db.run("INSERT INTO todos(id, title, done, version, deleted, seq) VALUES (?, ?, 0, 1, 0, ?)", [
            op.id,
            op.title,
            seq,
          ]);
        }
        break;
      case "rename":
        if (cur && !cur.deleted && cur.title !== op.title) {
          const seq = this.bumpSeq();
          this.db.run("UPDATE todos SET title = ?, version = version + 1, seq = ? WHERE id = ?", [op.title, seq, op.id]);
        }
        break;
      case "setDone":
        if (cur && !cur.deleted && cur.done !== op.done) {
          const seq = this.bumpSeq();
          this.db.run("UPDATE todos SET done = ?, version = version + 1, seq = ? WHERE id = ?", [
            op.done ? 1 : 0,
            seq,
            op.id,
          ]);
        }
        break;
      case "delete":
        if (cur && !cur.deleted) {
          const seq = this.bumpSeq();
          this.db.run("UPDATE todos SET deleted = 1, version = version + 1, seq = ? WHERE id = ?", [seq, op.id]);
        }
        break;
    }

    this.db.run("INSERT INTO applied_ops(op_id, todo_id) VALUES (?, ?)", [op.opId, op.id]);
    return this.get(op.id);
  }

  /** Apply a batch of ops in order, in one transaction. Throws ValidationError before touching anything. */
  push(ops: Op[]): OpResult[] {
    if (!Array.isArray(ops)) throw new ValidationError("ops must be an array");
    if (ops.length > 200) throw new ValidationError("too many ops");
    for (const op of ops) validateOp(op);
    const tx = this.db.transaction((batch: Op[]) => batch.map((op) => ({ opId: op.opId, todo: this.applyOne(op) })));
    return tx(ops);
  }

  /** All rows changed after `since`, oldest first, plus the seq to use next time. */
  pull(since: number, limit = 500): { changes: ServerTodo[]; seq: number } {
    const read = this.db.transaction(() => {
      const rows = this.db
        .query("SELECT * FROM todos WHERE seq > ? ORDER BY seq LIMIT ?")
        .all(since, limit) as Row[];
      const changes = rows.map(toTodo);
      const seq = changes.length === limit ? changes[changes.length - 1]!.seq : this.currentSeq();
      return { changes, seq: Math.max(seq, since) };
    });
    return read();
  }

  close(): void {
    this.db.close();
  }
}
