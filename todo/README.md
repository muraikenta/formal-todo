# Sync Todo

複数のタブ・端末から同じ一覧を使える、小さな Todo アプリ。あとで形式検証（モデル化・性質の検査）の題材にするため、実際の Web アプリにある「楽観的更新＋送信待ちキュー＋再送＋差分の取り込み」の形で作ってある。

- できること: 追加・名前の変更（ダブルクリック）・完了の切り替え・削除・絞り込み（すべて／未完了／完了）
- 画面は回線が切れていても動き、変更は「送信待ち」として残り、つながったら送られる
- 画面下の「不安定な回線を再現」をオンにすると、要求の 3 割を送る前に失敗させ、3 割を「サーバは反映したが応答が消えた」扱いにする

構成は Bun 1.3 ＋ TypeScript だけ（サーバは `Bun.serve` と `bun:sqlite`、画面は素の DOM。実行時の依存ゼロ）。

## 動かし方

```sh
bun run dev          # http://localhost:3457/ （PORT=4000 bun run dev で変更）
bun test             # または bun run test
```

- DB は既定で `./todo.db`（`DB_PATH` で変更）。`.gitignore` 済み
- 同じ URL を別タブで開くと、それぞれ別のクライアントになる（クライアント ID は `sessionStorage`、状態は `localStorage` にクライアントごとに保存）

## 同期の設計

### データ

- サーバの1行: `id`・`title`・`done`・`version`（その todo が変わるたびに +1。作成時 1）・`deleted`（削除の墓標。行は消さない）・`seq`（サーバ全体の通し番号のうち、その行が最後に変わったときの値）
- 操作（op）: `create` / `rename` / `setDone` / `delete` の4種類。どれも `opId`（`クライアントID:連番`）を持つ。`create` の `id` はクライアントが作る UUID

### クライアント（`src/sync.ts`。純粋関数だけ）

- 状態は `confirmed`（サーバから最後に聞いた行。墓標を含む）・`outbox`（まだサーバの確認が無い op を操作順に）・`lastSeq`（取り込み済みの通し番号）
- 画面に出すのは `confirmed` の上に `outbox` の op を順に当て直したもの（`view`）。押した瞬間に画面が変わり、確認が来るまで自分の変更が見え続ける
- 送信（`POST /api/push`）は `outbox` の先頭から最大 50 件を順番どおりに送る。応答の `results` にある `opId` だけを `outbox` から外し、返ってきた行を `confirmed` に取り込む
- 失敗・タイムアウト（5 秒）・応答の消失はどれも区別せず「届いたか分からない」として、同じ op を同じ `opId` のまま再送する（間隔は 0.5 秒から倍々、上限 10 秒）
- 取り込み（`GET /api/pull?since=lastSeq`）は 2 秒ごと。返ってきた行は、手元の `confirmed` より `version` が大きいときだけ置き換える。`lastSeq` は pull の応答でだけ進める（push の応答で進めると、他のクライアントの変更を飛ばすため）

### サーバ（`src/server-store.ts`）

- 1 回の push は 1 トランザクション。先に全件の入力を検査し、1件でも不正なら何も反映せず 400
- 反映した `opId` は全部 `applied_ops` に記録する。同じ `opId` がもう一度来たら反映せず、いまの行を返す（＝再送しても二重にならない。遅れて届いた古い再送が新しい値を巻き戻すこともない）
- `create` は同じ `id` の行が既にあれば何もしない（別の `opId` でも同じ）

### 競合のルール

1. **サーバに届いた順で後勝ち（項目ごと）**。`rename` は `title` だけ、`setDone` は `done` だけを書くので、A が名前を変え B が完了にした場合は両方残る。同じ項目を両方が変えたら、サーバに後から届いた方が残る
2. **削除は最終**。墓標になった todo への `rename` / `setDone` は無視し、同じ `id` の `create` でも復活しない
3. 値が変わらない op（同じ名前への変更など）は `version` も `seq` も進めない

`version` は「どちらが新しいか」をクライアントが判断するためのもので、サーバは version の一致を要求しない（楽観ロックで弾く方式ではない）。弾く方式にすると、楽観的に出した変更を画面で取り消す処理が要るため。

## ファイル

| ファイル | 中身 |
|---|---|
| `src/types.ts` | サーバの行・op・API の型 |
| `src/sync.ts` | クライアントの同期ロジック（純粋関数: `enqueue` / `view` / `applyOp` / `nextBatch` / `applyPushResult` / `applyPull` / `mergeRows`） |
| `src/server-store.ts` | SQLite への保存と op の反映ルール（`TodoStore.push` / `pull`） |
| `src/api.ts` | HTTP の薄い層（JSON の読み書きと 400 の返し方） |
| `src/server.ts` | 起動。画面（HTML import で Bun が都度バンドル）と API を配る |
| `src/app.ts` | 画面: 描画・保存・送信と取り込みのループ |
| `public/index.html` / `public/style.css` | 画面の骨組みと見た目 |
| `tests/sync.test.ts` | 純粋関数の単体試験 |
| `tests/server-store.test.ts` | 反映ルール（再送・削除が最終・不正な入力・ページ送り） |
| `tests/e2e.test.ts` | 複数クライアント＋本物の HTTP ハンドラ＋失敗する回線（応答の消失後の再送・2台の同時編集・削除と編集の競合・オフラインからの復帰） |

## API

```sh
curl -XPOST localhost:3457/api/push -H 'content-type: application/json' \
  -d '{"clientId":"c1","ops":[{"opId":"c1:1","kind":"create","id":"t1","title":"牛乳"}]}'
# => {"results":[{"opId":"c1:1","todo":{"id":"t1","title":"牛乳","done":false,"version":1,"deleted":false,"seq":1}}]}

curl 'localhost:3457/api/pull?since=0'
# => {"changes":[...],"seq":1}
```

存在しない `id` への op は `todo: null` を返す（op 自体は反映済みとして記録する）。
