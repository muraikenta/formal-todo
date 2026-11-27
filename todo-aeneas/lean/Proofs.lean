import TodoKernel
import Spec
/-!
# Rust の実装が仕様どおりであることの証明

- 仕様: `Spec.lean`（人が先に書く。実装を見ない）
- 実装: `../kernel/src/lib.rs` を Charon → Aeneas で自動翻訳した `TodoKernel.lean`（手で書いていない）
- ここ: Rust の状態 `Todos` を仕様の `State` に読み替える関数 `abs` を決め、
  「Rust で操作してから読み替えた結果 ＝ 読み替えてから仕様で操作した結果」をすべての状態で示す。
  一致が示せれば、仕様の上で証明した認可の性質（`Spec.toggle_others` など）が Rust にもそのまま当てはまる（最後の節）

記法: `f x ⦃ y => P y ⦄` は「f x は失敗（panic）せずに値 y を返し、y は P を満たす」。
-/
open Aeneas Aeneas.Std Result
namespace todo_kernel

/-- Rust の todo 1件を仕様の todo に読み替える（u32 の id・持ち主は自然数に）。 -/
def absTodo (t : Todo) : Spec.Todo := ⟨t.id.val, t.owner.val, t.title, t.done⟩

/-- Rust の状態を仕様の状態に読み替える。 -/
def abs (t : Todos) : Spec.State := ⟨t.items.val.map absTodo, t.next_id.val⟩

theorem u32_max_eq : U32.max = Spec.MaxId := by
  simp [U32.max_def, U32.numBits_def, Spec.MaxId]

theorem u32_ne_iff (a b : U32) : a ≠ b ↔ a.val ≠ b.val := by
  constructor
  · intro h h'; exact h (UScalar.eq_of_val_eq h')
  · intro h h'; exact h (by rw [h'])

theorem u32_eq_iff (a b : U32) : a = b ↔ a.val = b.val := by
  have := u32_ne_iff a b; tauto

/-- 自然数に読み替えてから比べても、u32 のまま比べても同じ。 -/
@[simp] theorem u32_beq_val (a b : U32) : (a.val == b.val) = (a == b) := by
  by_cases h : a = b
  · subst h; simp
  · have := (u32_ne_iff a b).mp h; simp [h, this]

@[simp] theorem mine_abs (u id : U32) (x : Todo) :
    Spec.mine u.val id.val (absTodo x) = (x.id == id && x.owner == u) := by
  simp [Spec.mine, absTodo]

/-! ## new: 空の状態を作る -/
theorem new_correct : new ⦃ t => abs t = Spec.empty ⦄ := by
  unfold new
  simp [abs, Spec.empty]

/-! ## add: 仕様どおりに足す（不変条件があれば失敗しない） -/

/-- 不変条件があれば、todo の件数は next_id 以下（id は重複せず、どれも next_id 未満だから）。
  これで「Vec に push しても長さの上限を超えない」が言える。 -/
theorem length_le_nextId (s : Spec.State) (h : Spec.Inv s) : s.items.length ≤ s.nextId := by
  obtain ⟨hnd, hlt, -⟩ := h
  have h1 : (s.items.map (·.id)).toFinset ⊆ Finset.range s.nextId := by
    intro x hx
    simp only [List.mem_toFinset, List.mem_map] at hx
    obtain ⟨t, ht, rfl⟩ := hx
    simpa using hlt t ht
  have := Finset.card_le_card h1
  rw [List.toFinset_card_of_nodup hnd] at this
  simpa using this

theorem max_val : core.num.U32.MAX.val = Spec.MaxId := by
  simp [core.num.U32.MAX, U32.rMax, Spec.MaxId]

