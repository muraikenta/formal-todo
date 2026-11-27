// Types shared by the client, the server and the tests.

/** A todo row as the server stores and sends it. */
export interface ServerTodo {
  id: string;
  title: string;
  done: boolean;
  /** Incremented by the server every time this todo changes. Starts at 1. */
  version: number;
  /** Tombstone: true once deleted. Deleted rows are kept so pulls can see the delete. */
  deleted: boolean;
  /** Server-wide sequence number of the last change to this row. */
  seq: number;
}

/** One user action. `opId` makes retries idempotent on the server. */
export type Op =
  | { opId: string; kind: "create"; id: string; title: string }
  | { opId: string; kind: "rename"; id: string; title: string }
  | { opId: string; kind: "setDone"; id: string; done: boolean }
  | { opId: string; kind: "delete"; id: string };

export interface PushRequest {
  clientId: string;
  ops: Op[];
}

export interface OpResult {
  opId: string;
  /** The row after the op was applied, or null if the todo never existed. */
  todo: ServerTodo | null;
}

export interface PushResponse {
  results: OpResult[];
}

export interface PullResponse {
  changes: ServerTodo[];
  /** Highest sequence number covered by this response. Pass it as `since` next time. */
  seq: number;
}
