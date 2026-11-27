import TodoKernel
import H5iAppLib
/-!
# この todo アプリがすべきこと（仕様）

レビューする人が読むファイル。誰がどの todo を書いてよいか、書き込みが状態を
どう変えるか、いつも成り立つ決まり、一覧に何が出るかを、ただのリストと自然数で書く。
証明はコードをこの仕様に合わせるだけなので、ここが間違っていると誰も気づけない。
-/
open Aeneas Aeneas.Std todo_kernel

namespace todo_kernel.Spec

/-- 状態をリストで見たもの: 次に払い出す todo の id と、todo の一覧。 -/
structure St where
  next : Nat
  todos : List Todo

def Snapshot.toSt (s : Snapshot) : St :=
  ⟨s.counter.next_id.val, s.todos.val⟩

def findTodo (s : St) (id : Nat) : Option Todo :=
  s.todos.find? (fun t => t.id.val = id)

/-- タイトルは空でなく、140 バイト以下。 -/
def titleOk (t : List U8) : Prop :=
  0 < t.length ∧ t.length ≤ 140

/-- ユーザー `u` が持っている todo。 -/
def mine (s : St) (u : Nat) : List Todo :=
  s.todos.filter (fun t => t.owner.val = u)

/-- 権限のルール: 状態 `s` で、ユーザー `u` は書き込み `w` をしてよいか。 -/
def allowed (s : St) (u : Nat) : Write → Prop
  | .PutTodo t =>
    -- `u` の新しい todo か、`u` 自身の todo の変更。持ち主は変わらない。
    t.owner.val = u ∧ titleOk t.title.val ∧
      (t.id.val = s.next ∨ ∃ q, findTodo s t.id.val = some q ∧ q.owner.val = u)
  | .DelTodo id =>
    -- 持ち主が、存在する todo を消す。
    ∃ q, findTodo s id.val = some q ∧ q.owner.val = u
  | .SetCounter c => c.next_id.val = s.next + 1

/-- 書き込み1つが状態をどう変えるか。`H5iAppLib.upsert` は同じキーの行を
置き換え、無ければ末尾に足す（SQL の INSERT … ON CONFLICT DO UPDATE）。 -/
def applyWrite (s : St) : Write → St
  | .PutTodo t => { s with todos := H5iAppLib.upsert (·.id) t s.todos }
  | .DelTodo id => { s with todos := s.todos.filter (fun t => t.id ≠ id) }
  | .SetCounter c => { s with next := c.next_id.val }

def applyAll (s : St) (ws : List Write) : St := ws.foldl applyWrite s

/-- アプリがたどり着けるどの状態でも成り立つ決まり（不変条件）。 -/
structure Inv (s : St) : Prop where
  /-- id が重複しない。 -/
  keys : (s.todos.map (·.id)).Nodup
  /-- どの id も次に払い出す id より小さい（＝id を使い回さない）。 -/
  fresh : ∀ t ∈ s.todos, t.id.val < s.next
  /-- どのタイトルも正しい長さ。 -/
  titles : ∀ t ∈ s.todos, titleOk t.title.val

def init : St := ⟨0, []⟩

/-- 空のアプリから、成功したコマンドだけでたどり着ける状態。 -/
inductive Reachable : St → Prop
  | init : Reachable init
  | step {a s c ws r} : Reachable (Snapshot.toSt s) → transition a s c = .ok (.Ok (ws, r)) →
      Reachable (applyAll (Snapshot.toSt s) ws.val)

end todo_kernel.Spec
