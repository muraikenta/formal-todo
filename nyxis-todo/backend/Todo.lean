import Todo.Approved
import Todo.Handlers
import Todo.App
import Nyxis.AppCheck

/-!
# Todo — Nyxis で作った Todo アプリのバックエンド

- `Todo.Approved` — 人が承認する正本 `schema.cedarschema` と `policies.cedar` の宣言と、認可安全性の定理
- `Todo.Handlers` — 各エンドポイントのハンドラ（`Nyxis.Handler`）とルーティング `Todo.router`
- `Todo.App` — 宣言とルーティングを組み合わせたアプリ `Todo.app`
- 起動は `Main.lean`（このモジュールを import する）

末尾の `nyxis_check_app` が、アプリ側の全モジュールの定義と属性をビルド時に監査する。新しいモジュールは必ずここから
import し、このチェックの後ろには宣言を置かない。
-/

nyxis_check_app
