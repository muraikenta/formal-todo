import Theorems
/-!
# 各コマンドは頼まれたことをやる（この実験の発見）

`Theorems.lean` は「悪いことが起きない」ことを示す: 書き込みはすべて本人のもの、
他人の todo は変わらない、不変条件が保たれる。ところがそれだけなら、何でも断る
カーネルや、名前変更で新しいタイトルを無視するカーネルでも成り立ってしまう
（独立レビューで指摘された穴）。このファイルは残りの半分を述べる。

* 成功したコマンドが状態に何を残し、何を返すか（`*_effect`）
* 持ち主の正しい操作は必ず成功すること（`*_ok`）。断ってごまかすことはできない

`reachable_inv`（id は重複しない）と合わせると、「この id の todo が新しい状態にある」
ことで、その todo の中身がちょうど決まる。
-/
open Aeneas Aeneas.Std Result todo_kernel todo_kernel.Spec todo_kernel.Commands todo_kernel.Theorems H5iAppLib

namespace todo_kernel.Effects

/-! ## 成功したコマンドが残すもの -/

/-- `Add` は古いカウンタの値を新しい id として返し、その id とタイトルで本人の
未完了の todo を保存し、既存の todo はすべて残す（上書きしない）。 -/
theorem add_effect (a : Principal) (s : Snapshot) (t : alloc.vec.Vec U8) ws r
    (hinv : Inv (Snapshot.toSt s)) (h : transition a s (.Add t) = .ok (.Ok (ws, r))) :
    r = .Created s.counter.next_id ∧
      (⟨s.counter.next_id, a.user, t, false⟩ : Todo) ∈ (applyAll (Snapshot.toSt s) ws.val).todos ∧
      ∀ q ∈ (Snapshot.toSt s).todos, q ∈ (applyAll (Snapshot.toSt s) ws.val).todos := by
  obtain ⟨hr, -, cnt, -, hws⟩ := post_of_ok (add_spec a.user s t) h ws r rfl
  refine ⟨hr, ?_, ?_⟩ <;> rw [hws] <;> simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite]
  · exact mem_upsert_self _ _ _
  · intro q hq
    apply mem_upsert_of_ne hq
    intro hid
    have := hinv.fresh q hq
    simp only [Snapshot.toSt] at this
    rw [hid] at this
    exact absurd this (Nat.lt_irrefl _)

/-- `Rename` は `Done` を返し、その id の todo は本人のもので、新しいタイトルと
元の完了フラグを持つ。 -/
theorem rename_effect (a : Principal) (s : Snapshot) (id : U64) (ti : alloc.vec.Vec U8) ws r
    (h : transition a s (.Rename id ti) = .ok (.Ok (ws, r))) :
    r = .Done ∧ ∃ q, findTodo (Snapshot.toSt s) id.val = some q ∧
      (⟨id, a.user, ti, q.completed⟩ : Todo) ∈ (applyAll (Snapshot.toSt s) ws.val).todos := by
  obtain ⟨hr, -, q, hq, -, hws⟩ := post_of_ok (rename_spec a.user s id ti) h ws r rfl
  refine ⟨hr, q, hq, ?_⟩
  rw [hws]; simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite]
  exact mem_upsert_self _ _ _

/-- `SetDone` は `Done` を返し、その id の todo は指定どおりの完了フラグと、
元のタイトルと、本人という持ち主を持つ。 -/
theorem set_done_effect (a : Principal) (s : Snapshot) (id : U64) (d : Bool) ws r
    (h : transition a s (.SetDone id d) = .ok (.Ok (ws, r))) :
    r = .Done ∧ ∃ q, findTodo (Snapshot.toSt s) id.val = some q ∧
      (⟨id, a.user, q.title, d⟩ : Todo) ∈ (applyAll (Snapshot.toSt s) ws.val).todos := by
  obtain ⟨hr, q, hq, -, hws⟩ := post_of_ok (set_done_spec a.user s id d) h ws r rfl
  refine ⟨hr, q, hq, ?_⟩
  rw [hws]; simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite]
  exact mem_upsert_self _ _ _

/-- `Delete` は `Done` を返し、その id の todo は残らない。 -/
theorem delete_effect (a : Principal) (s : Snapshot) (id : U64) ws r
    (h : transition a s (.Delete id) = .ok (.Ok (ws, r))) :
    r = .Done ∧ ∀ t ∈ (applyAll (Snapshot.toSt s) ws.val).todos, t.id ≠ id := by
  obtain ⟨hr, -, hws⟩ := post_of_ok (delete_spec a.user s id) h ws r rfl
  refine ⟨hr, ?_⟩
  rw [hws]; simp only [applyAll, List.foldl_cons, List.foldl_nil, applyWrite]
  intro t ht
  simpa using (List.mem_filter.1 ht).2

