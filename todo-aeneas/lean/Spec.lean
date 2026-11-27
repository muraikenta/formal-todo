module
public import Mathlib.Data.List.Nodup
@[expose] public section
/-!
# todo アプリの仕様（実装より先に書く）

Rust の実装（`../kernel/src/lib.rs`）は見ずに、「各操作のあと状態がどうなるべきか」をリストの言葉で書く。
id とユーザーは数学の自然数で、id の上限は `MaxId`（= u32 の最大値）。人がレビューするのはこのファイルだけでよい。

認可: どの操作も「誰が操作したか（u）」を受け取る。todo には持ち主（owner）があり、
自分が持ち主の todo にしか効かない・見えない。主役の性質は後半の「認可」の節。
-/

namespace Spec

structure Todo where
  id : Nat
  owner : Nat
  title : String
  done : Bool
deriving DecidableEq, Repr

structure State where
  items : List Todo
  nextId : Nat
deriving DecidableEq, Repr

/-- id の上限（u32 の最大値）。ここに達したら、もう足せない。 -/
def MaxId : Nat := 2 ^ 32 - 1

/-- 空のリスト。 -/
def empty : State := ⟨[], 0⟩

/-- t は「u が持ち主の、id 番の todo」か。切り替え・削除が効く相手。 -/
def mine (u id : Nat) (t : Todo) : Bool := t.id == id && t.owner == u

/-- 足す: u が持ち主の未完了の todo を末尾に足し、振った id を返す。id を使い切っていたら何も変えずに none。 -/
def add (s : State) (u : Nat) (title : String) : Option Nat × State :=
  if s.nextId = MaxId then (none, s)
  else (some s.nextId, ⟨s.items ++ [⟨s.nextId, u, title, false⟩], s.nextId + 1⟩)

/-- 完了の切り替え: u が持ち主の id 番の todo の done を反転する。効いたか（そういう todo があったか）を返す。 -/
def toggle (s : State) (u id : Nat) : Bool × State :=
  (s.items.any (mine u id),
   { s with items := s.items.map fun t => if mine u id t then { t with done := !t.done } else t })

/-- 消す: u が持ち主の id 番の todo を除く。効いたかを返す。 -/
def remove (s : State) (u id : Nat) : Bool × State :=
  (s.items.any (mine u id), { s with items := s.items.filter (fun t => !mine u id t) })

/-- u の未完了の件数。 -/
def openCount (s : State) (u : Nat) : Nat := (s.items.filter (fun t => !t.done && t.owner == u)).length

/-- u の持ち物（u から見た世界）。 -/
def ownedBy (s : State) (u : Nat) : List Todo := s.items.filter (·.owner == u)

/-- u に見せてよい id の一覧（自分が持ち主のものだけ、保存順）。 -/
def visible (s : State) (u : Nat) : List Nat := (ownedBy s u).map (·.id)

/-- 状態がいつも満たすべきこと（不変条件）:
  ① id が重複しない ② どの id も nextId より小さい ③ nextId は上限を超えない -/
def Inv (s : State) : Prop :=
  (s.items.map (·.id)).Nodup ∧ (∀ t ∈ s.items, t.id < s.nextId) ∧ s.nextId ≤ MaxId

/-! ## 仕様そのものの確かめ（小さい例。アリス = 1、ボブ = 2） -/
section examples
private def s1 := (add empty 1 "牛乳").2
private def s2 := (add s1 1 "卵").2
private def s3 := (add s2 2 "ボブの用事").2
example : (add empty 1 "牛乳").1 = some 0 := by decide
example : (add s2 2 "ボブの用事").1 = some 2 := by decide
example : openCount s3 1 = 2 ∧ openCount s3 2 = 1 := by decide
example : openCount (toggle s3 1 0).2 1 = 1 := by decide
example : (toggle s3 1 9).1 = false := by decide
example : (remove s3 1 1).2.items.map (·.title) = ["牛乳", "ボブの用事"] := by decide
example : visible s3 1 = [0, 1] ∧ visible s3 2 = [2] := by decide
-- ボブはアリスの todo を切り替えも削除もできない
example : toggle s3 2 0 = (false, s3) := by decide
example : remove s3 2 0 = (false, s3) := by decide
end examples

