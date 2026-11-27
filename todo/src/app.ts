// Browser glue: DOM rendering, persistence and the network loop.
// All sync decisions are made by the pure functions in ./sync.
import {
  applyPull,
  applyPushResult,
  enqueue,
  initialState,
  nextBatch,
  view,
  type ClientState,
  type Filter,
  type LocalAction,
} from "./sync";
import type { PullResponse, PushResponse } from "./types";

const REQUEST_TIMEOUT_MS = 5000;
const PULL_INTERVAL_MS = 2000;
const MAX_BACKOFF_MS = 10000;

// One client per tab: the id lives in sessionStorage (survives reload, not shared between tabs).
function loadClientId(): string {
  try {
    const existing = sessionStorage.getItem("todo-client-id");
    if (existing) return existing;
    const id = crypto.randomUUID();
    sessionStorage.setItem("todo-client-id", id);
    return id;
  } catch {
    // sessionStorage が使えないときは、保存せずに毎回新しい ID
    return crypto.randomUUID();
  }
}

const clientId = loadClientId();
// 状態は localStorage のこのキーに保存する（全タブで共有の保存先）
const storageKey = `todo-state:${clientId}`;

function loadState(): ClientState {
  try {
    const raw = localStorage.getItem(storageKey);
    if (raw) return JSON.parse(raw) as ClientState;
  } catch {
    // ignore broken or unavailable storage
  }
  return initialState(clientId);
}

let state = loadState();
let filter: Filter = "all";

function setState(next: ClientState): void {
  state = next;
  try {
    localStorage.setItem(storageKey, JSON.stringify(state));
  } catch {
    // storage full or blocked: keep running in memory
  }
  render();
}

function act(action: LocalAction): void {
  setState(enqueue(state, action));
  schedulePush(0);
}

// ---- network ---------------------------------------------------------------

const flaky = document.getElementById("flaky") as HTMLInputElement;

/** fetch with a timeout. With "flaky" on, randomly fails before sending or drops the response after. */
async function request<T>(url: string, init?: RequestInit): Promise<T> {
  if (flaky.checked && Math.random() < 0.3) throw new Error("simulated: request failed");
  const res = await fetch(url, { ...init, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
  if (flaky.checked && Math.random() < 0.3) throw new Error("simulated: response lost");
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return (await res.json()) as T;
}

let pushing = false;
let pushTimer: ReturnType<typeof setTimeout> | undefined;
let backoff = 500;
let lastError = "";

function schedulePush(delay: number): void {
  if (pushTimer) clearTimeout(pushTimer);
  pushTimer = setTimeout(push, delay);
}

async function push(): Promise<void> {
  pushTimer = undefined;
  if (pushing) return;
  const batch = nextBatch(state);
  if (batch.length === 0) return;
  pushing = true;
  try {
    const res = await request<PushResponse>("/api/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ clientId, ops: batch }),
    });
    setState(applyPushResult(state, res.results));
    backoff = 500;
    lastError = "";
  } catch (e) {
    lastError = String(e instanceof Error ? e.message : e);
    backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
  } finally {
    pushing = false;
    render();
  }
  if (state.outbox.length > 0) schedulePush(lastError ? backoff : 0);
}

let pulling = false;
async function pull(): Promise<void> {
  if (pulling) return;
  pulling = true;
  try {
    const res = await request<PullResponse>(`/api/pull?since=${state.lastSeq}`);
    setState(applyPull(state, res));
  } catch (e) {
    lastError = String(e instanceof Error ? e.message : e);
    render();
  } finally {
    pulling = false;
  }
}

// ---- rendering ---------------------------------------------------------------

const list = document.getElementById("list") as HTMLUListElement;
const statusEl = document.getElementById("status") as HTMLSpanElement;
let editingId: string | null = null;

function render(): void {
  renderStatus();
  // Rebuilding the list while the user types in an edit box would steal focus; skip it then.
  if (editingId && document.activeElement?.classList.contains("edit")) return;
  const items = view(state, filter);
  list.replaceChildren(
    ...items.map((t) => {
      const li = document.createElement("li");
      li.classList.toggle("done", t.done);
      li.classList.toggle("pending", t.pending);

      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.checked = t.done;
      cb.addEventListener("change", () => act({ kind: "setDone", id: t.id, done: cb.checked }));
      li.append(cb);

      if (editingId === t.id) {
        const input = document.createElement("input");
        input.className = "edit";
        input.value = t.title;
        input.maxLength = 500;
        const finish = (save: boolean) => {
          if (editingId !== t.id) return;
          editingId = null;
          const title = input.value.trim();
          if (save && title && title !== t.title) act({ kind: "rename", id: t.id, title });
          else render();
        };
        input.addEventListener("keydown", (e) => {
          if (e.key === "Enter") finish(true);
          if (e.key === "Escape") finish(false);
        });
        input.addEventListener("blur", () => finish(true));
        li.append(input);
        queueMicrotask(() => input.focus());
      } else {
        const span = document.createElement("span");
        span.className = "title";
        span.textContent = t.title;
        span.title = "ダブルクリックで編集";
        span.addEventListener("dblclick", () => {
          editingId = t.id;
          render();
        });
        li.append(span);
      }

      const del = document.createElement("button");
      del.textContent = "削除";
      del.addEventListener("click", () => act({ kind: "delete", id: t.id }));
      li.append(del);
      return li;
    }),
  );

  for (const b of document.querySelectorAll<HTMLButtonElement>("#filters button")) {
    b.classList.toggle("active", b.dataset.filter === filter);
  }
}

function renderStatus(): void {
  const pending = state.outbox.length;
  statusEl.textContent =
    (pending ? `送信待ち ${pending} 件` : "同期済み") + (lastError ? `（直近のエラー: ${lastError}）` : "");
}

document.getElementById("new-form")!.addEventListener("submit", (e) => {
  e.preventDefault();
  const input = document.getElementById("new-title") as HTMLInputElement;
  const title = input.value.trim();
  if (!title) return;
  act({ kind: "create", id: crypto.randomUUID(), title });
  input.value = "";
});

for (const b of document.querySelectorAll<HTMLButtonElement>("#filters button")) {
  b.addEventListener("click", () => {
    filter = b.dataset.filter as Filter;
    render();
  });
}

render();
schedulePush(0);
pull();
setInterval(() => {
  pull();
  if (state.outbox.length > 0 && !pushing && !pushTimer) schedulePush(0);
}, PULL_INTERVAL_MS);
window.addEventListener("online", () => schedulePush(0));
