import Lake
open Lake DSL

-- Pinned to the Aeneas commit that generated generated/TodoKernel.lean
-- (the same pin as h5i 0226696ca1c12e929be2969ecd64fd46772ffd35).
require aeneas from git
  "https://github.com/AeneasVerif/aeneas" @ "b86120db3183b0107eb5f2637b11c424cd06ef1c" / "backends/lean"

require h5i_app_lib from git
  "https://github.com/h5i-dev/h5i" @ "0226696ca1c12e929be2969ecd64fd46772ffd35" / "crates/h5i-app-core/proofs"

package todo_proofs

-- Generated Lean: the extracted Rust (`h5i app extract`). Do not edit.
lean_lib Generated where
  srcDir := "generated"
  roots := #[`TodoKernel, `Schema]

-- Hand-written specification and proofs.
@[default_target] lean_lib Proofs where
  roots := #[`Spec, `Commands, `Theorems, `Effects, `Apply, `Storage, `Scenario]
