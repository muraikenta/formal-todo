// 検証器（mbt.mjs）をわざと壊したアプリで試す: よくある書き間違いを1つずつ入れた版を作り、
// モデルベーステストが全部を「食い違い」として拾えるかを数える。元の版は通ることも確かめる。
//   node mutate.mjs
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const src = readFileSync("app/todo-core.mjs", "utf8");
const MUTANTS = [
  ["id を件数で振る", "{ id: state.nextId, title, done: false }", "{ id: state.todos.length, title, done: false }"],
  ["追加で nextId を進め忘れる", "nextId: state.nextId + 1,", "nextId: state.nextId,"],
  ["空欄も追加できてしまう", 'if (title === "") return state; // 空欄は弾く', ""],
  ["空欄で弾いたのに nextId だけ進む", 'if (title === "") return state; // 空欄は弾く', 'if (title === "") return { ...state, nextId: state.nextId + 1 };'],
  ["追加を先頭に入れる", "todos: [...state.todos, { id: state.nextId, title, done: false }]", "todos: [{ id: state.nextId, title, done: false }, ...state.todos]"],
  ["編集で空欄にしても消さない", 'if (title === "") return reduce(state, { type: "remove", id: action.id }); // 空欄にしたら削除', ""],
  ["全部切り替えが1件ずつ反転", "({ ...t, done: target })", "({ ...t, done: !t.done })"],
  ["全部切り替えの判定が some", "!state.todos.every((t) => t.done)", "!state.todos.some((t) => t.done)"],
  ["完了済みを消すが逆", "todos: state.todos.filter((t) => !t.done)", "todos: state.todos.filter((t) => t.done)"],
  ["削除が id ではなく位置で消す", "state.todos.filter((t) => t.id !== action.id)", "state.todos.filter((t, i) => i !== action.id)"],
  ["無い id の切り替えで落ちる", "todos: state.todos.map((t) => (t.id === action.id ? { ...t, done: !t.done } : t)),",
    "todos: (state.todos.find((t) => t.id === action.id).done, state.todos.map((t) => (t.id === action.id ? { ...t, done: !t.done } : t))),"],
  ["編集が全件の題名を変える", "state.todos.map((t) => (t.id === action.id ? { ...t, title } : t))", "state.todos.map((t) => ({ ...t, title }))"],
  ["5件目以降を弾く", 'if (title === "") return state; // 空欄は弾く', 'if (title === "" || state.todos.length >= 4) return state;'],
  ["id を 4 で巡回させる", "{ id: state.nextId, title, done: false }", "{ id: state.nextId % 4, title, done: false }"],
  ["追加で空白を取らない", 'case "add": {\n      const title = (action.title ?? "").trim();', 'case "add": {\n      const title = action.title ?? "";'],
  ["編集で空白を取らない", 'case "edit": {\n      const title = (action.title ?? "").trim();', 'case "edit": {\n      const title = action.title ?? "";'],
  ["題名を20文字で切る", "{ id: state.nextId, title, done: false }", "{ id: state.nextId, title: title.slice(0, 20), done: false }"],
  ["題名を小文字にする", "{ id: state.nextId, title, done: false }", "{ id: state.nextId, title: title.toLowerCase(), done: false }"],
  ["残り件数が完了済みを数える", "return state.todos.filter((t) => !t.done).length;", "return state.todos.filter((t) => t.done).length;"],
];

const dir = mkdtempSync(join(tmpdir(), "todo-mutants-"));
const run = (core) => spawnSync("node", ["mbt.mjs", `--core=${core}`, "--quiet"], { encoding: "utf8" });

const base = run("app/todo-core.mjs");
console.log(`元の版: ${base.status === 0 ? "通る" : "落ちる（おかしい）"}`);
let caught = 0;
for (const [name, from, to] of MUTANTS) {
  const n = src.split(from).length - 1;
  if (n !== 1) throw new Error(`「${name}」の置き換え元が ${n} 箇所（1箇所のはず）。元のコードが変わった`);
  const file = join(dir, `${MUTANTS.findIndex((m) => m[0] === name)}.mjs`);
  writeFileSync(file, src.replace(from, to));
  const r = run(file);
  const hit = r.status !== 0;
  if (hit) caught++;
  const where = (r.stderr.split("\n")[0] ?? "").replace(/^食い違い \d+ 本。最初: /, "");
  console.log(`${hit ? "検出" : "見逃し"}  ${name}${hit ? `  （${where}）` : ""}`);
}
console.log(`\n${caught}/${MUTANTS.length} を検出`);
process.exit(base.status === 0 && caught === MUTANTS.length ? 0 : 1);
