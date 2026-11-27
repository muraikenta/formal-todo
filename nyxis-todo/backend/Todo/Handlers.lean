import Lean.Data.Json
import Nyxis

/-!
# Todo.Handlers — Todo アプリのハンドラとルーティング

ハンドラは `Nyxis.Handler` で書く。持てる効果は認可層へのアクション呼び出し（`Handler.callAction`）だけで、
IO や DB には直接届かない。主体は JWT から、対象は DB の今の行から、効果は schema.cedarschema の宣言から
Nyxis が決める。ハンドラが決めるのは「どの行に・どのアクションを・どの値で呼ぶか」と「結果をどう HTTP にするか」だけ。

| メソッドとパス               | アクション      | 本文（JSON）            | 成功 |
|------------------------------|-----------------|-------------------------|------|
| `GET    /todos`              | `listTodos`     | なし                    | 200 と配列 |
| `GET    /todos/{id}`         | `readTodo`      | なし                    | 200 と行 |
| `POST   /todos`              | `createTodo`    | `title`（必須）         | 201 と `{"id": …}` |
| `PATCH  /todos/{id}`         | `renameTodo`    | `title`（必須）         | 204 |
| `POST   /todos/{id}/done`    | `setDone`       | なし（done = true）     | 204 |
| `POST   /todos/{id}/undone`  | `setDone`       | なし（done = false）    | 204 |
| `DELETE /todos/{id}`         | `deleteTodo`    | なし                    | 204 |
| `POST   /users/{id}`         | `registerUser`  | `name`（任意）          | 201 |
| `GET    /users/{id}`         | `readUser`      | なし                    | 200 と行 |

認可層の結果は `denied` → 403、`notFound` → 404、`conflict` → 409。Todo の `owner` は本文ではなく
リクエストの主体から決める。新しい Todo の ID は Nyxis が要求ごとに決める一意 ID（`Generated.id`）を使う。
-/

namespace Todo

open Lean (Json)
open Cedar.Spec
open Nyxis
open Nyxis.Authz
open Nyxis.Db (Key Row Column Cell)

/-- スキーマのアクション `Action::"<name>"`。 -/
def act (name : String) : EntityUID := ⟨⟨"Action", []⟩, name⟩

/-! ## 行と JSON の変換 -/

def cellToJson : Cell → Json
  | .prim (.string s) => .str s
  | .prim (.bool b) => .bool b
  | .prim (.int i) => .num i.toInt
  | .prim (.entityUID uid) => .str uid.eid
  | _ => .null

def rowToJson (row : Row) : Json :=
  Json.mkObj (row.toList.map fun kv => (kv.1, cellToJson kv.2))

/-- 一覧の行を JSON 配列にする。各要素に主キーを `id` として足す。 -/
def rowsToJson (rows : List (Key × Row)) : Json :=
  Json.arr (rows.map fun kv =>
    Json.mkObj (("id", Json.str kv.1) :: kv.2.toList.map fun c => (c.1, cellToJson c.2))).toArray

def parseObject (body : String) : Except String Json := do
  let json ← Json.parse body
  match json with
  | .obj _ => pure json
  | _ => throw "JSON object expected"

def stringField (json : Json) (name : String) : Except String (Option Cell) :=
  match json.getObjVal? name with
  | .error _ => pure none
  | .ok v => match v.getStr? with
    | .ok s => pure (some (.prim (.string s)))
    | .error _ => throw s!"{name}: string expected"

/-- 空白だけのタイトルは受け付けない。 -/
def nonEmptyTitle (json : Json) : Except String Cell := do
  match ← stringField json "title" with
  | some (.prim (.string s)) =>
    if s.trimAscii.isEmpty then throw "title must not be empty" else pure (.prim (.string s))
  | _ => throw "title expected"

def rowOf (fields : List (Column × Option Cell)) : Row :=
  Cedar.Data.Map.make (fields.filterMap fun f => f.2.map (f.1, ·))

/-! ## 結果の対応付け -/

def respond (success : Std.Http.Status) (body : Option Row → String) : Outcome → Http.Response
  | .ok row => { status := success, body := body row }
  | .list rows _ => { status := .ok, body := (rowsToJson rows).compress }
  | .denied => { status := .forbidden, body := "forbidden" }
  | .notFound => { status := .notFound, body := "not found" }
  | .conflict => { status := .conflict, body := "conflict" }
  -- 添付・外部 API の効果は宣言していないので、以下は起きない（関数を全域にするためだけにある）。
  | .signed _ => { status := .notFound, body := "not found" }
  | .called _ => { status := .notFound, body := "not found" }
  | .calledError _ _ => { status := .notFound, body := "not found" }