/-! ## 持ち主の操作は成功する -/

theorem find_todo_eq (s : Snapshot) (id : U64) {q : Todo} (hq : findTodo (Snapshot.toSt s) id.val = some q) :
    find_todo s.todos id = ok (some q) :=
  eq_ok_of_spec (WP.spec_mono (find_todo_spec _ _) (fun o ho => by rw [ho]; exact hq))

theorem one_eq (w : Write) : ∃ v : alloc.vec.Vec Write, one w = ok v := ok_of (one_spec w)

/-- 持ち主は、存在する todo をいつでも完了（または未完了）にできる。 -/
theorem set_done_ok (a : Principal) (s : Snapshot) (id : U64) (d : Bool) {q : Todo}
    -- 前提 hq: その id の todo q がある。ho: q の持ち主は操作した人 a
    (hq : findTodo (Snapshot.toSt s) id.val = some q) (ho : q.owner = a.user) :
    -- 結論: 何かの書き込み ws をして成功し、返事は Done
    ∃ ws, transition a s (.SetDone id d) = ok (.Ok (ws, .Done)) := by
  obtain ⟨v, hv⟩ := one_eq (.PutTodo ⟨id, a.user, q.title, d⟩)
  exact ⟨v, by simp [transition, set_done, find_todo_eq s id hq, ho, hv]⟩

/-- 持ち主は、存在する todo をいつでも消せる。 -/
theorem delete_ok (a : Principal) (s : Snapshot) (id : U64) {q : Todo}
    (hq : findTodo (Snapshot.toSt s) id.val = some q) (ho : q.owner = a.user) :
    ∃ ws, transition a s (.Delete id) = ok (.Ok (ws, .Done)) := by
  obtain ⟨v, hv⟩ := one_eq (.DelTodo id)
  exact ⟨v, by simp [transition, delete, find_todo_eq s id hq, ho, hv]⟩

theorem title_ok_true (t : alloc.vec.Vec U8) (ht : titleOk t.val) : title_ok t = ok true :=
  eq_ok_of_spec (WP.spec_mono (title_ok_spec t) (fun b hb => by
    cases b
    · exact absurd (hb.2 ht) (by simp)
    · rfl))

/-- 持ち主は、存在する todo をいつでも正しいタイトルに変えられる。 -/
theorem rename_ok (a : Principal) (s : Snapshot) (id : U64) (ti : alloc.vec.Vec U8) {q : Todo}
    (hq : findTodo (Snapshot.toSt s) id.val = some q) (ho : q.owner = a.user) (ht : titleOk ti.val) :
    ∃ ws, transition a s (.Rename id ti) = ok (.Ok (ws, .Done)) := by
  obtain ⟨v, hv⟩ := one_eq (.PutTodo ⟨id, a.user, ti, q.completed⟩)
  exact ⟨v, by simp [transition, rename, find_todo_eq s id hq, ho, title_ok_true ti ht, u8vec_clone, hv]⟩

/-- id が尽きていなければ、誰でも正しいタイトルの todo を追加できる。 -/
theorem add_ok (a : Principal) (s : Snapshot) (t : alloc.vec.Vec U8) (ht : titleOk t.val)
    (hn : s.counter.next_id.val < 2 ^ 64 - 1) :
    ∃ ws, transition a s (.Add t) = ok (.Ok (ws, .Created s.counter.next_id)) := by
  have hne : s.counter.next_id ≠ core.num.U64.MAX := by
    intro he; rw [he] at hn; simp [core.num.U64.MAX, U64.rMax] at hn
  have hspec : add a.user s t ⦃ r => ∃ ws, r = .Ok (ws, .Created s.counter.next_id) ⦄ := by
    unfold add
    step*
    all_goals first
      | exact ⟨_, rfl⟩
      | (simp_all [core.num.U64.MAX, U64.rMax]; try scalar_tac)
      | exact absurd (b_post.2 ht) (by simp_all)
  obtain ⟨o, ho, ws, rfl⟩ := (WP.spec_equiv_exists _ _).1 hspec
  exact ⟨ws, by simp only [transition]; exact ho⟩

end todo_kernel.Effects
