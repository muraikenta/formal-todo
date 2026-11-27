module
public import Mathlib.Data.List.Sort
public import Mathlib.Data.List.Perm.Basic
@[expose] public section
/-!
# ソートの仕様（実装より先に書く・性質で書く）

「どう並べるか」（アルゴリズム）は書かない。「並べ終わった結果が満たすこと」だけを書く。

1. 小さい順に並んでいる（`Sorted`）
2. 入力の並べ替えである＝要素を足しても消してもいない（`List.Perm`）

数は数学の自然数で書く（Rust の u32 は証明の側で自然数に読み替える）。
人がレビューするのは、このファイルと `Proofs.lean` 末尾の読み替え `nat` と主定理の文（引数の順番を逆にすると別の主張になる）。
-/

namespace Spec

/-- 小さい順に並んでいる: どの2つを取っても、前のほうが後ろ以下。 -/
def Sorted (l : List Nat) : Prop := l.Pairwise (· ≤ ·)

/-- `output` は `input` をソートしたものである。 -/
def IsSortOf (input output : List Nat) : Prop :=
  Sorted output ∧ output.Perm input

instance (l : List Nat) : Decidable (Sorted l) := by unfold Sorted; infer_instance
instance (i o : List Nat) : Decidable (IsSortOf i o) := by unfold IsSortOf; infer_instance

/-! ## 仕様そのものの確かめ（小さい例） -/
section examples
example : IsSortOf [3, 1, 2] [1, 2, 3] := by decide
example : IsSortOf [2, 1, 2] [1, 2, 2] := by decide            -- 同じ値があってもよい
example : IsSortOf [] [] := by decide
example : ¬ IsSortOf [3, 1, 2] [3, 1, 2] := by decide          -- 並んでいない
example : ¬ IsSortOf [3, 1, 2] [1, 2] := by decide             -- 1つ消えている
example : ¬ IsSortOf [2, 1] [1, 1] := by decide                -- 1つすり替わっている
/-- 「並んでいる」だけの仕様は弱い: 全部 0 にする実装でも満たしてしまう。だから並べ替えであることも書く。 -/
example : Sorted [0, 0, 0] ∧ ¬ IsSortOf [3, 1, 2] [0, 0, 0] := by decide
end examples

/-! ## 仕様が十分に強いことの確かめ

2つの性質だけで、答えはただ1つに決まる。
つまり、この仕様を満たす実装はどれも同じ結果を返す（「おかしな実装」が入り込む余地が無い）。 -/
theorem sortOf_unique {input a b : List Nat}
    (ha : IsSortOf input a) (hb : IsSortOf input b) : a = b :=
  List.Perm.eq_of_pairwise (fun _ _ _ _ h1 h2 => Nat.le_antisymm h1 h2) ha.1 hb.1 (ha.2.trans hb.2.symm)

/-- その「ただ1つの答え」は、標準ライブラリの mergeSort の結果そのもの（答えがあることと、ほかに無いこと）。 -/
theorem isSortOf_iff_mergeSort (l o : List Nat) :
    IsSortOf l o ↔ o = l.mergeSort (fun a b => decide (a ≤ b)) := by
  have hs : IsSortOf l (l.mergeSort (fun a b => decide (a ≤ b))) := by
    refine ⟨?_, List.mergeSort_perm _ _⟩
    have := List.pairwise_mergeSort (le := fun a b => decide (a ≤ b))
      (by intro a b c h1 h2; simp at *; omega) (by intro a b; simp; omega) l
    simpa [Sorted] using this
  exact ⟨fun h => sortOf_unique h hs, fun h => h ▸ hs⟩

end Spec