-- 前提 hinv: 今の状態を読み替えたものが不変条件 Inv を満たすなら
theorem add_correct (t : Todos) (user : U32) (title : String) (hinv : Spec.Inv (abs t)) :
    -- Rust の add は panic せず、返り値 r も新しい状態 t' も仕様の add と同じ
    add t user title ⦃ r t' => r.map (·.val) = (Spec.add (abs t) user.val title).1 ∧
                         abs t' = (Spec.add (abs t) user.val title).2 ⦄ := by
  unfold add
  split
  · rename_i h
    have : (abs t).nextId = Spec.MaxId := by
      simp only [abs]; rw [h, max_val]
    simp [Spec.add, this]
  · rename_i h
    have hne : (abs t).nextId ≠ Spec.MaxId := by
      intro h'; apply h
      apply UScalar.eq_of_val_eq
      rw [max_val]; exact h'
    have hlt : t.next_id.val < U32.max := by
      have h1 : t.next_id.val ≤ U32.max := by scalar_tac
      rw [u32_max_eq] at h1 ⊢
      simp only [abs] at hne
      omega
    have hlen : t.items.length < Usize.max := by
      have h1 := length_le_nextId _ hinv
      have h2 : U32.max ≤ Usize.max := by scalar_tac
      simp only [abs, List.length_map] at h1
      show t.items.val.length < Usize.max
      omega
    step as ⟨ v, hv ⟩
    step as ⟨ i, hi ⟩
    simp only [Spec.add, hne, ite_false, Option.map_some]
    simp [abs, hv, hi, absTodo]

