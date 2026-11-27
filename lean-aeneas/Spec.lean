module
public import Mathlib.Algebra.BigOperators.Intervals
@[expose] public section
/-!
# 仕様（実装より先に書く）

Rust の実装を一切見ずに、「何を返すべきか」だけを数学の言葉で書く。
ここに出てくる `+` や `∑` は数学の自然数の演算で、上限もあふれもない。
人がレビューするのはこのファイルだけでよい（実装が仕様どおりかは機械が証明する）。
-/

open Finset

namespace Spec

/-- u32 に収まる（0 〜 2^32 − 1）。 -/
def FitsU32 (x : Nat) : Prop := x ≤ 2 ^ 32 - 1

/-- 仕様1: add は入力を足し合わせた結果を返す。 -/
def add (a b : Nat) : Nat := a + b

/-- 仕様2: double_plus_one は 2x + 1 を返す。 -/
def doublePlusOne (x : Nat) : Nat := 2 * x + 1

/-- 仕様3: sum_to は 0 + 1 + 2 + … + n を返す（和の記号で書く。ループのことは書かない）。 -/
def sum (n : Nat) : Nat := ∑ i ∈ range (n + 1), i

/-! 共通の要求: 答えが u32 に収まらないときは、間違った値を返さずに失敗する。
（各関数の証明で「収まるなら仕様どおり」「収まらないなら失敗」の2本に分けて示す） -/

/-! ## 仕様そのものの確かめ（仕様の書き間違いに気づくため）
小さい値で、思ったとおりの答えになるかを見ておく。 -/
example : add 2 3 = 5 := rfl
example : doublePlusOne 10 = 21 := rfl
example : sum 10 = 55 := by decide

/-- 仕様の性質: 和はガウスの公式 n(n+1)/2 と一致する（仕様どうしの関係。実装とは無関係）。 -/
theorem two_mul_sum (n : Nat) : 2 * sum n = n * (n + 1) := by
  have h := Finset.sum_range_id_mul_two (n + 1)
  simp only [Nat.add_sub_cancel] at h
  simp only [sum]
  rw [Nat.mul_comm 2, h, Nat.mul_comm]

end Spec
