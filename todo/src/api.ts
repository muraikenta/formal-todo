// HTTP layer for the sync API. Thin: parse JSON, call TodoStore, return JSON.
import { TodoStore, ValidationError } from "./server-store";
import type { PullResponse, PushRequest, PushResponse } from "./types";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

export async function handlePush(store: TodoStore, req: Request): Promise<Response> {
  let body: PushRequest;
  try {
    body = (await req.json()) as PushRequest;
  } catch {
    return json({ error: "invalid JSON" }, 400);
  }
  try {
    const results = store.push(body?.ops);
    return json({ results } satisfies PushResponse);
  } catch (e) {
    if (e instanceof ValidationError) return json({ error: e.message }, 400);
    throw e;
  }
}

export function handlePull(store: TodoStore, req: Request): Response {
  const url = new URL(req.url);
  const since = Number(url.searchParams.get("since") ?? "0");
  if (!Number.isInteger(since) || since < 0) return json({ error: "since must be a non-negative integer" }, 400);
  return json(store.pull(since) satisfies PullResponse);
}