/-! ## open_count: user の未完了の件数を数える -/
theorem open_count_loop_spec (t : Todos) (user : U32) (count i : Usize)
    (hi : i.val ≤ t.items.length)
    (hc : count.val = ((t.items.val.take i.val).filter (fun x => !x.done && x.owner == user)).length) :
    open_count_loop t user count i ⦃ r =>
      r.val = (t.items.val.filter (fun x => !x.done && x.owner == user)).length ⦄ := by
  unfold open_count_loop
  apply loop.spec_decr_nat
    (measure := fun (p : Usize × Usize) => t.items.length - p.2.val)
    (inv := fun (p : Usize × Usize) => p.2.val ≤ t.items.length ∧
      p.1.val = ((t.items.val.take p.2.val).filter (fun x => !x.done && x.owner == user)).length)
  · rintro ⟨c, j⟩ ⟨hj, hc⟩
    simp only at hj hc ⊢
    unfold open_count_loop.body
    dsimp only
    split
    · rename_i hlt
      have hlt : j.val < t.items.val.length := by scalar_tac
      step as ⟨ x, hx ⟩
      have htake : t.items.val.take (j.val + 1) = t.items.val.take j.val ++ [x] := by
        rw [hx]; exact (List.take_concat_get' _ _ (by simpa using hlt)).symm
      have hcle : c.val ≤ j.val := by
        rw [hc]; exact (List.length_filter_le _ _).trans (by simp)
      split
      · rename_i hd
        step as ⟨ j1, hj1 ⟩
        refine ⟨by scalar_tac, ?_, by scalar_tac⟩
        rw [hj1, htake]; simp [hc, hd]
      · rename_i hd
        split
        · rename_i ho
          step as ⟨ c1, hc1 ⟩
          step as ⟨ j1, hj1 ⟩
          refine ⟨by scalar_tac, ?_, by scalar_tac⟩
          rw [hj1, htake]; simp [hc, hd, hc1, ho]
        · rename_i ho
          step as ⟨ j1, hj1 ⟩
          refine ⟨by scalar_tac, ?_, by scalar_tac⟩
          rw [hj1, htake]; simp [hc, hd, ho]
    · rename_i hge
      have : j.val = t.items.length := by scalar_tac
      simp [hc, this]
  · exact ⟨hi, hc⟩

theorem open_count_correct (t : Todos) (user : U32) :
    open_count t user ⦃ r => r.val = Spec.openCount (abs t) user.val ⦄ := by
  unfold open_count
  have := open_count_loop_spec t user 0#usize 0#usize (by simp) (by simp)
  apply WP.spec_mono this
  intro r hr
  rw [hr]
  simp [Spec.openCount, abs, List.filter_map, Function.comp_def, absTodo]

/-! ## visible_ids: user に見せてよい id を集める -/
theorem visible_ids_loop_spec (t : Todos) (user : U32) (ids : alloc.vec.Vec U32) (i : Usize)
    (hi : i.val ≤ t.items.length)
    (hids : ids.val = ((t.items.val.take i.val).filter (·.owner == user)).map (·.id)) :
    visible_ids_loop t user ids i ⦃ r =>
      r.val = (t.items.val.filter (·.owner == user)).map (·.id) ⦄ := by
  unfold visible_ids_loop
  apply loop.spec_decr_nat
    (measure := fun (p : alloc.vec.Vec U32 × Usize) => t.items.length - p.2.val)
    (inv := fun (p : alloc.vec.Vec U32 × Usize) => p.2.val ≤ t.items.length ∧
      p.1.val = ((t.items.val.take p.2.val).filter (·.owner == user)).map (·.id))
  · rintro ⟨ids, j⟩ ⟨hj, hids⟩
    simp only at hj hids ⊢
    unfold visible_ids_loop.body
    dsimp only
    split
    · rename_i hlt
      have hlt : j.val < t.items.val.length := by scalar_tac
      step as ⟨ x, hx ⟩
      have htake : t.items.val.take (j.val + 1) = t.items.val.take j.val ++ [x] := by
        rw [hx]; exact (List.take_concat_get' _ _ (by simpa using hlt)).symm
      have hle : ids.val.length ≤ j.val := by
        rw [hids, List.length_map]; exact (List.length_filter_le _ _).trans (by simp)
      split
      · rename_i ho
        have : ids.val.length < Usize.max := by scalar_tac
        step as ⟨ ids1, hids1 ⟩
        step as ⟨ j1, hj1 ⟩
        refine ⟨by scalar_tac, ?_, by scalar_tac⟩
        rw [hj1, htake, hids1, hids]; simp [ho]
      · rename_i ho
        step as ⟨ j1, hj1 ⟩
        refine ⟨by scalar_tac, ?_, by scalar_tac⟩
        rw [hj1, htake, hids]; simp [ho]
    · rename_i hge
      have : j.val = t.items.length := by scalar_tac
      simp [hids, this]
  · exact ⟨hi, hids⟩

theorem visible_ids_correct (t : Todos) (user : U32) :
    visible_ids t user ⦃ r => r.val.map (·.val) = Spec.visible (abs t) user.val ⦄ := by
  unfold visible_ids
  have := visible_ids_loop_spec t user (alloc.vec.Vec.new U32) 0#usize (by simp) (by simp)
  apply WP.spec_mono this
  intro r hr
  rw [hr]
  simp [Spec.visible, Spec.ownedBy, abs, List.filter_map, Function.comp_def, absTodo]

/-! ## toggle: user の id 番の完了を反転する（id が重複しないという不変条件のもとで） -/
theorem toggle_loop_spec (t : Todos) (id : U32) (i : Usize)
    (hi : i.val ≤ t.items.length)
    (hbefore : ∀ j (_ : j < i.val) (hj' : j < t.items.val.length), t.items.val[j].id ≠ id) :
    toggle_loop t id i ⦃ r =>
      r.1 = t.items ∧ r.2.1 = t.next_id ∧ r.2.2.val ≤ t.items.length ∧
      (∀ j (_ : j < r.2.2.val) (hj' : j < t.items.val.length), t.items.val[j].id ≠ id) ∧
      (∀ (h : r.2.2.val < t.items.val.length), t.items.val[r.2.2.val].id = id) ⦄ := by
  unfold toggle_loop
  apply loop.spec_decr_nat
    (measure := fun (j : Usize) => t.items.length - j.val)
    (inv := fun (j : Usize) => j.val ≤ t.items.length ∧
      ∀ k (hk : k < j.val) (hk' : k < t.items.val.length), t.items.val[k].id ≠ id)
  · rintro j ⟨hj, hb⟩
    unfold toggle_loop.body
    dsimp only
    split
    · rename_i hlt
      have hlt : j.val < t.items.val.length := by scalar_tac
      step as ⟨ x, hx ⟩
      split
      · rename_i hne
        step as ⟨ j1, hj1 ⟩
        refine ⟨by scalar_tac, ?_, by scalar_tac⟩
        intro k hk hk'
        by_cases hkj : k = j.val
        · subst hkj; rw [← hx]; simpa using hne
        · exact hb k (by omega) hk'
      · rename_i heq
        simp only [bne_iff_ne, ne_eq, Decidable.not_not] at heq
        rw [WP.spec_ok]
        exact ⟨rfl, rfl, hj, hb, fun _ => by rw [← hx]; exact heq⟩
    · rename_i hge
      have hge : t.items.val.length ≤ j.val := by scalar_tac
      rw [WP.spec_ok]
      exact ⟨rfl, rfl, hj, hb, fun h => by simp only at h; omega⟩
  · exact ⟨hi, hbefore⟩

theorem toggle_loop_spec0 (t : Todos) (id : U32) :
    toggle_loop t id 0#usize ⦃ v n k =>
      v = t.items ∧ n = t.next_id ∧ k.val ≤ t.items.length ∧
      (∀ j (_ : j < k.val) (hj' : j < t.items.val.length), t.items.val[j].id ≠ id) ∧
      (∀ (h : k.val < t.items.val.length), t.items.val[k.val].id = id) ⦄ := by
  have := toggle_loop_spec t id 0#usize (by simp) (by simp)
  apply WP.spec_mono this
  rintro ⟨v, n, k⟩ h
  exact h

-- 前提 hinv: id が重複しないこと（これで仕様の全部反転と Rust の最初の1件が一致する）
theorem toggle_correct (t : Todos) (user id : U32) (hinv : Spec.Inv (abs t)) :
    -- 効いたか b も新しい状態 t' も仕様の toggle と同じ
    toggle t user id ⦃ b t' => b = (Spec.toggle (abs t) user.val id.val).1 ∧
                         abs t' = (Spec.toggle (abs t) user.val id.val).2 ⦄ := by
  have hnd := hinv.1
  simp only [abs, List.map_map] at hnd
  unfold toggle
  step with toggle_loop_spec0 as ⟨ v, n, k, hv, hn, hk, hbefore, hfound ⟩
  subst hv hn
  split
  · rename_i hlt
    have hlt : k.val < t.items.val.length := by scalar_tac
    have hid := hfound hlt
    step as ⟨ x, hx ⟩
    split
    · -- 見つかり、持ち主が本人: 反転する
      rename_i ho
      step as ⟨ x2, back, hx2, hback ⟩
      simp only [hback]
      refine ⟨?_, ?_⟩
      · symm
        simp only [Spec.toggle, abs, List.any_map, List.any_eq_true, Function.comp_def, mine_abs]
        exact ⟨_, List.getElem_mem hlt, by rw [← hx] at hid ⊢; simp [hid, ho]⟩
      · simp only [abs, Spec.toggle, Spec.State.mk.injEq, and_true, List.map_map]
        apply List.ext_getElem
        · simp
        · intro j h1 h2
          simp only [alloc.vec.Vec.set_val_eq, List.getElem_map, List.getElem_set, Function.comp_def,
            mine_abs]
          by_cases hj : k.val = j
          · subst hj
            simp [hx, hx2, absTodo, hid, ← ho]
          · simp only [hj, ite_false]
            have hne : (t.items.val[j]'(by simpa using h2)).id ≠ id := by
              intro h
              have := (List.Nodup.getElem_inj_iff hnd (i := j) (j := k.val)
                (hi := by simpa using h2) (hj := by simpa using hlt)).mp
                (by simp only [Function.comp_def, absTodo, List.getElem_map]; rw [h, hid])
              exact hj this.symm
            simp [hne]
    · -- 見つかったが、持ち主が別の人: 何もしない（仕様の toggle_foreign と同じ）
      rename_i ho
      have hmem : absTodo x ∈ (abs t).items := by
        simp only [abs, List.mem_map]; exact ⟨x, by rw [hx]; exact List.getElem_mem hlt, rfl⟩
      have hfor := Spec.toggle_foreign (abs t) user.val id.val hinv (absTodo x) hmem
        (by rw [hx]; simp only [absTodo]; rw [hid]) ((u32_ne_iff _ _).mp ho)
      simp only [WP.spec_ok, WP.uncurry'_pair, hfor]
      simp
  · rename_i hge
    have hge : t.items.val.length ≤ k.val := by scalar_tac
    have hnone : ∀ x ∈ t.items.val, x.id ≠ id := by
      intro x hx
      obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem hx
      exact hbefore j (by omega) hj
    simp only [WP.spec_ok, WP.uncurry'_pair]
    refine ⟨?_, ?_⟩
    · symm
      simp only [Spec.toggle, abs, List.any_map, Function.comp_def, mine_abs, List.any_eq_false]
      intro x hx; simp [hnone x hx]
    · simp only [abs, Spec.toggle, Spec.State.mk.injEq, and_true, List.map_map]
      apply List.map_congr_left
      intro x hx
      simp [hnone x hx]

/-! ## remove: user の id 番の todo を除く（不変条件は要らない） -/

/-- IntoIter（Vec を前から1つずつ取り出すもの）の残りの中身。 -/
def iv {T : Type} (x : alloc.vec.into_iter.IntoIter T) : List T := alloc.vec.Vec.val x

theorem into_iter_next_spec {T : Type} (it : alloc.vec.into_iter.IntoIter T) :
    alloc.vec.into_iter.IteratorIntoIter.next it ⦃ o it' =>
      match o with
      | none => iv it = []
      | some x => iv it = x :: iv it' ⦄ := by
  unfold alloc.vec.into_iter.IteratorIntoIter.next
  split
  · rename_i h; simp only [WP.spec_ok]; simpa [iv] using h
  · rename_i hd tl h
    simp only [WP.spec_ok]
    show iv it = hd :: iv (alloc.vec.Vec.from tl _)
    simp only [iv, h]; exact congrArg _ (alloc.vec.Vec.from_val _ _).symm

/-- 残す条件: 「user の id 番」ではない。 -/
abbrev keep (user id : U32) (x : Todo) : Bool := !(x.id == id && x.owner == user)

theorem remove_loop_spec (user id : U32) (old : List Todo)
    (iter : alloc.vec.into_iter.IntoIter Todo)
    (kept : alloc.vec.Vec Todo) (pre : List Todo)
    (hold : old.length ≤ Usize.max)
    (hsplit : old = pre ++ iv iter) (hkept : kept.val = pre.filter (keep user id)) :
    remove_loop iter user id kept ⦃ r => r.val = old.filter (keep user id) ⦄ := by
  unfold remove_loop
  apply loop.spec_decr_nat
    (measure := fun (p : alloc.vec.into_iter.IntoIter Todo × alloc.vec.Vec Todo) => (iv p.1).length)
    (inv := fun (p : alloc.vec.into_iter.IntoIter Todo × alloc.vec.Vec Todo) =>
      ∃ pre, old = pre ++ iv p.1 ∧ p.2.val = pre.filter (keep user id))
  · rintro ⟨it, ke⟩ ⟨pr, hs, hk⟩
    unfold remove_loop.body
    step with into_iter_next_spec as ⟨ o, it1, hnext ⟩
    cases o with
    | none =>
      simp only at hnext ⊢
      simp only [WP.spec_ok]
      simp only at hs hk
      rw [hk, hs, hnext]; simp
    | some hd =>
      simp only at hnext hs hk ⊢
      have hlen : ke.val.length < Usize.max := by
        have h1 : ke.val.length ≤ pr.length := by rw [hk]; exact List.length_filter_le _ _
        have h2 : pr.length + 1 ≤ old.length := by rw [hs, hnext]; simp
        omega
      have hsplit' : old = (pr ++ [hd]) ++ iv it1 := by rw [hs, hnext]; simp
      split
      · rename_i hid
        split
        · -- user の id 番: 捨てる
          rename_i ho
          simp only [WP.spec_ok]
          refine ⟨⟨pr ++ [hd], hsplit', ?_⟩, by simp [hnext]⟩
          rw [hk]; simp [List.filter_append, keep, hid, ho]
        · rename_i ho
          step as ⟨ ke1, hke1 ⟩
          refine ⟨⟨pr ++ [hd], hsplit', ?_⟩, by simp [hnext]⟩
          rw [hke1, hk]; simp [List.filter_append, keep, hid, ho]
      · rename_i hid
        step as ⟨ ke1, hke1 ⟩
        refine ⟨⟨pr ++ [hd], hsplit', ?_⟩, by simp [hnext]⟩
        rw [hke1, hk]; simp [List.filter_append, keep, hid]
  · exact ⟨pre, hsplit, hkept⟩

theorem into_iter_spec (v : alloc.vec.Vec Todo) :
    alloc.vec.IntoIteratorVec.into_iter v ⦃ it => iv it = v.val ⦄ := by
  unfold alloc.vec.IntoIteratorVec.into_iter
  exact (WP.spec_ok _).mpr rfl

theorem remove_loop_spec0 (user id : U32) (v : alloc.vec.Vec Todo)
    (it : alloc.vec.into_iter.IntoIter Todo) (h : iv it = v.val) :
    remove_loop it user id (alloc.vec.Vec.new Todo) ⦃ r => r.val = v.val.filter (keep user id) ⦄ :=
  remove_loop_spec user id v.val it (alloc.vec.Vec.new Todo) [] v.property (by simp [h]) (by simp)

theorem remove_correct (t : Todos) (user id : U32) :
    remove t user id ⦃ b t' => b = (Spec.remove (abs t) user.val id.val).1 ∧
                         abs t' = (Spec.remove (abs t) user.val id.val).2 ⦄ := by
  unfold remove
  simp only [core.mem.replace]
  step with into_iter_spec as ⟨ it, hit ⟩
  step with remove_loop_spec0 user id t.items as ⟨ kept, hk ⟩
  have hmap : (t.items.val.filter (keep user id)).map absTodo =
      (t.items.val.map absTodo).filter (fun x => !Spec.mine user.val id.val x) := by
    rw [List.filter_map]
    congr 1
  refine ⟨?_, ?_⟩
  · have hlt : (kept.len < t.items.len) ↔ kept.val.length < t.items.val.length := by
      constructor <;> intro h <;> scalar_tac
    simp only [Spec.remove, abs, List.any_map, Function.comp_def, mine_abs]
    rw [Bool.eq_iff_iff, decide_eq_true_iff, hlt, hk, List.length_filter_lt_length_iff_exists,
      List.any_eq_true]
    simp [keep, u32_eq_iff]
  · simp [abs, Spec.remove, hk, hmap]

/-! ## まとめ1: Rust の操作を何回続けても、不変条件は崩れない
（仕様の上で示した `Spec.inv_*` と、上の「実装 = 仕様」をつなぐ） -/

theorem add_preserves_inv (t : Todos) (user : U32) (title : String) (hinv : Spec.Inv (abs t)) :
    add t user title ⦃ _ t' => Spec.Inv (abs t') ⦄ := by
  apply WP.spec_mono (add_correct t user title hinv)
  rintro ⟨r, t'⟩ ⟨-, h⟩
  show Spec.Inv (abs t'); rw [h]; exact Spec.inv_add _ _ _ hinv

theorem toggle_preserves_inv (t : Todos) (user id : U32) (hinv : Spec.Inv (abs t)) :
    toggle t user id ⦃ _ t' => Spec.Inv (abs t') ⦄ := by
  apply WP.spec_mono (toggle_correct t user id hinv)
  rintro ⟨b, t'⟩ ⟨-, h⟩
  show Spec.Inv (abs t'); rw [h]; exact Spec.inv_toggle _ _ _ hinv

theorem remove_preserves_inv (t : Todos) (user id : U32) (hinv : Spec.Inv (abs t)) :
    remove t user id ⦃ _ t' => Spec.Inv (abs t') ⦄ := by
  apply WP.spec_mono (remove_correct t user id)
  rintro ⟨b, t'⟩ ⟨-, h⟩
  show Spec.Inv (abs t'); rw [h]; exact Spec.inv_remove _ _ _ hinv

/-! ## まとめ2: 認可は Rust の実装でも成り立つ
user が何をしても、ほかの人 other の持ち物は変わらない（仕様の `*_others` を Rust に持ち上げる） -/

/-- user ≠ other なら、Rust の add のあとも other の持ち物は変わらない。 -/
theorem add_others_rust (t : Todos) (user other : U32) (title : String) (hne : user ≠ other)
    (hinv : Spec.Inv (abs t)) :
    add t user title ⦃ _ t' => Spec.ownedBy (abs t') other.val = Spec.ownedBy (abs t) other.val ⦄ := by
  apply WP.spec_mono (add_correct t user title hinv)
  rintro ⟨r, t'⟩ ⟨-, h⟩
  show Spec.ownedBy (abs t') other.val = _
  rw [h]; exact Spec.add_others _ _ _ _ ((u32_ne_iff _ _).mp hne)

/-- user ≠ other なら、Rust の toggle のあとも other の持ち物は変わらない。 -/
theorem toggle_others_rust (t : Todos) (user other id : U32) (hne : user ≠ other)
    (hinv : Spec.Inv (abs t)) :
    toggle t user id ⦃ _ t' => Spec.ownedBy (abs t') other.val = Spec.ownedBy (abs t) other.val ⦄ := by
  apply WP.spec_mono (toggle_correct t user id hinv)
  rintro ⟨b, t'⟩ ⟨-, h⟩
  show Spec.ownedBy (abs t') other.val = _
  -- 仕様で証明済みの Spec.toggle_others をそのまま使う
  rw [h]; exact Spec.toggle_others _ _ _ _ ((u32_ne_iff _ _).mp hne)

/-- user ≠ other なら、Rust の remove のあとも other の持ち物は変わらない。 -/
theorem remove_others_rust (t : Todos) (user other id : U32) (hne : user ≠ other) :
    remove t user id ⦃ _ t' => Spec.ownedBy (abs t') other.val = Spec.ownedBy (abs t) other.val ⦄ := by
  apply WP.spec_mono (remove_correct t user id)
  rintro ⟨b, t'⟩ ⟨-, h⟩
  show Spec.ownedBy (abs t') other.val = _
  rw [h]; exact Spec.remove_others _ _ _ _ ((u32_ne_iff _ _).mp hne)

/-- 見せる id はちょうど「user が持ち主の todo の id」。 -/
theorem visible_ids_only_own (t : Todos) (user : U32) :
    visible_ids t user ⦃ r => ∀ x, x ∈ r.val.map (·.val) ↔
      ∃ s ∈ (abs t).items, s.id = x ∧ s.owner = user.val ⦄ := by
  apply WP.spec_mono (visible_ids_correct t user)
  intro r hr x
  rw [hr]; exact Spec.visible_iff _ _ _

end todo_kernel
