// Entry point: serves the frontend (Bun HTML import, bundled on the fly) and the sync API.
import index from "../public/index.html";
import { handlePull, handlePush } from "./api";
import { TodoStore } from "./server-store";

const port = Number(process.env.PORT ?? 3457);
const dbPath = process.env.DB_PATH ?? "todo.db";
const store = new TodoStore(dbPath);

const server = Bun.serve({
  port,
  routes: {
    "/": index,
    "/api/push": { POST: (req) => handlePush(store, req) },
    "/api/pull": { GET: (req) => handlePull(store, req) },
  },
  fetch() {
    return new Response("Not found", { status: 404 });
  },
  error(err) {
    console.error(err);
    return new Response(JSON.stringify({ error: "internal error" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  },
});

console.log(`todo server: ${server.url} (db: ${dbPath}, pid: ${process.pid})`);
