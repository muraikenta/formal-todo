import SortKernel
import Spec
/-!
# Rust の挿入ソートが仕様どおりであることの証明

- 仕様: `Spec.lean`（人が先に書く。実装を見ない。性質で書いた）
- 実装: `../kernel/src/lib.rs` を Charon → Aeneas で自動翻訳した `SortKernel.lean`（手で書いていない）
- ここ: どんな入力でも「panic せずに終わり、結果は入力をソートしたもの」を示す

記法: `f x ⦃ y => P y ⦄` は「f x は止まり（無限ループせず）、失敗（panic）せずに値 y を返し、y は P を満たす」。
-/
open Aeneas Aeneas.Std Result
namespace sort_kernel

/-- 証明の途中で使う「並んでいる」（u32 のまま、値で比べる）。最後に仕様の `Spec.Sorted` に読み替える。 -/
def SortedU (l : List U32) : Prop := l.Pairwise (fun a b => a.val ≤ b.val)

/-! ## リストだけの補題 -/

/-- 並んでいる列 `pre ++ post` の間に、`pre` のどれ以上・`post` のどれ以下の `x` を挟んでも並んでいる。 -/
theorem sorted_insert_mid {pre post : List U32} {x : U32}
    (h : SortedU (pre ++ post)) (hpre : ∀ p ∈ pre, p.val ≤ x.val)
    (hpost : ∀ y ∈ post, x.val ≤ y.val) : SortedU (pre ++ x :: post) := by
  unfold SortedU at *
  rw [List.pairwise_append] at h ⊢
  obtain ⟨h1, h2, h3⟩ := h
  refine ⟨h1, List.pairwise_cons.2 ⟨hpost, h2⟩, ?_⟩
  intro a ha b hb
  rcases List.mem_cons.1 hb with rfl | hb
  · exact hpre a ha
  · exact h3 a ha b hb

/-- 長さ 1 以下の先頭はいつも並んでいる。 -/
theorem sorted_take_one (l : List U32) : SortedU (l.take 1) := by
  cases l <;> simp [SortedU]

/-- 列の真ん中の値を読む。 -/
theorem getElem_mid {l pre tail : List U32} {a : U32} (h : l = pre ++ a :: tail)
    {k : Nat} (hk : k = pre.length) (hb : k < l.length) : l[k] = a := by
  subst h hk; simp


/-- 隣どうしの入れ替え（Rust の `v.swap(j-1, j)`）は、列の上では a, x を x, a にするだけ。 -/
theorem swap_adj (s : Slice U32) (p q : Usize) (pre tail : List U32) (a x : U32)
    (h : s.val = pre ++ a :: x :: tail) (hp : p.val = pre.length) (hq : q.val = pre.length + 1) :
    core.slice.Slice.swap s p q ⦃ s' => s'.val = pre ++ x :: a :: tail ⦄ := by
  have hlen : s.val.length = pre.length + 2 + tail.length := by rw [h]; simp; omega
  unfold core.slice.Slice.swap
  step as ⟨ av, hav ⟩
  step as ⟨ bv, hbv ⟩
  step as ⟨ s1, hs1 ⟩
  step as ⟨ s2, hs2 ⟩
  rw [hs2, hs1]
  simp only [Slice.set_val_eq]
  have e1 : av = a := by rw [hav]; exact getElem_mid (tail := x :: tail) h hp _
  have e2 : bv = x := by
    rw [hbv]; exact getElem_mid (pre := pre ++ [a]) (tail := tail) (by rw [h]; simp) (by simp [hq]) _
  rw [e1, e2, h, hp, hq]
  simp [List.set_append_right]

/-! ## insert: v[i] を左の並んだ部分に沈める -/

/-- 内側のループの不変条件。`x` は沈めている値、`rest` は触らない右側、`s0` は入る前の先頭 i+1 個。
  いまの列は `pre ++ x :: post ++ rest` の形で、`x` を抜くと並んでいて、`x` は `post` のどれ以下。 -/
@[reducible] def InsInv (x : U32) (rest s0 : List U32) (i : Nat) (w : Slice U32) (j : Usize) : Prop :=
  ∃ pre post, w.val = pre ++ x :: post ++ rest ∧ pre.length = j.val ∧
    pre.length + post.length = i ∧ SortedU (pre ++ post) ∧
    (∀ y ∈ post, x.val ≤ y.val) ∧ (pre ++ x :: post).Perm s0

