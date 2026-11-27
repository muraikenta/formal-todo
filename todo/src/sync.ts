// Client-side sync logic. Pure functions only: no DOM, no fetch, no timers.
//
// Model:
//   confirmed : what we last heard from the server, keyed by id (includes tombstones)
//   outbox    : local ops not yet acknowledged by the server, in the order the user made them
//   lastSeq   : server sequence number we have pulled up to
//
// What the user sees (`view`) is `confirmed` with every outbox op replayed on top.
// So an optimistic change shows immediately, and if the server later sends a
// different value for the same field, the pending op still wins locally until it
// is acknowledged; after that the server's value is the truth.

import type { Op, OpResult, PullResponse, ServerTodo } from "./types";

export interface ClientState {
  clientId: string;
  confirmed: Record<string, ServerTodo>;
  outbox: Op[];
  lastSeq: number;
  /** Counter used to build unique op ids for this client. */
  nextOpNo: number;
}

/** What the UI renders. */
export interface ViewTodo {
  id: string;
  title: string;
  done: boolean;
  /** True while some op on this todo is still waiting for the server. */
  pending: boolean;
}

export type Filter = "all" | "active" | "done";

export function initialState(clientId: string): ClientState {
  return { clientId, confirmed: {}, outbox: [], lastSeq: 0, nextOpNo: 1 };
}

function newOpId(state: ClientState): [string, ClientState] {
  // 例: タブ c1 の 2 番目の操作は "c1:2"。連番は 1 ずつ増える
  const opId = `${state.clientId}:${state.nextOpNo}`;
  return [opId, { ...state, nextOpNo: state.nextOpNo + 1 }];
}

// ---- local actions (optimistic) -------------------------------------------

export type LocalAction =
  | { kind: "create"; id: string; title: string }
  | { kind: "rename"; id: string; title: string }
  | { kind: "setDone"; id: string; done: boolean }
  | { kind: "delete"; id: string };

/** Record a user action: give it an op id and append it to the outbox. */
export function enqueue(state: ClientState, action: LocalAction): ClientState {
  const [opId, s] = newOpId(state);
  const op = { ...action, opId } as Op;
  return { ...s, outbox: [...s.outbox, op] };
}

// ---- applying ops to a todo map --------------------------------------------

interface LocalTodo {
  id: string;
  title: string;
  done: boolean;
  deleted: boolean;
}

/** Apply one op to a map of todos (used for replaying the outbox). Returns a new map. */
export function applyOp(todos: Record<string, LocalTodo>, op: Op): Record<string, LocalTodo> {
  const cur = todos[op.id];
  switch (op.kind) {
    case "create":
      if (cur) return todos; // already exists (e.g. server already has it)
      return { ...todos, [op.id]: { id: op.id, title: op.title, done: false, deleted: false } };
    case "rename":
      if (!cur || cur.deleted) return todos;
      return { ...todos, [op.id]: { ...cur, title: op.title } };
    case "setDone":
      if (!cur || cur.deleted) return todos;
      return { ...todos, [op.id]: { ...cur, done: op.done } };
    case "delete":
      if (!cur) return todos;
      return { ...todos, [op.id]: { ...cur, deleted: true } };
  }
}

/** The list the user sees: confirmed state plus pending ops, without tombstones. */
export function view(state: ClientState, filter: Filter = "all"): ViewTodo[] {
  let todos: Record<string, LocalTodo> = {};
  for (const t of Object.values(state.confirmed)) {
    todos[t.id] = { id: t.id, title: t.title, done: t.done, deleted: t.deleted };
  }
  const pendingIds = new Set<string>();
  for (const op of state.outbox) {
    todos = applyOp(todos, op);
    pendingIds.add(op.id);
  }
  // Order: the order rows first entered `confirmed`, then local creates not yet acknowledged.
  return Object.values(todos)
    .filter((t) => !t.deleted)
    .filter((t) => (filter === "all" ? true : filter === "done" ? t.done : !t.done))
    .map((t) => ({ id: t.id, title: t.title, done: t.done, pending: pendingIds.has(t.id) }));
}

// ---- merging server data -----------------------------------------------------

/** Merge server rows into `confirmed`. A row replaces ours only if its version is newer. */
export function mergeRows(confirmed: Record<string, ServerTodo>, rows: ServerTodo[]): Record<string, ServerTodo> {
  let out = confirmed;
  for (const row of rows) {
    const cur = out[row.id];
    if (!cur || row.version > cur.version) {
      if (out === confirmed) out = { ...confirmed };
      out[row.id] = row;
    }
  }
  return out;
}

/** Merge a pull response. */
export function applyPull(state: ClientState, res: PullResponse): ClientState {
  return {
    ...state,
    confirmed: mergeRows(state.confirmed, res.changes),
    lastSeq: Math.max(state.lastSeq, res.seq),
  };
}

// ---- push --------------------------------------------------------------------

/** Ops to send next. We always send from the head of the outbox so order is kept. */
export function nextBatch(state: ClientState, max = 50): Op[] {
  return state.outbox.slice(0, max);
}

/**
 * The server acknowledged some ops. Drop them from the outbox and merge the rows it returned.
 * Ops not in `results` stay in the outbox and will be sent again.
 * Does not move lastSeq: other clients' changes may sit between our lastSeq and these rows.
 */
export function applyPushResult(state: ClientState, results: OpResult[]): ClientState {
  const acked = new Set(results.map((r) => r.opId));
  const rows = results.flatMap((r) => (r.todo ? [r.todo] : []));
  return {
    ...state,
    outbox: state.outbox.filter((op) => !acked.has(op.opId)),
    confirmed: mergeRows(state.confirmed, rows),
  };
}
