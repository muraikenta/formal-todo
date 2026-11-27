import Commands
/-!
# todo アプリについての定理（「悪いことが起きない」側）

`writes_of` が `Commands.lean` をまとめる: 成功したコマンドがすることは5通りのどれか。
ほかの定理はこの5通りに場合分けするだけで、コードそのものは見ない。

ここにあるのは安全性（他人の todo に触れない、など）だけ。これだけだと「何もしない」
カーネルでも通ってしまうので、「頼んだことをやる」側は `Effects.lean` に置いた。
-/
open Aeneas Aeneas.Std Result todo_kernel todo_kernel.Spec todo_kernel.Commands H5iAppLib

namespace todo_kernel.Theorems

/-! ## 一覧 -/

/-- `List` は何も書かず、呼び出した本人の todo ちょうどを保存順で返す。
他人の todo は誰にも見えない。 -/
theorem list_own (a : Principal) (s : Snapshot) :
    transition a s .List ⦃ r => ∃ v, r = .Ok (alloc.vec.Vec.new Write, .Todos v) ∧
      v.val = mine (Snapshot.toSt s) a.user.val ⦄ := by
  simp only [transition]
  step*
  refine ⟨_, rfl, ?_⟩
  rw [v_post]
  simp only [mine, Snapshot.toSt]
  apply List.filter_congr
  intro t _
  simp [ownedBy]

/-! ## 成功したコマンドが書くもの -/

/-- 成功したコマンドが書くもの（5通り）。 -/
theorem writes_of (a : Principal) (s : Snapshot) (c : Command) ws r
    (h : transition a s c = .ok (.Ok (ws, r))) :
    let st := Snapshot.toSt s
    -- List: 何も書かない。
    ws.val = [] ∨
    -- Add: 次の id で未完了の todo を1つ、カウンタを1つ進める。
    (∃ t cnt, titleOk t.val ∧ cnt.next_id.val = st.next + 1 ∧
      ws.val = [.PutTodo ⟨s.counter.next_id, a.user, t, false⟩, .SetCounter cnt]) ∨
    -- Rename: 本人の todo のタイトルを変える。
    (∃ id t q, titleOk t.val ∧ findTodo st id.val = some q ∧ q.owner = a.user ∧
      ws.val = [.PutTodo ⟨id, a.user, t, q.completed⟩]) ∨
    -- SetDone: 本人の todo の完了フラグを変える。
    (∃ id d q, findTodo st id.val = some q ∧ q.owner = a.user ∧
      ws.val = [.PutTodo ⟨id, a.user, q.title, d⟩]) ∨
    -- Delete: 本人の todo を1つ消す。
    (∃ id q, findTodo st id.val = some q ∧ q.owner = a.user ∧ ws.val = [.DelTodo id]) := by
  intro st
  cases c with
  | Add t =>
    obtain ⟨-, ht, cnt, hc, hws⟩ := post_of_ok (add_spec a.user s t) h ws r rfl
    exact .inr (.inl ⟨t, cnt, ht, hc, hws⟩)
  | Rename id t =>
    obtain ⟨-, ht, q, hq, ha, hws⟩ := post_of_ok (rename_spec a.user s id t) h ws r rfl
    exact .inr (.inr (.inl ⟨id, t, q, ht, hq, ha, hws⟩))
  | SetDone id d =>
    obtain ⟨-, q, hq, ha, hws⟩ := post_of_ok (set_done_spec a.user s id d) h ws r rfl
    exact .inr (.inr (.inr (.inl ⟨id, d, q, hq, ha, hws⟩)))
  | Delete id =>
    obtain ⟨-, ⟨q, hq, ha⟩, hws⟩ := post_of_ok (delete_spec a.user s id) h ws r rfl
    exact .inr (.inr (.inr (.inr ⟨id, q, hq, ha, hws⟩)))
  | List =>
    obtain ⟨v, hv, -⟩ := post_of_ok (list_own a s) h
    left
    simp only [core.result.Result.Ok.injEq, Prod.mk.injEq] at hv
    rw [hv.1]
    rfl

