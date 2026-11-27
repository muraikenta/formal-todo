/-!
# 第3章 プログラムの正しさを証明する — リストを2回ひっくり返すと元に戻る

数の次は「プログラム」。リストの反転関数を書き、
「どんなリストでも、2回反転すると元に戻る」をテストではなく証明で保証する。
テストは試した入力でしか分からないが、証明は無限にあるすべての入力について言える。
-/

namespace Jiyuu

/-- リスト: 空 `nil` か、「先頭の要素 + 残りのリスト」`cons`。 -/
inductive L (α : Type) where
  | nil  : L α
  | cons : α → L α → L α
  deriving Repr

open L

/-- 連結 xs ++ ys -/
def append {α : Type} : L α → L α → L α
  | nil,       ys => ys
  | cons x xs, ys => cons x (append xs ys)

/-- 反転（素直な書き方: 残りを反転して、先頭を最後にくっつける） -/
def reverse {α : Type} : L α → L α
  | nil       => nil
  | cons x xs => append (reverse xs) (cons x nil)

-- [1,2,3] を反転すると [3,2,1]
#eval reverse (cons 1 (cons 2 (cons 3 nil)))

theorem append_nil {α : Type} (xs : L α) : append xs nil = xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    show cons x (append xs nil) = cons x xs
    rw [ih]

theorem append_assoc {α : Type} (xs ys zs : L α) :
    append (append xs ys) zs = append xs (append ys zs) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    show cons x (append (append xs ys) zs) = cons x (append xs (append ys zs))
    rw [ih]

/-- 連結してから反転 = それぞれ反転して逆順に連結 -/
theorem reverse_append {α : Type} (xs ys : L α) :
    reverse (append xs ys) = append (reverse ys) (reverse xs) := by
  induction xs with
  | nil =>
    show reverse ys = append (reverse ys) nil
    rw [append_nil]
  | cons x xs ih =>
    show append (reverse (append xs ys)) (cons x nil)
       = append (reverse ys) (append (reverse xs) (cons x nil))
    rw [ih, append_assoc]

/-! ## 主定理: 2回反転すると元に戻る -/
theorem reverse_reverse {α : Type} (xs : L α) : reverse (reverse xs) = xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    show reverse (append (reverse xs) (cons x nil)) = cons x xs
    rw [reverse_append, ih]
    rfl

end Jiyuu
