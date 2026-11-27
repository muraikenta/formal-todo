import Jiyuu.Ch1Add
/-!
# 第2章 掛け算 — 足し算の定理を部品にして証明を積み上げる

掛け算は「足し算の繰り返し」として定義する。証明では第1章の定理をそのまま使う。
-/

namespace Jiyuu
open N

/-- 掛け算の定義
  - n × 0 = 0
  - n × (m の次) = n × m + n -/
def mul : N → N → N
  | _, zero   => zero
  | n, succ m => mul n m + n

instance : Mul N := ⟨mul⟩   -- これで `a * b` と書ける

-- 3 × 4 = 12
#eval (mul (N.ofNat 3) (N.ofNat 4)).toNat

theorem mul_zero (n : N) : n * zero = zero := rfl

theorem zero_mul (n : N) : zero * n = zero := by
  induction n with
  | zero => rfl
  | succ k ih =>
    show zero * k + zero = zero
    rw [ih]; rfl

/-- 1 = succ zero -/
abbrev one : N := succ zero

theorem mul_one (n : N) : n * one = n := by
  show zero + n = n
  exact zero_add n

theorem one_mul (n : N) : one * n = n := by
  induction n with
  | zero => rfl
  | succ k ih =>
    show one * k + one = succ k
    rw [ih]; rfl

/-! ## 分配法則 a × (b + c) = a × b + a × c
足し算の結合法則・交換法則（第1章）を道具として使う。 -/
theorem mul_add (a b c : N) : a * (b + c) = a * b + a * c := by
  induction c with
  | zero => rfl
  | succ k ih =>
    show a * (b + k) + a = a * b + (a * k + a)
    rw [ih, add_assoc]

/-- (a の次) × b = a × b + b -/
theorem succ_mul (a b : N) : succ a * b = a * b + b := by
  induction b with
  | zero => rfl
  | succ k ih =>
    show succ a * k + succ a = succ (a * k + a + k)
    rw [ih]
    show succ (a * k + k + a) = succ (a * k + a + k)
    rw [add_assoc, add_comm k a, ← add_assoc]

/-! ## 掛け算の交換法則 a × b = b × a -/
theorem mul_comm (a b : N) : a * b = b * a := by
  induction b with
  | zero => rw [mul_zero, zero_mul]
  | succ k ih =>
    show a * k + a = succ k * a
    rw [succ_mul, ih]

/-! ## 掛け算の結合法則 (a × b) × c = a × (b × c) -/
theorem mul_assoc (a b c : N) : (a * b) * c = a * (b * c) := by
  induction c with
  | zero => rfl
  | succ k ih =>
    show (a * b) * k + a * b = a * (b * k + b)
    rw [ih, mul_add]

end Jiyuu
