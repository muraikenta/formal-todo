// Clients (pure sync module) talking to the store through the real HTTP handlers,
// over a fake network that can fail a request or lose its response.
import { describe, expect, test } from "bun:test";
import { handlePull, handlePush } from "../src/api";
import { TodoStore } from "../src/server-store";
import {
  applyPull,
  applyPushResult,
  enqueue,
  initialState,
  nextBatch,
  view,
  type ClientState,
  type LocalAction,
} from "../src/sync";
import type { PullResponse, PushResponse } from "../src/types";

type Fault = "none" | "fail-request" | "lose-response";

class Net {
  next: Fault[] = [];
  constructor(private store: TodoStore) {}
  private fault(): Fault {
    return this.next.shift() ?? "none";
  }
  async push(clientId: string, ops: unknown[]): Promise<PushResponse> {
    const f = this.fault();
    if (f === "fail-request") throw new Error("network down");
    const res = await handlePush(
      this.store,
      new Request("http://x/api/push", { method: "POST", body: JSON.stringify({ clientId, ops }) }),
    );
    if (f === "lose-response") throw new Error("timeout");
    return (await res.json()) as PushResponse;
  }
  async pull(since: number): Promise<PullResponse> {
    const f = this.fault();
    if (f === "fail-request") throw new Error("network down");
    const res = handlePull(this.store, new Request(`http://x/api/pull?since=${since}`));
    if (f === "lose-response") throw new Error("timeout");
    return (await res.json()) as PullResponse;
  }
}

class Client {
  state: ClientState;
  constructor(id: string, private net: Net) {
    this.state = initialState(id);
  }
  act(a: LocalAction) {
    this.state = enqueue(this.state, a);
  }
  async push(): Promise<boolean> {
    const batch = nextBatch(this.state);
    if (batch.length === 0) return true;
    try {
      const res = await this.net.push(this.state.clientId, batch);
      this.state = applyPushResult(this.state, res.results);
      return true;
    } catch {
      return false;
    }
  }
  async pull(): Promise<boolean> {
    try {
      this.state = applyPull(this.state, await this.net.pull(this.state.lastSeq));
      return true;
    } catch {
      return false;
    }
  }
  async sync() {
    await this.push();
    await this.pull();
  }
  titles() {
    return view(this.state).map((t) => `${t.title}${t.done ? "✓" : ""}`);
  }
}

describe("end to end", () => {
  test("normal flow", async () => {
    const store = new TodoStore();
    const net = new Net(store);
    const a = new Client("A", net);
    a.act({ kind: "create", id: "1", title: "牛乳" });
    a.act({ kind: "create", id: "2", title: "卵" });
    a.act({ kind: "setDone", id: "1", done: true });
    a.act({ kind: "rename", id: "2", title: "卵 10個" });
    await a.sync();
    expect(a.state.outbox).toEqual([]);
    expect(a.titles()).toEqual(["牛乳✓", "卵 10個"]);
    a.act({ kind: "delete", id: "1" });
    await a.sync();
    expect(a.titles()).toEqual(["卵 10個"]);
    expect(view(a.state).every((t) => !t.pending)).toBe(true);
  });

  test("retry after a lost response does not duplicate or re-apply", async () => {
    const store = new TodoStore();
    const net = new Net(store);
    const a = new Client("A", net);
    a.act({ kind: "create", id: "1", title: "牛乳" });
    a.act({ kind: "setDone", id: "1", done: true });

    net.next = ["lose-response"];
    expect(await a.push()).toBe(false); // server applied it, client did not hear back
    expect(a.state.outbox).toHaveLength(2);

    net.next = ["fail-request"];
    expect(await a.push()).toBe(false); // never reached the server

    expect(await a.push()).toBe(true); // retry
    expect(a.state.outbox).toEqual([]);
    await a.pull();
    expect(a.titles()).toEqual(["牛乳✓"]);
    const rows = store.pull(0).changes;
    expect(rows).toHaveLength(1);
    expect(rows[0]!.version).toBe(2);
  });

  test("two clients editing the same todo converge", async () => {
    const store = new TodoStore();
    const net = new Net(store);
    const a = new Client("A", net);
    const b = new Client("B", net);
    a.act({ kind: "create", id: "1", title: "牛乳" });
    await a.sync();
    await b.sync();
    expect(b.titles()).toEqual(["牛乳"]);

    // concurrent: A renames, B toggles and renames
    a.act({ kind: "rename", id: "1", title: "牛乳 (A)" });
    b.act({ kind: "setDone", id: "1", done: true });
    b.act({ kind: "rename", id: "1", title: "牛乳 (B)" });
    await a.push();
    await b.push(); // B arrives last, so B's title wins; the toggle has no competitor and survives
    await a.pull();
    await b.pull();
    expect(a.titles()).toEqual(["牛乳 (B)✓"]);
    expect(b.titles()).toEqual(a.titles());
  });

  test("delete on one client wins over a concurrent edit on another", async () => {
    const store = new TodoStore();
    const net = new Net(store);
    const a = new Client("A", net);
    const b = new Client("B", net);
    a.act({ kind: "create", id: "1", title: "牛乳" });
    await a.sync();
    await b.sync();
    a.act({ kind: "delete", id: "1" });
    b.act({ kind: "rename", id: "1", title: "豆乳" });
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.titles()).toEqual([]);
    expect(b.titles()).toEqual([]);
  });

  test("offline client catches up after reconnecting", async () => {
    const store = new TodoStore();
    const net = new Net(store);
    const a = new Client("A", net);
    const b = new Client("B", net);
    net.next = ["fail-request", "fail-request"];
    b.act({ kind: "create", id: "b1", title: "Bのメモ" });
    await b.sync(); // both calls fail
    expect(b.state.outbox).toHaveLength(1);
    a.act({ kind: "create", id: "a1", title: "Aのメモ" });
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.titles().sort()).toEqual(["Aのメモ", "Bのメモ"]);
    expect(b.titles().sort()).toEqual(a.titles().sort());
  });
});