/-- どのコマンドでもカーネルは落ちない（panic・オーバーフロー・範囲外アクセスなし）。 -/
theorem transition_total (a : Principal) (s : Snapshot) (c : Command) : ∃ r, transition a s c = ok r := by
  cases c
  · simp only [transition]; exact ok_of (add_spec _ _ _)
  · simp only [transition]; exact ok_of (rename_spec _ _ _ _)
  · simp only [transition]; exact ok_of (set_done_spec _ _ _ _)
  · simp only [transition]; exact ok_of (delete_spec _ _ _)
  · exact ok_of (list_own a s)

/-- h5i の決まった形（`H5iAppLib.Obligation.PanicFree`）での「落ちない」:
どの呼び出し人・状態・コマンドでも `transition` は値を返す（`[obligations] panic-free`）。 -/
theorem panic_free : H5iAppLib.Obligation.PanicFree transition :=
  H5iAppLib.Obligation.panicFree_of_total transition_total

theorem findTodo_mem {s : St} {id : Nat} {q : Todo} (h : findTodo s id = some q) :
    q ∈ s.todos ∧ q.id.val = id :=
  ⟨List.mem_of_find?_eq_some h, by simpa using List.find?_some h⟩

/-! ## 権限 -/

/-- 成功したコマンドの書き込みは、すべて権限のルール `allowed` で許されている
（コマンド実行前の状態で判断）。 -/
theorem authorized (a : Principal) (s : Snapshot) (c : Command) ws r
    (hinv : Inv (Snapshot.toSt s)) (h : transition a s c = .ok (.Ok (ws, r))) :
    ∀ w ∈ ws.val, allowed (Snapshot.toSt s) a.user.val w := by
  rcases writes_of a s c ws r h with
    hws | ⟨t, cnt, ht, hc, hws⟩ | ⟨tid, t, q, ht, hq, ha, hws⟩ | ⟨tid, d, q, hq, ha, hws⟩ |
    ⟨tid, q, hq, ha, hws⟩
  · -- List は何も書かない。
    simp [hws]
  · -- Add: 本人の新しい todo と、次のカウンタ値。
    rw [hws]; intro w hw
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hw
    rcases hw with rfl | rfl
    · exact ⟨rfl, ht, .inl rfl⟩
    · exact hc
  · -- Rename: 本人の todo。
    rw [hws]; intro w hw
    simp only [List.mem_singleton] at hw
    subst hw
    exact ⟨rfl, ht, .inr ⟨q, hq, by rw [ha]⟩⟩
  · -- SetDone: 本人の todo。タイトルは元から正しい。
    rw [hws]; intro w hw
    simp only [List.mem_singleton] at hw
    subst hw
    exact ⟨rfl, hinv.titles q (findTodo_mem hq).1, .inr ⟨q, hq, by rw [ha]⟩⟩
  · -- Delete: 本人の todo。
    rw [hws]; intro w hw
    simp only [List.mem_singleton] at hw
    subst hw
    exact ⟨q, hq, by rw [ha]⟩

/-! ## 不変条件 -/

/-- 新しいカウンタより小さい id の todo を書いても、不変条件は保たれる。 -/
theorem inv_put_todo {s : St} (hi : Inv s) (t : Todo) (n : Nat) (hn : s.next ≤ n)
    (hid : t.id.val < n) (ht : titleOk t.title.val) :
    Inv ⟨n, upsert (·.id) t s.todos⟩ where
  keys := nodup_map_upsert (·.id) (·.id) (fun _ _ => Iff.rfl) t s.todos hi.keys
  fresh z hz := by
    rcases mem_upsert_of hz with rfl | hz
    · exact hid
    · exact Nat.lt_of_lt_of_le (hi.fresh z hz) hn
  titles z hz := by
    rcases mem_upsert_of hz with rfl | hz
    · exact ht
    · exact hi.titles z hz

theorem inv_del_todo {s : St} (hi : Inv s) (id : U64) :
    Inv { s with todos := s.todos.filter (fun t => t.id ≠ id) } where
  keys := nodup_map_filter _ _ _ hi.keys
  fresh z hz := hi.fresh z (List.mem_filter.1 hz).1
  titles z hz := hi.titles z (List.mem_filter.1 hz).1

