import Model
/-!
差分テスト用の窓口。標準入力から1行ずつ「関数名 引数…」を読み、
モデルの答えを `ok 値` か `fail` で1行ずつ返す。
  例: `add 2 3` → `ok 5`、`sum_to 100000` → `fail`
-/

def answer (r : Option Nat) : String :=
  match r with
  | some v => s!"ok {v}"
  | none => "fail"

def handle (line : String) : String :=
  match (line.trimAscii.toString.splitOn " ").filter (· ≠ "") with
  | ["add", a, b] =>
    match a.toNat?, b.toNat? with
    | some a, some b => answer (Model.add a b)
    | _, _ => "error"
  | ["double_plus_one", x] =>
    match x.toNat? with
    | some x => answer (Model.doublePlusOne x)
    | none => "error"
  | ["sum_to", n] =>
    match n.toNat? with
    | some n => answer (Model.sumToFast n)   -- 仕様 sumTo と等しいことは Model.sumToFast_eq で証明済み
    | none => "error"
  | _ => "error"

partial def loop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  stdout.putStrLn (handle line)
  loop stdin stdout

def main : IO Unit := do
  loop (← IO.getStdin) (← IO.getStdout)