/-! ## 不変条件は、どの操作のあとも保たれる -/

theorem inv_empty : Inv empty := by simp [Inv, empty, MaxId]

theorem inv_add (s : State) (u : Nat) (title : String) (h : Inv s) : Inv (add s u title).2 := by
  obtain ⟨hnd, hlt, hle⟩ := h
  unfold add
  split
  · exact ⟨hnd, hlt, hle⟩
  · rename_i hne
    show ((s.items ++ [(⟨s.nextId, u, title, false⟩ : Todo)]).map (fun t : Todo => t.id)).Nodup ∧
      (∀ t ∈ s.items ++ [(⟨s.nextId, u, title, false⟩ : Todo)], t.id < s.nextId + 1) ∧ s.nextId + 1 ≤ MaxId
    refine ⟨?_, ?_, ?_⟩
    · simp only [List.map_append, List.map_cons, List.map_nil]
      rw [List.nodup_append]
      refine ⟨hnd, List.nodup_singleton _, ?_⟩
      intro a ha b hb
      simp only [List.mem_singleton] at hb
      simp only [List.mem_map] at ha
      obtain ⟨t, ht, rfl⟩ := ha
      have := hlt t ht
      omega
    · intro t ht
      simp only [List.mem_append, List.mem_singleton] at ht
      rcases ht with ht | rfl
      · have := hlt t ht; omega
      · simp
    · omega

/-- toggle は id を変えない。 -/
theorem toggle_ids (s : State) (u id : Nat) :
    (toggle s u id).2.items.map (·.id) = s.items.map (·.id) := by
  simp only [toggle, List.map_map]
  apply List.map_congr_left
  intro t _
  simp only [Function.comp]
  split <;> rfl

theorem inv_toggle (s : State) (u id : Nat) (h : Inv s) : Inv (toggle s u id).2 := by
  obtain ⟨hnd, hlt, hle⟩ := h
  refine ⟨?_, ?_, ?_⟩
  · rw [toggle_ids]; exact hnd
  · intro t ht
    simp only [toggle, List.mem_map] at ht
    obtain ⟨v, hv, rfl⟩ := ht
    have := hlt v hv
    split <;> simpa
  · exact hle

theorem inv_remove (s : State) (u id : Nat) (h : Inv s) : Inv (remove s u id).2 := by
  obtain ⟨hnd, hlt, hle⟩ := h
  refine ⟨?_, ?_, ?_⟩
  · simp only [remove]
    exact (List.filter_sublist.map _).nodup hnd
  · intro t ht
    simp only [remove, List.mem_filter] at ht
    exact hlt t ht.1
  · exact hle

/-! ## 使う人から見た性質 -/

/-- 足すと、自分の未完了が1件増える。 -/
theorem add_openCount (s : State) (u : Nat) (title : String) (h : s.nextId ≠ MaxId) :
    openCount (add s u title).2 u = openCount s u + 1 := by
  simp [add, h, openCount, List.filter_append]

/-- 2回切り替えると元に戻る。 -/
theorem toggle_toggle (s : State) (u id : Nat) : (toggle (toggle s u id).2 u id).2 = s := by
  cases s with
  | mk items nextId =>
    simp only [toggle, List.map_map, State.mk.injEq, and_true]
    conv => rhs; rw [← List.map_id items]
    apply List.map_congr_left
    intro t _
    simp only [Function.comp]
    by_cases ht : mine u id t = true
    · have : mine u id { t with done := !t.done } = true := by simpa [mine] using ht
      simp [ht, this]
    · simp [ht]

