// 仕様の変異テスト: todo.qnt の操作の中身を1か所ずつ「ありがちな書き間違い」に変え、
// 不変条件 safety が全部を違反として拾えるかを数える（不変条件が弱いと、誤った仕様が TLC を通ってしまう）。
//   node mutate-spec.mjs
// 判定: TLC（todo3 を全網羅）か quint run（todo7・ランダム 3000 本）のどちらかが違反を出せば「検出」。
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const src = readFileSync("todo.qnt", "utf8");
const M = [
  ["toggle が何もしない", "todos' = mapTodos(todos, t => if (t.id == id) { ...t, done: not(t.done) } else t),", "todos' = todos,"],
  ["toggle が2件変える", "if (t.id == id) { ...t, done: not(t.done) }", "if (t.id == id or t.id == id + 1) { ...t, done: not(t.done) }"],
  ["edit が done も反転する", "{ ...t, title: title }", "{ ...t, title: title, done: not(t.done) }"],
  ["edit が題名を変えない", "if (t.id == id) { ...t, title: title } else t", "t"],
  ["edit が全件の題名を変える", "if (t.id == id) { ...t, title: title } else t", "{ ...t, title: title }"],
  ["edit で空欄にしても消さない", "todos' = if (title == \"\") todos.select(t => t.id != id)", "todos' = if (title == \"\") todos"],
  ["remove が何もしない", "todos' = todos.select(t => t.id != id),\n    nextId' = nextId,\n    record(\"remove\"", "todos' = todos,\n    nextId' = nextId,\n    record(\"remove\""],
  ["remove が全件消す", "todos' = todos.select(t => t.id != id),\n    nextId' = nextId,\n    record(\"remove\"", "todos' = List(),\n    nextId' = nextId,\n    record(\"remove\""],
  ["remove が nextId を戻す", "nextId' = nextId,\n    record(\"remove\"", "nextId' = if (nextId > 0) nextId - 1 else 0,\n    record(\"remove\""],
  ["clearCompleted が全部消す", "todos' = todos.select(t => not(t.done))", "todos' = List()"],
  ["clearCompleted が先頭の完了済みを残す", "todos' = todos.select(t => not(t.done))", "todos' = todos.select(t => not(t.done) or t.id == 0)"],
  ["toggleAll が常に全部未完了", "val target = not(allDone(todos))", "val target = false"],
  ["toggleAll が1件ずつ反転", "t => { ...t, done: target }", "t => { ...t, done: not(t.done) }"],
  ["add が完了済みで追加", "{ id: newId, title: title, done: false }", "{ id: newId, title: title, done: true }"],
  ["add が題名を取り違える", "{ id: newId, title: title, done: false }", "{ id: newId, title: \"milk\", done: false }"],
  ["add が生の入力を保存", "{ id: newId, title: title, done: false }", "{ id: newId, title: raw, done: false }"],
  ["add が追加せず nextId だけ進む", "todos' = todos.append({ id: newId, title: title, done: false })", "todos' = todos"],
  ["空欄の add で nextId が進む", "all { todos' = todos, nextId' = nextId }", "all { todos' = todos, nextId' = nextId + 1 }"],
  ["add が nextId を2進める", "nextId' = nextId + 1,", "nextId' = nextId + 2,"],
  ["add が先頭に入れる", "todos.append({ id: newId, title: title, done: false })", "List({ id: newId, title: title, done: false }).concat(todos)"],
];

const dir = mkdtempSync(join(tmpdir(), "todo-spec-mutants-"));
const q = (file, ...args) => spawnSync("quint", [...args, file], { encoding: "utf8" });
const violated = (r) => /violation\]|Invariant .* is violated|counterexample/.test(r.stdout + r.stderr);

const baseRun = q("todo.qnt", "run", "--main=todo7", "--invariant=safety", "--max-steps=30", "--max-samples=3000", "--seed=0x5eed");
const baseTlc = q("todo.qnt", "verify", "--main=todo3", "--backend=tlc", "--invariant=safety");
const baseOk = !violated(baseRun) && !violated(baseTlc) && baseRun.status === 0 && baseTlc.status === 0;
console.log(`元の仕様: ${baseOk ? "違反なし" : "違反あり（おかしい）"}`);

let caught = 0;
M.forEach(([name, from, to], i) => {
  const n = src.split(from).length - 1;
  if (n !== 1) throw new Error(`「${name}」の置き換え元が ${n} 箇所（1箇所のはず）`);
  const file = join(dir, `m${i}.qnt`);
  writeFileSync(file, src.replace(from, to));
  const tc = q(file, "typecheck");
  if (tc.status !== 0) throw new Error(`「${name}」が型検査を通らない: ${tc.stderr.slice(0, 300)}`);
  const run = q(file, "run", "--main=todo7", "--invariant=safety", "--max-steps=30", "--max-samples=3000", "--seed=0x5eed");
  let how = violated(run) ? "quint run" : "";
  if (!how) {
    const tlc = q(file, "verify", "--main=todo3", "--backend=tlc", "--invariant=safety");
    how = violated(tlc) ? "TLC" : "";
  }
  if (how) caught++;
  console.log(`${how ? "検出" : "見逃し"}  ${name}${how ? `（${how}）` : ""}`);
});
console.log(`\n${caught}/${M.length} を検出`);
process.exit(baseOk && caught === M.length ? 0 : 1);