/-- 成功したコマンドは不変条件を保つ。 -/
theorem inv_preserved (a : Principal) (s : Snapshot) (c : Command) ws r
    (hinv : Inv (Snapshot.toSt s)) (h : transition a s c = .ok (.Ok (ws, r))) :
    Inv (applyAll (Snapshot.toSt s) ws.val) := by
  rcases writes_of a s c ws r h with
    hws | ⟨t, cnt, ht, hc, hws⟩ | ⟨tid, t, q, ht, hq, ha, hws⟩ | ⟨tid, d, q, hq, ha, hws⟩ |
    ⟨tid, q, hq, ha, hws⟩ <;> rw [hws] <;> simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite]
  · exact hinv
  · -- Add: 新しい id は古いカウンタの値で、新しいカウンタより小さい。
    exact inv_put_todo hinv _ cnt.next_id.val (by omega) (by simp [hc, Snapshot.toSt]) ht
  · -- Rename: 既存の todo の id なので、カウンタより小さい。
    obtain ⟨hm, hqid⟩ := findTodo_mem hq
    exact inv_put_todo hinv _ _ (Nat.le_refl _) (hqid ▸ hinv.fresh q hm) ht
  · -- SetDone: 同じく。タイトルは元の正しいもの。
    obtain ⟨hm, hqid⟩ := findTodo_mem hq
    exact inv_put_todo hinv _ _ (Nat.le_refl _) (hqid ▸ hinv.fresh q hm) (hinv.titles q hm)
  · exact inv_del_todo hinv tid

theorem init_inv : Inv init := by
  constructor <;> simp [init]

/-- アプリがたどり着けるどの状態でも、不変条件が成り立つ。 -/
theorem reachable_inv {s : St} (h : Reachable s) : Inv s := by
  induction h with
  | init => exact init_inv
  | step _ ht ih => exact inv_preserved _ _ _ _ _ ih ht

/-- 到達できる状態での `authorized`（不変条件を前提に置かなくてよい形）。 -/
theorem authorized_reachable (a : Principal) (s : Snapshot) (c : Command) ws r
    (hr : Reachable (Snapshot.toSt s)) (h : transition a s c = .ok (.Ok (ws, r))) :
    ∀ w ∈ ws.val, allowed (Snapshot.toSt s) a.user.val w :=
  authorized a s c ws r (reachable_inv hr) h

/-! ## 1歩の前後で言えること -/

theorem same_todo {s : St} (hi : Inv s) {p q : Todo} (hp : p ∈ s.todos) (hq : q ∈ s.todos) (h : p.id = q.id) :
    p = q :=
  List.inj_on_of_nodup_map hi.keys hp hq h

/-- どのコマンドも todo の持ち主を変えない。 -/
theorem owner_kept (a : Principal) (s : Snapshot) (c : Command) ws r
    (hinv : Inv (Snapshot.toSt s)) (h : transition a s c = .ok (.Ok (ws, r))) :
    ∀ q ∈ (Snapshot.toSt s).todos, ∀ p ∈ (applyAll (Snapshot.toSt s) ws.val).todos,
      p.id = q.id → p.owner = q.owner := by
  intro q hq p hp hid
  rcases writes_of a s c ws r h with
    hws | ⟨t, cnt, ht, hc, hws⟩ | ⟨tid, t, q', ht, hq', ha, hws⟩ | ⟨tid, d, q', hq', ha, hws⟩ |
    ⟨tid, q', hq', ha, hws⟩ <;> rw [hws] at hp <;>
    simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite] at hp
  · rw [same_todo hinv hp hq hid]
  · -- Add: 新しい todo の id は未使用なので `q` ではない。
    rcases mem_upsert_of hp with rfl | hp
    · have := hinv.fresh q hq
      simp only [Snapshot.toSt] at this
      rw [← hid] at this
      exact absurd this (Nat.lt_irrefl _)
    · rw [same_todo hinv hp hq hid]
  · -- Rename: 名前を変える todo の持ち主は本人。
    rcases mem_upsert_of hp with rfl | hp
    · obtain ⟨hm, hqid⟩ := findTodo_mem hq'
      rw [same_todo hinv hm hq ((u64_val_eq _ _).1 hqid ▸ hid)] at ha
      exact ha.symm
    · rw [same_todo hinv hp hq hid]
  · -- SetDone: 同じく。
    rcases mem_upsert_of hp with rfl | hp
    · obtain ⟨hm, hqid⟩ := findTodo_mem hq'
      rw [same_todo hinv hm hq ((u64_val_eq _ _).1 hqid ▸ hid)] at ha
      exact ha.symm
    · rw [same_todo hinv hp hq hid]
  · rw [same_todo hinv (List.mem_filter.1 hp).1 hq hid]