/-- 消したあと、自分のその id はどこにも無い。 -/
theorem remove_gone (s : State) (u id : Nat) :
    ∀ t ∈ (remove s u id).2.items, mine u id t = false := by
  intro t ht
  simp only [remove, List.mem_filter, Bool.not_eq_true'] at ht
  exact ht.2

/-- 消しても、ほかの todo はそのまま残る。 -/
theorem remove_keeps (s : State) (u id : Nat) (t : Todo) (ht : t ∈ s.items)
    (hne : mine u id t = false) : t ∈ (remove s u id).2.items := by
  simp [remove, ht, hne]

/-! ## 認可（主役）

1. 他人の todo は変わらない: u が何をしても、ほかの人 v の持ち物は1件も変わらない
2. 見えるのは自分の todo だけ: u に見せる id は、u が持ち主の todo の id とちょうど一致する
3. 他人の id を指定しても何も起きない: 失敗を返し、状態はそのまま -/

theorem add_others (s : State) (u v : Nat) (title : String) (huv : u ≠ v) :
    ownedBy (add s u title).2 v = ownedBy s v := by
  unfold add; split
  · rfl
  · simp [ownedBy, List.filter_append, huv]

theorem toggle_others (s : State) (u v id : Nat) (huv : u ≠ v) :
    ownedBy (toggle s u id).2 v = ownedBy s v := by
  simp only [ownedBy, toggle]
  rw [List.filter_map]
  conv => rhs; rw [← List.map_id (List.filter _ s.items)]
  simp only [Function.comp_def]
  rw [List.filter_congr (q := (·.owner == v))]
  · apply List.map_congr_left
    intro t ht
    simp only [List.mem_filter, beq_iff_eq] at ht
    have : mine u id t = false := by simp [mine, ht.2, Ne.symm huv]
    simp [this]
  · intro t _; split <;> rfl

theorem remove_others (s : State) (u v id : Nat) (huv : u ≠ v) :
    ownedBy (remove s u id).2 v = ownedBy s v := by
  simp only [ownedBy, remove, List.filter_filter]
  apply List.filter_congr
  intro t _
  by_cases h : t.owner = v
  · simp [mine, h, Ne.symm huv]
  · simp [h]

theorem visible_iff (s : State) (u x : Nat) :
    x ∈ visible s u ↔ ∃ t ∈ s.items, t.id = x ∧ t.owner = u := by
  simp only [visible, ownedBy, List.mem_map, List.mem_filter, beq_iff_eq]
  constructor
  · rintro ⟨t, ⟨ht, ho⟩, rfl⟩; exact ⟨t, ht, rfl, ho⟩
  · rintro ⟨t, ht, rfl, ho⟩; exact ⟨t, ⟨ht, ho⟩, rfl⟩

/-- 不変条件のもとで、id 番の todo が他人のものなら、どれも u の「自分の id 番」ではない。 -/
theorem none_mine (s : State) (u id : Nat) (h : Inv s) (t : Todo) (ht : t ∈ s.items)
    (hid : t.id = id) (ho : t.owner ≠ u) : ∀ x ∈ s.items, mine u id x = false := by
  obtain ⟨hnd, -, -⟩ := h
  intro x hx
  by_cases hxid : x.id = id
  · have : x = t := List.inj_on_of_nodup_map hnd hx ht (by rw [hxid, hid])
    subst this; simp [mine, ho]
  · simp [mine, hxid]

theorem toggle_foreign (s : State) (u id : Nat) (h : Inv s) (t : Todo) (ht : t ∈ s.items)
    (hid : t.id = id) (ho : t.owner ≠ u) : toggle s u id = (false, s) := by
  have hnone := none_mine s u id h t ht hid ho
  cases s with
  | mk items nextId =>
    simp only [toggle, Prod.mk.injEq, State.mk.injEq, and_true]
    refine ⟨?_, ?_⟩
    · simpa using hnone
    · conv => rhs; rw [← List.map_id items]
      apply List.map_congr_left
      intro x hx; simp [hnone x hx]

theorem remove_foreign (s : State) (u id : Nat) (h : Inv s) (t : Todo) (ht : t ∈ s.items)
    (hid : t.id = id) (ho : t.owner ≠ u) : remove s u id = (false, s) := by
  have hnone := none_mine s u id h t ht hid ho
  cases s with
  | mk items nextId =>
    simp only [remove, Prod.mk.injEq, State.mk.injEq, and_true]
    refine ⟨?_, ?_⟩
    · simpa using hnone
    · rw [List.filter_eq_self]; intro x hx; simp [hnone x hx]

end Spec
