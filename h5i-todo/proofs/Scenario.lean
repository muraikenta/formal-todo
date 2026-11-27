import Theorems
/-!
# A concrete run

A real run meets the theorems' hypotheses: Alice adds "hi". Then Bob can
neither check it off nor delete it, and his listing is empty.
-/
open Aeneas Aeneas.Std Result todo_kernel todo_kernel.Spec todo_kernel.Commands todo_kernel.Theorems H5iAppLib

namespace todo_kernel.Scenario

def alice : Principal := ⟨0#u64, 1#u64⟩
def bob : Principal := ⟨0#u64, 2#u64⟩
def hi : alloc.vec.Vec U8 := alloc.vec.Vec.from [104#u8, 105#u8] (by scalar_tac)

/-- The empty app. -/
def s0 : Snapshot := ⟨⟨0#u64⟩, alloc.vec.Vec.new Todo⟩
/-- Alice has added "hi". -/
def s1 : Snapshot := ⟨⟨1#u64⟩, alloc.vec.Vec.from [⟨0#u64, 1#u64, hi, false⟩] (by scalar_tac)⟩

theorem run {a s c r} {P : alloc.vec.Vec Write → Prop}
    (h : transition a s c ⦃ o => ∃ ws, o = .Ok (ws, r) ∧ P ws ⦄) :
    ∃ ws, transition a s c = ok (.Ok (ws, r)) ∧ P ws := by
  obtain ⟨o, ho, ws, rfl, hp⟩ := (WP.spec_equiv_exists _ _).1 h
  exact ⟨ws, ho, hp⟩

/-- Alice adds "hi" with id 0. -/
theorem add_hi : transition alice s0 (.Add hi) ⦃ r => ∃ ws, r = .Ok (ws, .Created 0#u64) ∧
    ws.val = [.PutTodo ⟨0#u64, 1#u64, hi, false⟩, .SetCounter ⟨1#u64⟩] ⦄ := by
  simp only [transition]; unfold add
  repeat' (first | step | split)
  all_goals simp_all [s0, alice, hi, titleOk, core.num.U64.MAX, U64.rMax]
  · scalar_tac
  · exact (u64_val_eq _ _).1 (by simpa using i_post)

/-- The app reaches `s1`. -/
theorem s1_reachable : Reachable (Snapshot.toSt s1) := by
  have h0 : Reachable (Snapshot.toSt s0) := by
    have : Snapshot.toSt s0 = init := by simp [Snapshot.toSt, s0, init]
    rw [this]; exact .init
  obtain ⟨ws, ht, hws⟩ := run add_hi
  have := Reachable.step h0 ht
  rwa [hws, show applyAll (Snapshot.toSt s0) [.PutTodo ⟨0#u64, 1#u64, hi, false⟩, .SetCounter ⟨1#u64⟩] =
    Snapshot.toSt s1 by simp [applyAll, applyWrite, Snapshot.toSt, s0, s1, upsert]] at this

/-- Bob does not own Alice's todo, so he cannot check it off. -/
theorem bob_cannot_set_done : transition bob s1 (.SetDone 0#u64 true) = ok (.Err .Forbidden) := by
  apply eq_ok_of_spec
  simp only [transition]; unfold set_done
  repeat' (first | step | split)
  all_goals simp_all [s1, bob]

/-- Nor delete it. -/
theorem bob_cannot_delete : transition bob s1 (.Delete 0#u64) = ok (.Err .Forbidden) := by
  apply eq_ok_of_spec
  simp only [transition]; unfold delete
  repeat' (first | step | split)
  all_goals simp_all [s1, bob]

/-- Bob's listing is empty, while Alice's todo is stored. -/
theorem bob_sees_nothing : mine (Snapshot.toSt s1) bob.user.val = [] ∧
    mine (Snapshot.toSt s1) alice.user.val = [⟨0#u64, 1#u64, hi, false⟩] := by
  simp [mine, Snapshot.toSt, s1, alice, bob]

/-- And it is the kernel's `List` reply that is empty for Bob, not just the spec's `mine`. -/
theorem bob_lists_nothing : transition bob s1 .List ⦃ r => ∃ v, r = .Ok (alloc.vec.Vec.new Write, .Todos v) ∧ v.val = [] ⦄ :=
  WP.spec_mono (list_own bob s1) (fun _ ⟨v, hr, hv⟩ => ⟨v, hr, hv.trans bob_sees_nothing.1⟩)

end todo_kernel.Scenario
