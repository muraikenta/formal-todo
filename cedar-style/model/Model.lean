/-!
# 実行できる仕様（モデル）— Cedar 方式

Cedar は「Lean で書いた読みやすいモデル」で性質を証明し、Rust の本番実装とは
差分テスト（同じ入力を両方に流して結果を比べる）でつなぐ。ここではその形を真似る。

モデルは速さより読みやすさを優先する。u32 に収まらない答えは `none`（失敗）。
-/

namespace Model

def u32Max : Nat := 2 ^ 32 - 1

/-- 答えが u32 に収まれば `some`、収まらなければ `none`。 -/
def ofNat? (x : Nat) : Option Nat := if x ≤ u32Max then some x else none

/-- add: 入力を足し合わせる。 -/
def add (a b : Nat) : Option Nat := ofNat? (a + b)

/-- double_plus_one: 2x + 1。 -/
def doublePlusOne (x : Nat) : Option Nat := ofNat? (2 * x + 1)

/-- 0 + 1 + … + n をそのまま足す（ループの書き方には合わせない）。 -/
def sumUpTo (n : Nat) : Nat := ((List.range (n + 1)).sum)

/-- sum_to: 0 + 1 + … + n。 -/
def sumTo (n : Nat) : Option Nat := ofNat? (sumUpTo n)

/-! ## モデルについての証明（ここは「すべての入力」で成り立つ） -/

/-- 交換法則: 失敗するかどうかも含めて同じ。 -/
theorem add_comm (a b : Nat) : add a b = add b a := by
  simp [add, Nat.add_comm]

/-- 足し算は、収まる限り a + b を返す。 -/
theorem add_ok (a b : Nat) (h : a + b ≤ u32Max) : add a b = some (a + b) := by
  simp [add, ofNat?, h]

/-- 和はガウスの公式どおり。 -/
theorem two_mul_sumUpTo (n : Nat) : 2 * sumUpTo n = n * (n + 1) := by
  induction n with
  | zero => rfl
  | succ k ih =>
    simp only [sumUpTo, List.range_succ, List.sum_append, List.sum_cons, List.sum_nil] at ih ⊢
    rw [Nat.mul_add, ih]
    simp only [Nat.add_zero, Nat.mul_add, Nat.add_mul, Nat.mul_one, Nat.one_mul]
    omega

/-! ## 差分テスト用の速い版
`sumUpTo` は読みやすさ優先で、n 個のリストを作る（n が大きいと遅い）。
差分テストではガウスの公式で計算する版を使い、2つが等しいことをここで証明しておく。 -/
def sumToFast (n : Nat) : Option Nat := ofNat? (n * (n + 1) / 2)

theorem sumToFast_eq (n : Nat) : sumToFast n = sumTo n := by
  have h := two_mul_sumUpTo n
  have : n * (n + 1) / 2 = sumUpTo n := by omega
  simp [sumToFast, sumTo, this]

-- 小さい値で確かめ
example : sumTo 10 = some 55 := by decide
example : add (2 ^ 32 - 1) 1 = none := by decide

end Model
