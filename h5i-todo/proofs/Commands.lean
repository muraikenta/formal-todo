import Spec
/-!
# What each command does

List specs for the helpers, then one lemma per command: the writes it makes
when it succeeds. `Theorems.lean` uses only these lemmas.
-/
open Aeneas Aeneas.Std Result todo_kernel todo_kernel.Spec H5iAppLib

namespace todo_kernel.Commands

attribute [simp] u64_val_eq

/-! ## Helpers -/

theorem todo_clone (t : Todo) : Todo.Insts.CoreCloneClone.clone t = ok t := by
  simp [Todo.Insts.CoreCloneClone.clone, u8vec_clone, lift]

@[step] theorem todo_clone_spec (t : Todo) : Todo.Insts.CoreCloneClone.clone t ⦃ q => q = t ⦄ := by
  simp [todo_clone]

@[step] theorem one_spec (w : Write) : one w ⦃ v => v.val = [w] ⦄ := by
  unfold one; step*

@[step] theorem title_ok_spec (t : alloc.vec.Vec U8) : title_ok t ⦃ b => b = true ↔ titleOk t.val ⦄ := by
  unfold title_ok titleOk
  step*
  all_goals (simp only [MAX_TITLE] at *; simp_all [alloc.vec.Vec.length]; try scalar_tac)

@[step] theorem find_todo_spec (ts : alloc.vec.Vec Todo) (id : U64) :
    find_todo ts id ⦃ o => o = ts.val.find? (fun t => t.id.val = id.val) ⦄ := by
  unfold find_todo find_todo_loop
  apply WP.spec_mono (loop_search ts.val (fun t => decide (t.id = id)) (fun o : Option Todo => o)
    (fun _ t => some t) none _ ?_ 0#usize (by simp))
  · intro r hr; rw [search_find _ _ _ hr]; simp
  · intro j hj; unfold find_todo_loop.body; h5i_step

/-- The todos a listing keeps. -/
def ownedBy (u : U64) (t : Todo) : Bool := t.owner = u

@[step] theorem todos_of_spec (ts : alloc.vec.Vec Todo) (u : U64) :
    todos_of ts u ⦃ v => v.val = ts.val.filter (ownedBy u) ⦄ := by
  unfold todos_of todos_of_loop
  apply WP.spec_mono (loop_fold ts.val (fun w : alloc.vec.Vec Todo => w.val)
    (fun acc x => if ownedBy u x then acc ++ [x] else acc)
    (fun w j => w.length ≤ j) (fun x => todos_of_loop.body ts u x.1 x.2) ?_ _ 0#usize (by simp) (by simp))
  · intro r hr; rw [hr, foldl_filter]; simp
  · intro o j hj ho
    have := ts.len_ineq
    unfold todos_of_loop.body
    step* <;> (repeat' (first | step | split | simp only [bind_ok] at *)) <;>
      (try simp only [FoldStep]) <;> (try simp_all [ownedBy]) <;> scalar_tac

/-! ## Commands

What a successful run writes, and which facts made it succeed. Refusals write
nothing. -/

/-- A todo with a fresh id owned by the caller, not done, and the counter moved past it. -/
theorem add_spec (u : U64) (s : Snapshot) (t : alloc.vec.Vec U8) :
    add u s t ⦃ r => ∀ ws rep, r = .Ok (ws, rep) → rep = .Created s.counter.next_id ∧ titleOk t.val ∧
      ∃ c : Counter, c.next_id.val = s.counter.next_id.val + 1 ∧
        ws.val = [.PutTodo ⟨s.counter.next_id, u, t, false⟩, .SetCounter c] ⦄ := by
  unfold add
  step*
  -- Left after `step*`: `next_id + 1` does not overflow.
  simp only [core.num.U64.MAX, U64.rMax] at *; scalar_tac

theorem findTodo_of (s : Snapshot) (id : U64) (o : Option Todo)
    (ho : o = s.todos.val.find? (fun t => t.id.val = id.val)) {q : Todo} (h : o = some q) :
    findTodo (Snapshot.toSt s) id.val = some q := by
  simp only [findTodo, Snapshot.toSt]; rw [← ho]; exact h

/-- A new title for one of the caller's todos; id, owner and done are kept. -/
theorem rename_spec (u : U64) (s : Snapshot) (id : U64) (ti : alloc.vec.Vec U8) :
    rename u s id ti ⦃ r => ∀ ws rep, r = .Ok (ws, rep) → rep = .Done ∧ titleOk ti.val ∧
      ∃ q, findTodo (Snapshot.toSt s) id.val = some q ∧ q.owner = u ∧
        ws.val = [.PutTodo ⟨id, u, ti, q.completed⟩] ⦄ := by
  unfold rename
  step*
  intro ws rep h; obtain ⟨rfl, rfl⟩ := ok_inj h
  have ha : t.owner = u := by simpa using ‹¬(t.owner != u) = true›
  refine ⟨rfl, b_post.1 ‹_›, t, findTodo_of s id o o_post ‹o = some t›, ha, ?_⟩
  simp [v1_post, ha, v_post]

/-- A new done flag for one of the caller's todos; id, owner and title are kept. -/
theorem set_done_spec (u : U64) (s : Snapshot) (id : U64) (d : Bool) :
    set_done u s id d ⦃ r => ∀ ws rep, r = .Ok (ws, rep) → rep = .Done ∧
      ∃ q, findTodo (Snapshot.toSt s) id.val = some q ∧ q.owner = u ∧
        ws.val = [.PutTodo ⟨id, u, q.title, d⟩] ⦄ := by
  unfold set_done
  step*
  intro ws rep h; obtain ⟨rfl, rfl⟩ := ok_inj h
  have ha : t.owner = u := by simpa using ‹¬(t.owner != u) = true›
  refine ⟨rfl, t, findTodo_of s id o o_post ‹o = some t›, ha, ?_⟩
  simp [v_post, ha]

theorem delete_spec (u : U64) (s : Snapshot) (id : U64) :
    delete u s id ⦃ r => ∀ ws rep, r = .Ok (ws, rep) → rep = .Done ∧
      (∃ q, findTodo (Snapshot.toSt s) id.val = some q ∧ q.owner = u) ∧
        ws.val = [.DelTodo id] ⦄ := by
  unfold delete
  step*
  intro ws rep h; obtain ⟨rfl, rfl⟩ := ok_inj h
  exact ⟨rfl, ⟨t, findTodo_of s id o o_post ‹o = some t›, ‹t.owner = u›⟩, v_post⟩

end todo_kernel.Commands