/-- 絞り込みの外にある行を upsert しても、同じキーの行が絞り込みの中に無ければ、
絞り込みの結果は変わらない。 -/
theorem filter_upsert_of_mem {α κ : Type} [DecidableEq κ] (k : α → κ) (p : α → Bool) (x : α) (l : List α)
    (hx : p x = false) (hk : ∀ y ∈ l, k y = k x → p y = false) : (upsert k x l).filter p = l.filter p := by
  induction l with
  | nil => simp [upsert, hx]
  | cons y ys ih =>
    unfold upsert
    split
    · rename_i hy
      simp [hx, hk y List.mem_cons_self hy]
    · simp only [List.filter_cons, ih (fun z hz => hk z (List.mem_cons_of_mem _ hz))]

/-- 本人の todo への書き込みは、ほかのユーザーの todo に影響しない。 -/
theorem mine_put_own {s : St} (hi : Inv s) (u : Nat) {a : U64} (hu : u ≠ a.val) (t : Todo)
    (ho : t.owner = a) (hk : ∀ y ∈ s.todos, y.id = t.id → y.owner = a) :
    (upsert (·.id) t s.todos).filter (fun z => z.owner.val = u) = mine s u := by
  apply filter_upsert_of_mem
  · simp [ho, Ne.symm hu]
  · intro y hy hid
    simp [hk y hy hid, Ne.symm hu]

/-- どのコマンドが成功した後も、ほかのユーザーの todo は前とまったく同じ。 -/
theorem others_unchanged (a : Principal) (s : Snapshot) (c : Command) ws r
    (hinv : Inv (Snapshot.toSt s)) (h : transition a s c = .ok (.Ok (ws, r)))
    (u : Nat) (hu : u ≠ a.user.val) :
    mine (applyAll (Snapshot.toSt s) ws.val) u = mine (Snapshot.toSt s) u := by
  rcases writes_of a s c ws r h with
    hws | ⟨t, cnt, ht, hc, hws⟩ | ⟨tid, t, q, ht, hq, ha, hws⟩ | ⟨tid, d, q, hq, ha, hws⟩ |
    ⟨tid, q, hq, ha, hws⟩ <;> rw [hws] <;> simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite]
  -- （List は何も書かないので `simp only` の時点で閉じている。）
  · -- Add: 既存の todo に新しい id のものは無い。
    simp only [mine]
    apply mine_put_own hinv u hu _ rfl
    intro y hy hid
    have := hinv.fresh y hy
    simp only [Snapshot.toSt] at this hid
    rw [hid] at this
    exact absurd this (Nat.lt_irrefl _)
  all_goals
    obtain ⟨hm, hqid⟩ := findTodo_mem hq
    -- この id の todo は `q` だけで、その持ち主は本人。
    have hown : ∀ y ∈ (Snapshot.toSt s).todos, y.id = tid → y.owner = a.user := by
      intro y hy hid
      rw [same_todo hinv hy hm (hid.trans ((u64_val_eq _ _).1 hqid).symm)]; exact ha
  · simp only [mine]; exact mine_put_own hinv u hu ⟨tid, a.user, t, q.completed⟩ rfl hown
  · simp only [mine]; exact mine_put_own hinv u hu ⟨tid, a.user, q.title, d⟩ rfl hown
  · -- Delete: 消す todo は本人のもの。
    simp only [mine]
    rw [List.filter_filter]
    apply List.filter_congr
    intro y hy
    by_cases hid : y.id = tid
    · have := hown y hy hid
      simp [hid, this, Ne.symm hu]
    · simp [hid]

end todo_kernel.Theorems
