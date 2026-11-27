import Jiyuu
import Spec
/-!
# 実装が仕様どおりであることの証明

- 仕様: `Spec.lean`（人が先に書く。実装を見ない）
- 実装: `../rust/src/lib.rs` を Charon → Aeneas で自動翻訳した `Jiyuu.lean`（手で書いていない）
- ここ: 「実装 = 仕様」を証明する。仕様を変えずに実装だけ壊すと、ここが通らなくなる

記法: `f x ⦃ y => P y ⦄` は「f x は失敗せずに値 y を返し、y は P を満たす」。
Aeneas は u32 の足し算を「成功したら値（ok）、あふれたら失敗（fail）」として翻訳するので、
証明は「答えが u32 に収まるなら仕様どおり」の形になる。
-/
open Aeneas Aeneas.Std Result
namespace jiyuu

-- 実行してみる
#eval add 2#u32 3#u32              -- ok 5
#eval add 4294967295#u32 1#u32     -- fail integerOverflow（あふれた）
#eval sum_to 10#u32                -- ok 55 (= 0x37)

/-- Aeneas の U32.max と、仕様に書いた 2^32 − 1 が同じであること。 -/
theorem u32_max_eq : U32.max = 2 ^ 32 - 1 := by
  simp [U32.max_def, U32.numBits_def]

/-! ## 定理1: add は仕様どおり（答えが u32 に収まるとき） -/
theorem add_correct (a b : U32) (h : Spec.FitsU32 (Spec.add a.val b.val)) :
    add a b ⦃ c => c.val = Spec.add a.val b.val ⦄ := by
  simp only [Spec.FitsU32, Spec.add, ← u32_max_eq] at h ⊢
  unfold add
  step as ⟨ c ⟩
  grind

/-! ## 定理2: add は、答えが u32 に収まらないとき必ず失敗する（間違った値を黙って返さない） -/
theorem add_fails (a b : U32) (h : ¬ Spec.FitsU32 (Spec.add a.val b.val)) :
    add a b = fail .integerOverflow := by
  simp only [Spec.FitsU32, Spec.add, ← u32_max_eq, Nat.not_le] at h
  show UScalar.add a b = fail .integerOverflow
  simp only [UScalar.add, UScalar.tryMk, UScalar.tryMkOpt, UScalar.check_bounds]
  simp only [U32.max] at h
  split
  · rename_i hb
    simp only [decide_eq_true_eq, U32.numBits_def, UScalarTy.U32_numBits_eq] at h hb
    omega
  · rfl

/-! ## 定理3（性質）: 交換法則。失敗するかどうかも含めて、add a b と add b a は完全に同じ -/
theorem add_comm (a b : U32) : add a b = add b a := by
  show UScalar.add a b = UScalar.add b a
  simp only [UScalar.add, Nat.add_comm]

/-! ## 定理4: double_plus_one は仕様どおり。add の証明を部品にして進む -/
theorem double_plus_one_correct (x : U32) (h : Spec.FitsU32 (Spec.doublePlusOne x.val)) :
    double_plus_one x ⦃ y => y.val = Spec.doublePlusOne x.val ⦄ := by
  simp only [Spec.FitsU32, Spec.doublePlusOne, ← u32_max_eq] at h ⊢
  unfold double_plus_one add
  step as ⟨ i ⟩
  step as ⟨ y ⟩
  grind

/-! ## 定理5（主定理）: while ループの sum_to は、仕様の 0 + 1 + … + n を返す
実装はループ、仕様は和の記号。書き方がまったく違う2つが、すべての n で一致することを示す。
ループの証明では「ループ不変条件」を人が見つけて与える:
  - i ≤ n
  - 2 × total = i × (i + 1)   （ここまでの和）
各周でこれが保たれ、n − i が減り続ける（＝必ず止まる）ことを示す。
最後に仕様側の性質（Spec.two_mul_sum: 2 × 和 = n(n+1)）でつなぐ。 -/
theorem sum_to_correct (n : U32) (h : Spec.FitsU32 (Spec.sum n.val)) :
    sum_to n ⦃ r => r.val = Spec.sum n.val ⦄ := by
  have hG := Spec.two_mul_sum n.val
  simp only [Spec.FitsU32, ← u32_max_eq] at h
  unfold sum_to sum_to_loop
  apply loop.spec_decr_nat
    (measure := fun (p : U32 × U32) => n.val - p.2.val)
    (inv := fun (p : U32 × U32) => p.2.val ≤ n.val ∧ 2 * p.1.val = p.2.val * (p.2.val + 1))
  · rintro ⟨total, i⟩ ⟨hi, hinv⟩
    simp only at hi hinv ⊢
    unfold sum_to_loop.body
    split
    · step as ⟨ i1, hi1 ⟩
      have : total.val + i1.val ≤ U32.max := by
        have : 2 * (total.val + i1.val) = i1.val * (i1.val + 1) := by grind
        have : i1.val * (i1.val + 1) ≤ n.val * (n.val + 1) := Nat.mul_le_mul (by grind) (by grind)
        omega
      step as ⟨ total1, ht1 ⟩
      grind
    · simp
      have : i.val = n.val := by scalar_tac
      rw [this] at hinv
      omega
  · simp

end jiyuu
