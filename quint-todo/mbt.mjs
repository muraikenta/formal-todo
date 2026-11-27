// モデルベーステスト: Quint が出した実行列（ITF トレース）を、アプリの中身に1歩ずつ流して状態を突き合わせる。
//   node mbt.mjs [--core=app/todo-core.mjs] [--traces=traces] [--quiet]
// 1本でも食い違えば exit 1。トレースが0本・1歩も比べていないときも exit 1（0件を成功と読まない）。
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const args = Object.fromEntries(
  process.argv.slice(2).map((a) => {
    const [k, v] = a.replace(/^--/, "").split("=");
    return [k, v ?? true];
  }),
);
const corePath = resolve(args.core ?? "app/todo-core.mjs");
const tracesDir = resolve(args.traces ?? "traces");
const { initialState, reduce, remaining } = await import(pathToFileURL(corePath).href);

// ITF の値を JS の値に戻す（{"#bigint": "3"} → 3 など）
function fromItf(v) {
  if (Array.isArray(v)) return v.map(fromItf);
  if (v && typeof v === "object") {
    if ("#bigint" in v) return Number(v["#bigint"]);
    if ("#tup" in v) return v["#tup"].map(fromItf);
    if ("#set" in v) return v["#set"].map(fromItf);
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fromItf(x)]));
  }
  return v;
}
// モデルの変数名は "todo4::todo::todos" のように前に module 名が付くので、末尾で引く
const pick = (s, name) => {
  const key = Object.keys(s).find((k) => k === name || k.endsWith(`::${name}`));
  if (key === undefined) throw new Error(`トレースに変数 ${name} が無い`);
  return fromItf(s[key]);
};
// 比べるのは todos・nextId と、画面に出る「残り N 件」（remaining）。モデル側の残り件数は todos から数える
const norm = (st, left) => JSON.stringify({ todos: st.todos.map(({ id, title, done }) => ({ id, title, done })), nextId: st.nextId, remaining: left });
const implView = (st) => norm(st, remaining(st));
const modelView = (st) => norm(st, st.todos.filter((t) => !t.done).length);

const files = readdirSync(tracesDir).filter((f) => f.endsWith(".itf.json")).sort();
let steps = 0;
const actionCount = {};
const changedCount = {}; // 状態が実際に変わった歩（無い id への操作などの空振りを除く）
const failures = [];
for (const f of files) {
  const { states } = JSON.parse(readFileSync(join(tracesDir, f), "utf8"));
  let impl = initialState();
  const model0 = { todos: pick(states[0], "todos"), nextId: pick(states[0], "nextId") };
  if (implView(impl) !== modelView(model0)) {
    failures.push({ file: f, step: 0, action: "init", impl: implView(impl), model: modelView(model0) });
    continue;
  }
  for (let i = 1; i < states.length; i++) {
    const s = states[i];
    const type = s["mbt::actionTaken"];
    const picks = fromItf(s["mbt::nondetPicks"]);
    const arg = (n) => (picks[n]?.tag === "Some" ? picks[n].value : undefined);
    // Quint の action の引数と同じものを渡す（使わない引数はアプリ側が無視する）
    const action = { type, id: arg("id"), title: arg("raw") };
    const before = implView(impl);
    try {
      impl = reduce(impl, action);
    } catch (e) {
      failures.push({ file: f, step: i, action: JSON.stringify(action), impl: `例外: ${e.message}`, model: "" });
      break;
    }
    const model = { todos: pick(s, "todos"), nextId: pick(s, "nextId") };
    steps++;
    actionCount[type] = (actionCount[type] ?? 0) + 1;
    if (implView(impl) !== before) changedCount[type] = (changedCount[type] ?? 0) + 1;
    if (implView(impl) !== modelView(model)) {
      failures.push({ file: f, step: i, action: JSON.stringify(action), impl: implView(impl), model: modelView(model) });
      break;
    }
  }
}

if (!args.quiet) {
  console.log(`トレース ${files.length} 本 / 突き合わせた歩数 ${steps}`);
  console.log(`操作ごとの歩数: ${JSON.stringify(actionCount)}`);
  console.log(`うち状態が変わった歩: ${JSON.stringify(changedCount)}`);
}
if (files.length === 0 || steps === 0) {
  console.error("トレースが無い（0件は成功ではない）");
  process.exit(1);
}
if (failures.length > 0) {
  const f0 = failures[0];
  console.error(`食い違い ${failures.length} 本。最初: ${f0.file} の ${f0.step} 歩目 ${f0.action}`);
  console.error(`  アプリ: ${f0.impl}`);
  console.error(`  モデル: ${f0.model}`);
  process.exit(1);
}
console.log("全歩一致");