def noContent : Outcome → Http.Response := respond .noContent (fun _ => "")

def badRequest (message : String) : Http.Response := { status := .badRequest, body := message }

def rowBody (row : Option Row) : String := (row.map fun r => (rowToJson r).compress).getD ""

/-! ## ハンドラ -/

/-- `GET /todos` — 認可を通った行だけが返る（他人の Todo は一覧に出ない）。 -/
def listTodos : Principal → Generated → Http.Request → Handler Http.Response := fun _ _ _ => do
  let outcome ← Handler.callAction (act "listTodos") ""
  pure (respond .ok (fun _ => "") outcome)

/-- `GET /todos/{id}` -/
def readTodo (id : Key) : Principal → Generated → Http.Request → Handler Http.Response := fun _ _ _ => do
  let outcome ← Handler.callAction (act "readTodo") id
  pure (respond .ok rowBody outcome)

/-- `POST /todos` — 持ち主は主体。ID は Nyxis が決めた一意 ID。 -/
def createTodo : Principal → Generated → Http.Request → Handler Http.Response := fun principal gen req => do
  let parsed : Except String Row := do
    -- 本文の JSON から、空でないタイトルを取り出す
    let json ← parseObject req.body
    let title ← nonEmptyTitle json
    pure (rowOf
      -- owner は本文の値ではなく、ログインした主体
      [ ("owner", some (.prim (.entityUID principal.uid)))
      , ("title", some title)
      -- 作ったばかりの todo は未完了
      , ("done", some (.prim (.bool false))) ])
  match parsed with
  | .error e => pure (badRequest e)
  | .ok row =>
    respond .created (fun _ => (Json.mkObj [("id", Json.str gen.id)]).compress) <$>
      Handler.callAction (act "createTodo") gen.id row

/-- `PATCH /todos/{id}` — タイトルを変える。 -/
def renameTodo (id : Key) : Principal → Generated → Http.Request → Handler Http.Response := fun _ _ req => do
  let parsed : Except String Row := do
    let json ← parseObject req.body
    let title ← nonEmptyTitle json
    pure (rowOf [("title", some title)])
  match parsed with
  | .error e => pure (badRequest e)
  | .ok changes => noContent <$> Handler.callAction (act "renameTodo") id changes

/-- `POST /todos/{id}/done` と `/undone` -/
def setDone (id : Key) (done : Bool) : Principal → Generated → Http.Request → Handler Http.Response :=
  fun _ _ _ => noContent <$> Handler.callAction (act "setDone") id (rowOf [("done", some (.prim (.bool done)))])

/-- `DELETE /todos/{id}` -/
def deleteTodo (id : Key) : Principal → Generated → Http.Request → Handler Http.Response := fun _ _ _ =>
  noContent <$> Handler.callAction (act "deleteTodo") id

/-- `POST /users/{id}` — 自分の User 行を作る。 -/
def registerUser (id : Key) : Principal → Generated → Http.Request → Handler Http.Response := fun _ _ req => do
  let parsed : Except String Row := do
    let json ← if req.body.trimAscii.isEmpty then pure (Json.mkObj []) else parseObject req.body
    let name ← stringField json "name"
    pure (rowOf [("name", name <|> some (.prim (.string "")))])
  match parsed with
  | .error e => pure (badRequest e)
  | .ok row => respond .created (fun _ => "") <$> Handler.callAction (act "registerUser") id row

/-- `GET /users/{id}` -/
def readUser (id : Key) : Principal → Generated → Http.Request → Handler Http.Response := fun _ _ _ => do
  let outcome ← Handler.callAction (act "readUser") id
  pure (respond .ok rowBody outcome)

/-! ## ルーティング -/

def segments (path : String) : List String :=
  (path.splitOn "/").filter (· ≠ "")

def router : Http.Router := fun method path =>
  match method, segments path with
  | .get, ["todos"] => some listTodos
  | .post, ["todos"] => some createTodo
  | .get, ["todos", id] => some (readTodo id)
  | .patch, ["todos", id] => some (renameTodo id)
  | .post, ["todos", id, "done"] => some (setDone id true)
  | .post, ["todos", id, "undone"] => some (setDone id false)
  | .delete, ["todos", id] => some (deleteTodo id)
  | .post, ["users", id] => some (registerUser id)
  | .get, ["users", id] => some (readUser id)
  | _, _ => none

end Todo
