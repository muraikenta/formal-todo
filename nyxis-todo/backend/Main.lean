import Todo
import Todo.Server

/-! Sample-specific startup, trusted connection code under Assumptions 1 and 3, outside the theorem.
Sample runs its final application audit before this module imports the internal database
bridge. Do not import this launcher from application modules or expand AppCheck's trust set.
Credentials come only from the environment; startup performs no DDL or data seeding.
-/

-- The deployment used by startup is definitionally the declared sources; a well-typed
-- replacement of `Server.deployment.sources` fails here at build time.
example : Todo.Server.deployment.sources = Todo.Approved.sources := rfl

-- Keep the concrete declaration and deployment axiom checks with this application.
run_cmd do
  for n in [``Todo.Approved.app_schema, ``Todo.Approved.app_policies,
      ``Todo.Approved.authorization_safety, ``Todo.Server.serve_handler,
      ``Todo.Server.readAll_response] do
    let axioms ← Lean.collectAxioms n
    for a in axioms do
      unless [``propext, ``Classical.choice, ``Quot.sound].contains a do
        throwError "{n} depends on a disallowed axiom: {a}"

#print axioms Todo.Approved.authorization_safety
#print axioms Todo.Server.serve_handler
#print axioms Todo.Server.readAll_response

def main (args : List String) : IO Unit := do
  let port : UInt16 ← match args with
    | [] => pure 8080
    | [s] => match s.toNat? with
      | some n =>
        if 0 < n && n ≤ 65535 then pure n.toUInt16
        else throw (IO.userError "port out of range")
      | none => throw (IO.userError "port is not a number")
    | _ => throw (IO.userError "usage: todoServer [port]")
  let some conninfo ← IO.getEnv "NYXIS_DATABASE_URL"
    | throw (IO.userError "NYXIS_DATABASE_URL is required")
  if conninfo.trimAscii.isEmpty || conninfo.contains '\x00' then
    throw (IO.userError "NYXIS_DATABASE_URL is invalid")
  let some issuer ← IO.getEnv "NYXIS_SUPABASE_ISSUER"
    | throw (IO.userError "NYXIS_SUPABASE_ISSUER is required")
  if (Nyxis.Internal.JwksFetch.urlOfIssuer issuer).isNone then
    throw (IO.userError "NYXIS_SUPABASE_ISSUER is invalid")
  let cors ← match Nyxis.Internal.Cors.parse ((← IO.getEnv "NYXIS_CORS_ORIGINS").getD "") with
    | .ok config => pure config
    | .error message => throw (IO.userError message)
  IO.println s!"todo: PostgreSQL backend, listening on port {port}"
  Todo.Server.serve port conninfo issuer Todo.router cors
