import { describe, expect, test } from "bun:test";
import { TodoStore, ValidationError } from "../src/server-store";

describe("TodoStore", () => {
  test("create, rename, toggle, delete bump version and seq", () => {
    const st = new TodoStore();
    const [c] = st.push([{ opId: "o1", kind: "create", id: "a", title: "A" }]);
    expect(c!.todo).toMatchObject({ id: "a", title: "A", done: false, version: 1, deleted: false, seq: 1 });
    st.push([{ opId: "o2", kind: "rename", id: "a", title: "B" }]);
    st.push([{ opId: "o3", kind: "setDone", id: "a", done: true }]);
    const [d] = st.push([{ opId: "o4", kind: "delete", id: "a" }]);
    expect(d!.todo).toMatchObject({ title: "B", done: true, version: 4, deleted: true, seq: 4 });
  });

  test("retrying the same op does not apply it twice", () => {
    const st = new TodoStore();
    st.push([{ opId: "o1", kind: "create", id: "a", title: "A" }]);
    st.push([{ opId: "o1", kind: "create", id: "a", title: "A" }]);
    st.push([{ opId: "o2", kind: "setDone", id: "a", done: true }]);
    st.push([{ opId: "o3", kind: "setDone", id: "a", done: false }]);
    // a late retry of o2 must not flip it back to done
    const [r] = st.push([{ opId: "o2", kind: "setDone", id: "a", done: true }]);
    expect(r!.todo).toMatchObject({ done: false, version: 3 });
    expect(st.pull(0).changes).toHaveLength(1);
  });

  test("delete is final", () => {
    const st = new TodoStore();
    st.push([
      { opId: "o1", kind: "create", id: "a", title: "A" },
      { opId: "o2", kind: "delete", id: "a" },
    ]);
    const res = st.push([
      { opId: "o3", kind: "rename", id: "a", title: "zombie" },
      { opId: "o4", kind: "create", id: "a", title: "again" },
    ]);
    expect(res.map((r) => r.todo)).toEqual([
      expect.objectContaining({ title: "A", deleted: true }),
      expect.objectContaining({ title: "A", deleted: true }),
    ]);
  });

  test("ops on unknown ids return null", () => {
    const st = new TodoStore();
    expect(st.push([{ opId: "o1", kind: "rename", id: "nope", title: "x" }])[0]!.todo).toBeNull();
  });

  test("pull returns only changes after since", () => {
    const st = new TodoStore();
    st.push([
      { opId: "o1", kind: "create", id: "a", title: "A" },
      { opId: "o2", kind: "create", id: "b", title: "B" },
    ]);
    const first = st.pull(0);
    expect(first.changes.map((t) => t.id)).toEqual(["a", "b"]);
    expect(first.seq).toBe(2);
    st.push([{ opId: "o3", kind: "rename", id: "a", title: "A2" }]);
    const second = st.pull(first.seq);
    expect(second.changes.map((t) => [t.id, t.title])).toEqual([["a", "A2"]]);
    expect(st.pull(second.seq).changes).toEqual([]);
  });

  test("pull pages with a limit", () => {
    const st = new TodoStore();
    st.push(["a", "b", "c"].map((id, i) => ({ opId: `o${i}`, kind: "create" as const, id, title: id })));
    const p1 = st.pull(0, 2);
    expect(p1.changes.map((t) => t.id)).toEqual(["a", "b"]);
    const p2 = st.pull(p1.seq, 2);
    expect(p2.changes.map((t) => t.id)).toEqual(["c"]);
  });

  test("invalid batch is rejected before anything is applied", () => {
    const st = new TodoStore();
    expect(() =>
      st.push([
        { opId: "o1", kind: "create", id: "a", title: "A" },
        { opId: "o2", kind: "create", id: "b", title: "   " },
      ]),
    ).toThrow(ValidationError);
    expect(st.pull(0).changes).toEqual([]);
  });
});
