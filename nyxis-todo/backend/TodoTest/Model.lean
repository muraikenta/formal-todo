import Todo.App

/-!
# TodoTest.Model — Todo アプリのハンドラとポリシーのモデル検査

Nyxis のランタイムの純粋なモデル（`Nyxis.Runtime.handleRequest`）で `Todo.app` を動かし、主体ごとの許可・拒否と
HTTP ステータスを `#guard` で確かめる。HTTP サーバ・JWT・PostgreSQL は含まない（実 DB の確認は scripts/ で別にやる）。

Nyxis の定理が保証するのは「ハンドラは承認したポリシーの範囲を超えない」こと。**ポリシー自体が意図どおりか**
（他人の Todo が読めないか）は定理の外なので、ここで具体例として確かめる。
-/

namespace TodoTest.Model

open Cedar.Spec
open Cedar.Data
open Nyxis
open Nyxis.Db
open Nyxis.Authz
open Nyxis.Runtime

def app : App := Todo.app

def userT : EntityType := ⟨"User", []⟩
def todoT : EntityType := ⟨"Todo", []⟩
def user (id : String) : EntityUID := ⟨userT, id⟩
def todo (id : String) : EntityUID := ⟨todoT, id⟩

def row (kvs : List (Column × Cell)) : Row := Map.make kvs
def todoRow (owner title : String) (done : Bool) : Row :=
  row [("owner", user owner), ("title", title), ("done", done)]

/-- 初期状態: alice の Todo が2件、bob の Todo が1件。 -/
def store : Store := Map.make
  [ (user "alice", row [("name", "Alice")])
  , (user "bob", row [("name", "Bob")])
  , (todo "a1", todoRow "alice" "牛乳を買う" false)
  , (todo "a2", todoRow "alice" "請求書を送る" true)
  , (todo "b1", todoRow "bob" "bob の秘密の予定" false) ]

def alice : Principal := .user (user "alice")
def bob : Principal := .user (user "bob")
def anon : Principal := .anonymous

def gen : Generated := { now := ⟨1700000000000⟩, id := "00000000-0000-4000-8000-000000000001" }

def req (p : Principal) (method : Std.Http.Method) (path : String) (body : String := "") : AuthenticatedRequest :=
  { principal := p, generated := gen, request := { method := method, path := path, body := body } }

def status (s : Store) (r : AuthenticatedRequest) : UInt16 := (handleRequest app s r).result.status.toCode
def body (s : Store) (r : AuthenticatedRequest) : String := (handleRequest app s r).result.body
def after (s : Store) (r : AuthenticatedRequest) : Store := (handleRequest app s r).store
def contains (haystack needle : String) : Bool := (haystack.splitOn needle).length > 1

/-! ## 一覧: 自分の Todo だけが出る -/

#guard status store (req alice .get "/todos") == 200
#guard contains (body store (req alice .get "/todos")) "牛乳を買う"
#guard contains (body store (req alice .get "/todos")) "請求書を送る"
#guard !contains (body store (req alice .get "/todos")) "秘密"
#guard contains (body store (req bob .get "/todos")) "秘密"
#guard !contains (body store (req bob .get "/todos")) "牛乳"
-- 匿名は空の一覧（行ごとの認可で全部落ちる）。
#guard body store (req anon .get "/todos") == "[]"

/-! ## 1件: 他人の Todo は読めない -/

#guard status store (req alice .get "/todos/a1") == 200
#guard status store (req bob .get "/todos/a1") == 403
#guard status store (req anon .get "/todos/a1") == 403
-- 無い ID も 403（存在するかどうかを漏らさない）。
#guard status store (req alice .get "/todos/nope") == 403

/-! ## 作成: 持ち主は必ず自分。ID は Nyxis が決める -/

#guard status store (req alice .post "/todos" "{\"title\":\"散歩\"}") == 201
#guard body store (req alice .post "/todos" "{\"title\":\"散歩\"}") == "{\"id\":\"00000000-0000-4000-8000-000000000001\"}"
#guard (after store (req alice .post "/todos" "{\"title\":\"散歩\"}")).find? todoT gen.id ==
  some (todoRow "alice" "散歩" false)
-- 本文で owner を偽っても、持ち主は JWT の主体（ハンドラが本文の owner を読まない）。
#guard (after store (req alice .post "/todos" "{\"title\":\"x\",\"owner\":\"bob\"}")).find? todoT gen.id ==
  some (todoRow "alice" "x" false)
#guard status store (req anon .post "/todos" "{\"title\":\"x\"}") == 403
#guard status store (req alice .post "/todos" "{\"title\":\"   \"}") == 400
#guard status store (req alice .post "/todos" "not json") == 400

/-! ## 更新・削除: 他人の Todo には何もできず、DB も変わらない -/

#guard status store (req alice .post "/todos/a1/done") == 204
#guard (after store (req alice .post "/todos/a1/done")).find? todoT "a1" == some (todoRow "alice" "牛乳を買う" true)
#guard (after store (req alice .post "/todos/a2/undone")).find? todoT "a2" == some (todoRow "alice" "請求書を送る" false)
#guard (after store (req alice .patch "/todos/a1" "{\"title\":\"豆乳を買う\"}")).find? todoT "a1" ==
  some (todoRow "alice" "豆乳を買う" false)
#guard status store (req alice .delete "/todos/a1") == 204
#guard ((after store (req alice .delete "/todos/a1")).find? todoT "a1").isNone

#guard status store (req bob .post "/todos/a1/done") == 403
#guard status store (req bob .patch "/todos/a1" "{\"title\":\"乗っ取り\"}") == 403
#guard status store (req bob .delete "/todos/a1") == 403
#guard after store (req bob .post "/todos/a1/done") == store
#guard after store (req bob .patch "/todos/a1" "{\"title\":\"乗っ取り\"}") == store
#guard after store (req bob .delete "/todos/a1") == store
#guard after store (req anon .delete "/todos/b1") == store

/-! ## ユーザー: 自分の行だけ -/

#guard status store (req alice .get "/users/alice") == 200
#guard status store (req alice .get "/users/bob") == 403
#guard status (Map.make []) (req alice .post "/users/alice" "{\"name\":\"Alice\"}") == 201
#guard status (Map.make []) (req alice .post "/users/bob" "{\"name\":\"偽 Bob\"}") == 403
#guard status store (req alice .post "/users/alice" "{}") == 409

/-! ## ルーティングに無いパス -/

#guard status store (req alice .get "/nope") == 404

end TodoTest.Model
