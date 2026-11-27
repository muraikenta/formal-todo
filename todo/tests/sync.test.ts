import { describe, expect, test } from "bun:test";
import { applyPull, applyPushResult, enqueue, initialState, nextBatch, view } from "../src/sync";
import type { ServerTodo } from "../src/types";

const row = (p: Partial<ServerTodo> & { id: string }): ServerTodo => ({
  title: "t",
  done: false,
  version: 1,
  deleted: false,
  seq: 1,
  ...p,
});

describe("sync (pure)", () => {
  test("local ops show immediately and are queued in order", () => {
    let s = initialState("c1");
    s = enqueue(s, { kind: "create", id: "a", title: "牛乳" });
    s = enqueue(s, { kind: "setDone", id: "a", done: true });
    expect(view(s)).toEqual([{ id: "a", title: "牛乳", done: true, pending: true }]);
    expect(nextBatch(s).map((o) => o.opId)).toEqual(["c1:1", "c1:2"]);
  });

  test("filters", () => {
    let s = initialState("c1");
    s = enqueue(s, { kind: "create", id: "a", title: "A" });
    s = enqueue(s, { kind: "create", id: "b", title: "B" });
    s = enqueue(s, { kind: "setDone", id: "b", done: true });
    expect(view(s, "active").map((t) => t.id)).toEqual(["a"]);
    expect(view(s, "done").map((t) => t.id)).toEqual(["b"]);
    expect(view(s, "all").map((t) => t.id)).toEqual(["a", "b"]);
  });

  test("push result removes acked ops and keeps the rest", () => {
    let s = initialState("c1");
    s = enqueue(s, { kind: "create", id: "a", title: "A" });
    s = enqueue(s, { kind: "rename", id: "a", title: "A2" });
    s = applyPushResult(s, [{ opId: "c1:1", todo: row({ id: "a", title: "A" }) }]);
    expect(s.outbox.map((o) => o.opId)).toEqual(["c1:2"]);
    // pending rename still wins in the view
    expect(view(s)[0]).toMatchObject({ title: "A2", pending: true });
  });

  test("pending op stays on top of a newer pulled value", () => {
    let s = initialState("c1");
    s = applyPull(s, { changes: [row({ id: "a", title: "old" })], seq: 1 });
    s = enqueue(s, { kind: "rename", id: "a", title: "mine" });
    s = applyPull(s, { changes: [row({ id: "a", title: "theirs", version: 2, seq: 2 })], seq: 2 });
    expect(view(s)[0]!.title).toBe("mine");
    expect(s.lastSeq).toBe(2);
  });

  test("older row from the server does not overwrite a newer one", () => {
    let s = initialState("c1");
    s = applyPull(s, { changes: [row({ id: "a", title: "v2", version: 2, seq: 5 })], seq: 5 });
    s = applyPushResult(s, [{ opId: "x", todo: row({ id: "a", title: "v1", version: 1 }) }]);
    expect(view(s)[0]!.title).toBe("v2");
  });

  test("tombstone hides the todo", () => {
    let s = initialState("c1");
    s = applyPull(s, { changes: [row({ id: "a" })], seq: 1 });
    s = applyPull(s, { changes: [row({ id: "a", deleted: true, version: 2, seq: 2 })], seq: 2 });
    expect(view(s)).toEqual([]);
  });
});