theorem insert_loop_spec (x : U32) (rest s0 : List U32) (i : Nat) (w : Slice U32) (j : Usize)
    (hinv : InsInv x rest s0 i w j) :
    insert_loop w j ⦃ w' =>
      SortedU (w'.val.take (i + 1)) ∧ w'.val.drop (i + 1) = rest ∧
      (w'.val.take (i + 1)).Perm s0 ∧ w'.val.length = w.val.length ⦄ := by
  have hlen0 : ∀ w j, InsInv x rest s0 i w j → w.val.length = i + 1 + rest.length := by
    rintro w j ⟨pre, post, hw, -, hpp, -⟩
    rw [hw]; simp; omega
  have hL := hlen0 w j hinv
  unfold insert_loop
  apply loop.spec_decr_nat
    (measure := fun (p : Slice U32 × Usize) => p.2.val)
    (inv := fun (p : Slice U32 × Usize) => InsInv x rest s0 i p.1 p.2 ∧
      p.1.val.length = w.val.length)
  · rintro ⟨w, j⟩ ⟨hinv, hlw⟩
    have hL' := hlen0 w j hinv
    obtain ⟨pre, post, hw, hpl, hpp, hs, hpost, hperm⟩ := hinv
    simp only at *
    -- 抜けるときの共通の後始末: x の左がすべて x 以下なら、先頭 i+1 個は並んでいる
    have finish : (∀ p ∈ pre, p.val ≤ x.val) →
        SortedU (w.val.take (i + 1)) ∧ w.val.drop (i + 1) = rest ∧
        (w.val.take (i + 1)).Perm s0 ∧ w.val.length = (w.val.length) := by
      intro hpre
      have hlen : (pre ++ x :: post).length = i + 1 := by simp; omega
      have ht : w.val.take (i + 1) = pre ++ x :: post := by
        rw [hw]; exact List.take_left' hlen
      have hd : w.val.drop (i + 1) = rest := by
        rw [hw]; exact List.drop_left' hlen
      rw [ht, hd]
      exact ⟨sorted_insert_mid hs hpre hpost, rfl, hperm, rfl⟩
    unfold insert_loop.body
    split
    · rename_i hj
      -- j > 0 なので pre は空でない: pre = pre' ++ [a]
      obtain ⟨pre', a, rfl⟩ : ∃ pre' a, pre = pre' ++ [a] := by
        rcases List.eq_nil_or_concat pre with h | h
        · subst h; simp at hpl; scalar_tac
        · simpa using h
      have hw' : w.val = pre' ++ a :: x :: (post ++ rest) := by rw [hw]; simp
      simp only [List.length_append, List.length_singleton] at hpl hpp
      step as ⟨ k, hk ⟩
      have hkv : k.val = pre'.length := by scalar_tac
      step as ⟨ a', ha' ⟩
      step as ⟨ x', hx' ⟩
      have ha'eq : a = a' := by rw [ha']; exact (getElem_mid (tail := x :: (post ++ rest)) hw' hkv _).symm
      have hx'eq : x = x' := by
        rw [hx']
        exact (getElem_mid (pre := pre' ++ [a]) (tail := post ++ rest) (by rw [hw']; simp)
          (by simp; omega) _).symm
      subst ha'eq hx'eq
      split
      · rename_i hgt
        -- a > x: 入れ替えて1つ左へ
        step with swap_adj w k j pre' (post ++ rest) a x hw' hkv (by omega) as ⟨ w2, hw2 ⟩
        have hw2v : w2.val = pre' ++ x :: (a :: post) ++ rest := by rw [hw2]; simp
        refine ⟨⟨pre', a :: post, hw2v, hkv.symm, by simp; omega, ?_, ?_, ?_⟩, ?_, by scalar_tac⟩
        · simpa [List.append_assoc] using hs
        · intro y hy
          rcases List.mem_cons.1 hy with rfl | hy
          · scalar_tac
          · exact hpost y hy
        · refine List.Perm.trans ?_ hperm
          simp only [List.append_assoc, List.cons_append]
          exact List.Perm.append_left pre' (List.Perm.swap _ _ _)
        · rw [hlw.symm, hw2v, hw']; simp
      · rename_i hle
        -- a ≤ x: ここで止まる
        have := finish (by
          intro p hp
          have hle' : a.val ≤ x.val := by scalar_tac
          rcases List.mem_append.1 hp with hp | hp
          · have : p.val ≤ a.val := by
              have := hs
              unfold SortedU at this
              rw [List.append_assoc, List.pairwise_append] at this
              exact this.2.2 p hp a (by simp)
            omega
          · simp at hp; subst hp; exact hle')
        simpa [hlw] using this
    · rename_i hj
      -- j = 0: pre は空
      have : pre = [] := by apply List.eq_nil_of_length_eq_zero; scalar_tac
      subst this
      have := finish (by simp)
      simpa [hlw] using this
  · exact ⟨hinv, rfl⟩

/-- insert の仕様: 先頭 i 個が並んでいれば、先頭 i+1 個が並び、右側は触らず、先頭 i+1 個は並べ替えになる。 -/
theorem insert_spec (v : Slice U32) (i : Usize) (hi : i.val < v.val.length)
    (hs : SortedU (v.val.take i.val)) :
    insert v i ⦃ v' =>
      SortedU (v'.val.take (i.val + 1)) ∧ v'.val.drop (i.val + 1) = v.val.drop (i.val + 1) ∧
      (v'.val.take (i.val + 1)).Perm (v.val.take (i.val + 1)) ∧ v'.val.length = v.val.length ⦄ := by
  unfold insert
  apply insert_loop_spec v.val[i.val] (v.val.drop (i.val + 1)) (v.val.take (i.val + 1)) i.val v i
  refine ⟨v.val.take i.val, [], ?_, by simp; omega, by simp; omega, by simpa using hs, by simp, ?_⟩
  · conv_lhs => rw [← List.take_append_drop i.val v.val]
    rw [List.drop_eq_getElem_cons hi]
    simp
  · rw [List.take_add_one, List.getElem?_eq_getElem hi]
    simp

/-! ## insertion_sort: 左から順に insert する -/

theorem insertion_sort_loop_spec (v0 : List U32) (w : Slice U32) (n i : Usize)
    (hn : n.val = w.val.length) (hlen : w.val.length = v0.length) (hperm : w.val.Perm v0)
    (hs : SortedU (w.val.take i.val)) (hi1 : 1 ≤ i.val) (hin : n.val = 0 ∨ i.val ≤ n.val) :
    insertion_sort_loop w n i ⦃ w' => SortedU w'.val ∧ w'.val.Perm v0 ⦄ := by
  unfold insertion_sort_loop
  apply loop.spec_decr_nat
    (measure := fun (p : Slice U32 × Usize) => n.val + 1 - p.2.val)
    (inv := fun (p : Slice U32 × Usize) => p.1.val.length = n.val ∧ p.1.val.Perm v0 ∧
      SortedU (p.1.val.take p.2.val) ∧ 1 ≤ p.2.val ∧ (n.val = 0 ∨ p.2.val ≤ n.val))
  · rintro ⟨w, i⟩ ⟨hl, hp, hs, hi1, hin⟩
    simp only at *
    unfold insertion_sort_loop.body
    split
    · rename_i hlt
      step with insert_spec as ⟨ w', hs', hd', hp', hl' ⟩
      step as ⟨ i', hi' ⟩
      refine ⟨by omega, ?_, by rw [hi']; exact hs', by omega, by right; scalar_tac, by scalar_tac⟩
      rw [← List.take_append_drop (i.val + 1) w'.val, hd']
      refine List.Perm.trans ?_ hp
      conv_rhs => rw [← List.take_append_drop (i.val + 1) w.val]
      exact List.Perm.append_right _ hp'
    · rename_i hge
      simp only [WP.spec_ok]
      refine ⟨?_, hp⟩
      rcases hin with h0 | hle
      · have : w.val = [] := List.eq_nil_of_length_eq_zero (by omega)
        rw [this]; simp [SortedU]
      · have : i.val = n.val := by scalar_tac
        rw [this, ← hl, List.take_length] at hs
        exact hs
  · exact ⟨hn.symm, hperm, hs, hi1, hin⟩

/-! ## 主定理: Rust の挿入ソートは、どんな入力でも panic せず、結果は入力をソートしたもの -/

/-- Rust の u32 の列を、仕様の自然数の列に読み替える。 -/
def nat (v : Slice U32) : List Nat := v.val.map (·.val)

theorem insertion_sort_correct (v : Slice U32) :
    insertion_sort v ⦃ v' => Spec.IsSortOf (nat v) (nat v') ⦄ := by
  unfold insertion_sort
  have := insertion_sort_loop_spec v.val v (Slice.len v) 1#usize (by simp) rfl (List.Perm.refl _)
    (sorted_take_one _) (by simp) (by
      by_cases h : v.val.length = 0
      · left; simp [h]
      · right; simp; omega)
  apply WP.spec_mono this
  rintro v' ⟨hs, hp⟩
  refine ⟨?_, hp.map _⟩
  unfold Spec.Sorted nat
  rw [List.pairwise_map]
  exact hs

/-- 言い換え: Rust の結果を読み替えると、入力を標準の mergeSort で並べたものと等しい。 -/
theorem insertion_sort_eq_mergeSort (v : Slice U32) :
    insertion_sort v ⦃ v' => nat v' = (nat v).mergeSort (fun a b => decide (a ≤ b)) ⦄ :=
  WP.spec_mono (insertion_sort_correct v) (fun _ h => (Spec.isSortOf_iff_mergeSort _ _).1 h)

/-- 読み替え `nat` は情報を落とさない: 仕様を満たす u32 の列はただ1つ。 -/
theorem out_unique (v a b : Slice U32)
    (ha : Spec.IsSortOf (nat v) (nat a)) (hb : Spec.IsSortOf (nat v) (nat b)) : a = b := by
  have h := Spec.sortOf_unique ha hb
  simp only [nat] at h
  have hinj : Function.Injective (fun x : U32 => x.val) := fun x y hxy => UScalar.eq_of_val_eq hxy
  exact Slice.ext a b ((List.map_injective_iff.2 hinj) h)

end sort_kernel
