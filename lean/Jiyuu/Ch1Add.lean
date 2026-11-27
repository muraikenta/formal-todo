/-!
# 第1章 足し算を自分で作って、性質を証明する

Lean に最初から入っている `Nat` は使わず、自然数そのものをゼロから定義する。
「0 がある」「n があれば、その次 (n+1) がある」の2つだけで全部の自然数を表す（ペアノの公理）。
-/

namespace Jiyuu

/-- 自然数。`zero` が 0、`succ n` が「n の次の数」。3 は `succ (succ (succ zero))`。 -/
inductive N where
  | zero : N
  | succ : N → N
  deriving Repr

open N

/-- 表示用: N を普通の数に直す。 -/
def N.toNat : N → Nat
  | zero   => 0
  | succ n => n.toNat + 1

/-- 普通の数から N を作る（#eval で試す用）。 -/
def N.ofNat : Nat → N
  | 0     => zero
  | n + 1 => succ (N.ofNat n)

/-- 足し算の定義。教えたのはこの2行だけ。
  - n + 0 = n
  - n + (m の次) = (n + m) の次 -/
def add : N → N → N
  | n, zero   => n
  | n, succ m => succ (add n m)

instance : Add N := ⟨add⟩   -- これで `a + b` と書ける

-- 動かしてみる: 2 + 3 = 5
#eval (add (N.ofNat 2) (N.ofNat 3)).toNat

/-! ## 定理1: n + 0 = n
定義の1行目そのもの。`rfl`（両辺は計算すると同じ）で終わる。 -/
theorem add_zero (n : N) : n + zero = n := rfl

/-! ## 定理2: 0 + n = n
見た目は定理1と同じなのに、定義は「右側」でしか場合分けしていないので計算では出ない。
→ 数学的帰納法: n = 0 のとき成り立つ ＋ n で成り立つなら n の次でも成り立つ。 -/
theorem zero_add (n : N) : zero + n = n := by
  induction n with
  | zero => rfl                      -- 0 + 0 = 0 は計算で出る
  | succ k ih =>                     -- ih : 0 + k = k（帰納法の仮定）
    show succ (zero + k) = succ k    -- 定義で1段ほどく
    rw [ih]                          -- 仮定で書き換えれば両辺が同じ

/-! ## 補題: (a の次) + b = (a + b) の次 -/
theorem succ_add (a b : N) : succ a + b = succ (a + b) := by
  induction b with
  | zero => rfl
  | succ k ih =>
    show succ (succ a + k) = succ (succ (a + k))
    rw [ih]

/-! ## 定理3: 交換法則 a + b = b + a -/
theorem add_comm (a b : N) : a + b = b + a := by
  induction b with
  | zero => rw [add_zero, zero_add]
  | succ k ih =>
    show succ (a + k) = succ k + a
    rw [succ_add, ih]

/-! ## 定理4: 結合法則 (a + b) + c = a + (b + c) -/
theorem add_assoc (a b c : N) : (a + b) + c = a + (b + c) := by
  induction c with
  | zero => rfl
  | succ k ih =>
    show succ ((a + b) + k) = succ (a + (b + k))
    rw [ih]

end Jiyuu
