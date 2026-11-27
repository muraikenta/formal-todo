# h5i で作る todo アプリ（Rust のカーネルを Lean で証明する）

[h5i](https://github.com/h5i-dev/h5i)（Axum ベースの Rust web フレームワーク。判断を「カーネル」という純粋関数に集め、Charon/Aeneas で Lean 4 に翻訳して証明する）で、ユーザーごとの todo アプリを作った（2026-11-27）。手本は h5i 同梱の掲示板チュートリアル（`examples/app/board`）。

## できたもの

- 組織（テナント）の中で、各ユーザーが自分の todo を持つ。追加・名前変更・完了切り替え・削除・一覧
- 判断はすべて [kernel/src/lib.rs](kernel/src/lib.rs) の `transition` 1関数。サーバ（[server/src/lib.rs](server/src/lib.rs)）は JSON と PostgreSQL の受け渡しだけで、何も決めない
- 画面 [server/static/index.html](server/static/index.html) は `POST /rpc` を呼ぶだけ。ユーザー切り替え（alice / bob）と「他人の todo を id 指定で触ってみる」欄つき

## 証明したこと（`h5i app check` で 108 定理、標準の3公理だけ・sorry なし）

| 定理 | 言っていること |
|---|---|
| `Theorems.authorized_reachable` | 成功したコマンドの書き込みは、すべて呼び出した本人の todo（新規か自分のもの）だけ |
| `Theorems.others_unchanged` | どのコマンドの後も、他のユーザーの todo は1件も変わらない |
| `Theorems.list_own` | 一覧の返事は「呼び出した本人の todo」ちょうど（他人のものは出ない） |
| `Theorems.owner_kept` | どのコマンドも todo の持ち主を変えない |
| `Theorems.reachable_inv` | 到達できるすべての状態で、id が重複しない・次の id より小さい・タイトルが 1〜140 バイト |
| `Effects.*_effect` | 頼んだことをやる: 追加は新しい id を返し未完了で保存し既存を上書きしない／名前変更は新タイトル＋完了状態はそのまま／完了切り替えは指定どおりの値／削除はその id を消す |
| `Effects.*_ok` | 持ち主の正しい操作は必ず成功する（何でも断るカーネルでは通らない） |
| `Theorems.panic_free` | どの入力でもカーネルが落ちない（オーバーフロー・範囲外アクセスなし） |
| `Storage.db_inv` | PostgreSQL に書いて読み戻しても不変条件が保たれる（h5i の共通定理に接続） |
| `Scenario.*` | 具体例: Alice が追加 → Bob は完了にも削除もできず、Bob の一覧の返事は空 |

ミューテーション（わざと壊したカーネル）は 15/15 で検出（[h5i-app.toml](h5i-app.toml) の `[[mutant]]`）。

## 分かったこと

- **「悪いことが起きない」だけの定理は、何もしないカーネルでも通る**。最初の版は認可・他人不変・不変条件だけを gate していて、独立レビュー（エージェント3視点＋反証役）に「名前変更が新タイトルを無視しても、完了フラグを勝手に戻しても、全部 Ok で何も書かなくても gate は通る」と指摘された。`Effects.lean`（やったことの中身＋持ち主の操作は成功する）を足して塞いだ
- ミューテーションの「捕まった」は、**定理の主張が偽になった**のか**証明スクリプトが壊れただけ**かを区別しない。15件とも最初に止まったのは各コマンドの補題（`Commands.lean`）で、gate した定理の主張そのものが偽になったかまでは h5i は見ていない
- Rust 側の欄名 `done` が、Aeneas の生成コードのループ制御 `done` と衝突して Lean がコンパイルできなかった → `completed` に改名（JSON では `done` のまま）
- 先に `cargo test` すると `h5i_app_lean_schema_is_current` が落ちる（`schema!` の Lean が古い）。`h5i app extract` → `cargo test` の順にする

## 証明していないところ（信頼している境界）

- JSON ⇔ コマンドの変換（`server/src/lib.rs`）、冪等キーの返事の保存、HMAC トークン、組織（テナント）の切り分け（h5i の engine と `tenant-isolation` の自動証明が担う）。PostgreSQL・Charon/Aeneas/Lean 自体
- 画面はトークンを URL の `#` に載せている（手元の動作確認用。本番の作りではない）

## 動かし方

道具の版は h5i（commit `0226696`）の `pins.rs` に合わせる: Charon `4bd5a29`・Aeneas `b86120d`・Lean v4.31.0。筆者の環境（macOS）では Aeneas の macOS 版リリース（`nightly-2026.09.28-b86120d`）を `~/src/h5i-tools` に展開し、h5i CLI も同じ場所に `cargo install --path ~/src/h5i --no-default-features --root ~/src/h5i-tools` で入れた。

```bash
export PATH=$HOME/src/h5i-tools:$HOME/src/h5i-tools/bin:/opt/homebrew/opt/rustup/bin:$PATH
```

```bash
cd h5i-todo && h5i app prove . && h5i app mutate .
```

```bash
cd h5i-todo && ./run.sh
```

`run.sh` は Docker で PostgreSQL（`h5i-todo-pg`、127.0.0.1:55433）を立て、alice・bob のトークンを入れた URL（http://127.0.0.1:8787/#alice=…&bob=…）を出してサーバを起動する。初回の `lake build` は Mathlib のキャッシュ取得込みで数分。
