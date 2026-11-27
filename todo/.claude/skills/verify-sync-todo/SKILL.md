---
name: verify-sync-todo
description: Sync Todo の同期（src/sync.ts の outbox・再送・mergeRows・lastSeq、src/server-store.ts の applyOne の再送判定、src/app.ts の push/pull ループと clientId・localStorage への保存・リロード）を変えたときに、TLA+ モデル verification/SyncTodo.tla を pstack の statechart スクリプトで検査して「確認済みの操作が黙って捨てられない」「同じクライアントの操作が順に1回ずつ反映される」「同期が済んだら全タブがサーバと同じ一覧になる」「積んだ操作がどこからも送られなくならない」が崩れていないか確かめる。sync.ts・server-store.ts・api.ts・app.ts の同期まわりを触った変更、op や opId の形、clientId や保存キーの決め方、再送・タイムアウト・pull の取り込み方を変える変更のときに使う。
---

# Sync Todo の同期を形式検証する

テストは書いた順番しか試さない。このモデルは、2 つのタブとサーバの間で「送る・届かない・タイムアウトする・遅れて届く・差分を取り込む・リロードする・閉じる」が**どの順に起きても**、下の 4 つの約束が守られるかを TLC（TLA+ のモデル検査器）で全部の順番について調べる。

**モデルはコードを読まない。** コードを変えても、モデルを同じ意味に直さずに回せば結果は変わらない（変更前と同じ緑が出る）。

## 守る約束（性質）と、破れたときの害

| 性質（`verification/SyncTodo.tla`） | 一文で | 破れたときの害 |
|---|---|---|
| `AckedMeansApplied` | 確認が来たとして送信待ちから外した操作は、その操作としてサーバに反映されている | ユーザーの変更がエラーも出さずに消え、画面は「同期済み」と出る |
| `ClientOrderKept` | 同じクライアント ID の操作は、サーバで連番の順に 1 回ずつ反映処理される | 遅れて届いた古い再送が、あとから付けた名前や完了を巻き戻す |
| `Converged` | 送信待ちも届く途中の要求も無く、全タブが最後まで pull したら、全タブの一覧がサーバと同じ | タブごとに違う一覧が出たまま直らない |
| `NoOpLost` | ユーザーが積んだ操作は、サーバに反映済みか、開いているタブの送信待ちにあるか、サーバに向かう途中の要求に入っている | 操作がどこからも送られなくなり、エラーも出ずに消える |

## この検査が見ているコード（カバレッジ）

最後にモデルがコードどおりだと確かめたコミット（同期コミット）: **このリポジトリの最初のコミット**（元の作業リポジトリでのコミット。この公開リポジトリでは最初のコミットの `todo/` がそれに当たる）

| モデルのアクション・演算子 | コード |
|---|---|
| `YouCreate` / `YouRename` / `YouToggle` / `YouDelete` → `Enqueue` | `src/app.ts` の `act`・`render` 内のイベント・`new-form` の submit → `src/sync.ts` の `enqueue` / `newOpId` |
| `CanTouch`・`StaleUI` | `src/app.ts` の `render` の先頭の `if (editingId && ...) return;`。編集欄にフォーカスがある間は描き直さないので、イベントのクロージャ（`t`・`cb.checked`・`t.id`）が古い描画のままになりうる |
| `ApplyOp` / `Replay` / `View` | `src/sync.ts` の `applyOp` / `view`（並び順・`pending`・絞り込みは見ない） |
| `MergeRows` | `src/sync.ts` の `mergeRows` |
| `Save` / `store` | `src/app.ts` の `setState`（`localStorage[todo-state:<clientId>]` に毎回保存）。`Enqueue`・`PushOk`・`PullOk` の最後で呼ぶ |
| `PushStart` | `src/app.ts` の `push`（await の前まで）＋ `src/sync.ts` の `nextBatch` |
| `ServerPush` → `ApplyAll` / `ApplyOne` | `src/api.ts` の `handlePush` → `src/server-store.ts` の `TodoStore.push`（1 トランザクション）/ `applyOne` |
| `PushOk` | `src/app.ts` の `push`（await の後）＋ `src/sync.ts` の `applyPushResult`（lastSeq は動かさない） |
| `PushGivesUp`・`RequestLost` | `src/app.ts` の `request`（`AbortSignal.timeout`・不安定な回線）と `push` の catch |
| `PullRead` / `PullOk` | `src/app.ts` の `pull` → `src/api.ts` の `handlePull` → `TodoStore.pull` → `src/sync.ts` の `applyPull`（lastSeq を進める） |
| `OpenNewTab` / `DuplicateTab` | `src/app.ts` の `loadClientId`（sessionStorage）と `loadState`（localStorage） |
| `Reload` | ページの読み直し: `loadClientId`（sessionStorage は残る）→ `loadState`。`pushing`・`pulling`・届く途中の応答は消える |
| `CloseTab` | タブを閉じる: sessionStorage（＝クライアント ID）が消え、`todo-state:<ID>` は残るが、以後開くタブは新しい ID を作るので誰も読まない |

1 アクションは、コードで途中に `await` が挟まらない 1 区間（JS は単一スレッドなので、その区間は割り込まれない）。サーバの `push` は SQLite の 1 トランザクションなので 1 アクション。

## 変更がこの検査に関係するかの見分け方

```sh
git diff --stat $(git rev-list --max-parents=0 HEAD) -- todo/src
```

上の表のファイルの、表に出てくる関数が変わっていたら関係する。`src/server.ts`・`public/`・`render` の見た目だけの変更（DOM の組み立て、CSS）は関係しない。迷ったら関係するとみなす。

## 回し方

**関係する変更なら、回す前にカバレッジ表の該当アクション・演算子を、変更後のコードと同じ意味に直す（直し方は下の「変更を意図してモデルを直すとき」）。直さずに回した緑は何も示さない。**

道具は pstack の statechart スクリプト。pstack の `statechart` skill は `disable-model-invocation: true` なので、**エージェントは Skill ツールで `/statechart` を呼べない。スクリプトを直接実行する**（使い方の正本はその SKILL.md の「Run」節）。場所の探し方:

```sh
S=$(ls -d ~/src/cursor-plugins/pstack/skills/statechart/scripts/statechart 2>/dev/null \
  || find ~ -path '*pstack/skills/statechart/scripts/statechart' -type f 2>/dev/null | head -1); echo "$S"
```

筆者の環境では `~/src/cursor-plugins/pstack/skills/statechart/scripts/statechart`。初回は mise で TLC と Java を入れるのでネットワークが要る。

```sh
V=todo/verification; O=$(mktemp -d)
for c in SyncTodo SyncTodoTwoTodos SyncTodoDuplicateTab SyncTodoDuplicateReload SyncTodoCloseTab; do
  echo "=== $c"; "$S" "$V/SyncTodo.tla" --config "$V/$c.cfg" --view "$V/view.mjs" --out "$O/$c"
done
```

config ごとの「正常」（同期コミット 公開時点 時点）:

| config | 何を入れたか | 正常な結果 | 規模（1 ワーカー） |
|---|---|---|---|
| `SyncTodo.cfg` | 別のタブで URL を開く・リロードあり・todo 1 件 | **Rules that hold に 4 つ並ぶ** | 1,499,907 状態・約 90 秒 |
| `SyncTodoTwoTodos.cfg` | 同じで todo 2 件（`MaxPush = 2`）。**todo をまたぐ不具合（lastSeq の進め方・pull の取りこぼし）は todo 1 件では原理的に出ない**（push の応答の行がいつもその行の最新版になる）ので、必ず回す | **Rules that hold に 4 つ並ぶ** | 651,021 状態・約 40 秒 |
| `SyncTodoDuplicateTab.cfg` | タブの複製・リロード無し | `AckedMeansApplied` と `NoOpLost` が 9 ステップで破れる（既知の発見 1）。残りは「Rules not checked」 | 数秒 |
| `SyncTodoDuplicateReload.cfg` | タブの複製・リロードあり | `NoOpLost` が 5 ステップで破れる（既知の発見 2）。`AckedMeansApplied` も 9 ステップで破れる | 数秒 |
| `SyncTodoCloseTab.cfg` | 別のタブで URL を開く・タブを閉じるあり | `NoOpLost` が 2 ステップで破れる（既知の発見 3） | 数秒 |
| `SyncTodoStaleUI.cfg`（重いので任意） | `SyncTodo.cfg` の画面の操作の条件を古いクロージャまで広げた上位集合 | **4 つとも成り立つ** | 16,004,587 状態。TLC 直接・8 ワーカーで約 2.5 分（statechart の 1 ワーカーだと 15 分以上の見込み）。`render`・`act`・イベントまわりを変えたときに回す |

破れる config の「Rules not checked」は、statechart が最初の違反の後の再実行を 10 万状態で打ち切るための表示で、成り立つという意味ではない。発見を直したら、その config も「4 つ並ぶ」が正常になる。

結果は statechart の report の読み方で読む。破れた性質は最短経路が出る。経路のタブの表示は「ID・送信待ちの中身（連番:種類）・送信中か・取り込み済み seq」、サーバの表示は todo ごとの「名前・完了・seq」。

## 結果の読み方: 本物のバグか、モデルの誤りか

1. report の最短経路を、上のカバレッジ表でコードの関数に置き換えて 1 ステップずつ読む
2. その経路を本物のコードで再現する bun test を、リポジトリの外（作業用の一時フォルダにコピーしたアプリ）に書く
   - 同期だけの経路: `src/sync.ts` の純粋関数と `src/api.ts` の `handlePush` / `handlePull` を、`tests/e2e.test.ts` の `Net` / `Client` と同じ形で呼び、1 アクション = 1 呼び出しで並べる。タブの複製は `JSON.parse(JSON.stringify(state))` で写す
   - リロード・タブを閉じる・保存が絡む経路: 本物の `src/app.ts` を `import("../src/app.ts?load=N")` でタブごとに別のモジュールとして読み込み、`document`（最小の偽物）・`sessionStorage`（タブごと）・`localStorage`（共有）・`setTimeout`（溜めて手で回す）・`fetch`（`handlePush` / `handlePull` に直結）を差し替える。リロード = 同じ sessionStorage でもう一度 import、閉じて開き直す = 空の sessionStorage で import。偽物の環境でも送信が起きることを対照の試験で先に確かめる
3. 再現できたら本物のバグ。再現できなければ、モデルがコードと違うと考えて、違うアクションを探して直す（性質を弱めて通すのは禁止）

## 既知の発見（同期コミット 公開時点 時点。すべて本物のコードで再現済み・リポジトリには置いていない）

### 発見 1: タブを複製すると、片方のタブの操作が黙って捨てられる（`AckedMeansApplied`）

1. タブ1で todo「A」を追加する（op `c1:1`）
2. タブを複製する。sessionStorage が写るので `loadClientId` は同じ ID `c1` を返し、`loadState` は同じ状態（`nextOpNo = 2`）を読む
3. タブ1で名前を「B」に変える → op `c1:2`
4. タブ2で完了にする → これも op `c1:2`
5. 両方が送る。サーバは先に届いたタブ1の `c1:2` を反映し、あとのタブ2の `c1:2` を `applied_ops` で「再送」と見なして反映しない
6. タブ2は応答の `results` に `c1:2` があるので outbox から外し、「同期済み」と出る。サーバの todo は「B」未完了のまま

捨てられるのは名前・完了の変更だけではない。両方のタブの重なった op が**追加**なら、あとのタブの todo は作られない。応答の `todo` は `null` なので、そのタブの画面からも todo が消え、表示は「同期済み」になる（todo 2 件の試験で再現: タブ1 が X、タブ2 が Y を同じ `c1:1` で追加 → タブ2 の一覧は X だけ）。

### 発見 2: 複製したタブ同士は保存を上書きし合い、リロードすると自分の送信待ちが消える（`NoOpLost`）

複製した 2 つのタブは同じキー `todo-state:c1` に `setState` のたびに状態全体を保存する。どちらかをリロードすると、最後に保存した**もう一方のタブ**の状態を読む。自分の送信待ちと `nextOpNo` はそれで置き換わり、まだ送っていない操作はエラーも出ずに消える。`nextOpNo` が戻ると、すでに使った opId をもう一度作るので、発見 1 と同じ取り違えも起きうる。

- モデルの最短経路（5 ステップ）: タブ1で追加 → 複製 → タブ1で名前を変える（`c1:2` 名前）→ タブ2で完了（`c1:2` 完了。保存が上書きされる）→ タブ1をリロード → タブ1の送信待ちが「1:追加・2:完了」になり、名前の変更が消える
- 本物の `src/app.ts` で再現: タブ1で X を送る → 複製（タブ2はオフライン）→ タブ2で Y を追加（送信待ち 1 件）→ タブ1で Z を追加して送る（保存が上書き）→ タブ2をリロード → 表示は「同期済み」、サーバは X と Z だけ。対照（タブ1が保存しない場合）では Y は送られる

### 発見 3: 送信待ちが残ったタブを閉じると、その操作は二度と送られない（`NoOpLost`）

クライアント ID はそのタブの sessionStorage にしか無く、送信待ちは `localStorage[todo-state:<ID>]` に残る。タブを閉じて URL を開き直すと sessionStorage は空なので新しい ID を作り、古いキーは誰も読まない。README の「変更は「送信待ち」として残り、つながったら送られる」は、オフラインのままタブを閉じると成り立たない。

- モデルの最短経路（2 ステップ）: タブ1で追加 → タブ1を閉じる
- 本物の `src/app.ts` で再現: オフラインで X を追加（送信待ち 1 件）→ 空の sessionStorage で開き直す → 「同期済み」、サーバに X は無く、古いキーは残るだけ。対照（同じ sessionStorage で開き直す＝閉じたタブの復元）では X は送られる

### 直し方の候補（どれも未検証。直すかどうかは未定）

- **「クライアント ID をタブの起動ごとに作り直す」だけはやらない。** ID が sessionStorage にあるのはリロードをまたいで同じ ID を使うためで、保存キーもその ID で決まる。起動ごとに新しい ID にすると、リロードのたびに新しいキーを読むことになり、前のキーの送信待ちは送られずに消える（発見 3 と同じ害がリロードで毎回起きる）
- 複製の検出（例: 起動時に `navigator.locks` か `BroadcastChannel` で「同じ ID のタブが生きているか」を確かめる）をして、**複製されたタブだけ**新しい ID と新しいキーに移る。そのとき写ってきた送信待ちは捨てずに新しいキーへ持っていく（opId はそのままなので、もう一方のタブと二重に送ってもサーバは同じ op として 1 回だけ反映する）
- opId を op ごとの UUID にする（発見 1 は消えるが、発見 2・3 は残る）
- 起動時に、どのタブも持っていない `todo-state:*` のキーの送信待ちを引き取って送る（発見 3 への手当て）

直したら、モデルの該当アクション（`DuplicateTab`・`Reload`・`CloseTab`・`Enqueue` など）を直したコードと同じ意味に書き換え、破れていた config で 4 つとも成り立つことを確かめてから、この節と上の表の「正常」を書き直す。

## 変更を意図してモデルを直すとき

- コードの変更に合わせて、表の該当アクション・演算子を同じ意味に書き換える。アクションの区切り（await の位置・トランザクションの範囲）が変わったら、アクションを分ける／まとめる。`setState` を呼ぶ場所が増減したら `Save` の位置も合わせる
- 性質（`AckedMeansApplied` / `ClientOrderKept` / `Converged` / `NoOpLost`）を弱めて通さない。約束そのものが変わった（README の「競合のルール」が変わった）ときだけ、README と一緒に変える
- 直したら、性質ごとに「壊した版で破れる」ことを 1 回は確かめる（下の壊し方）
- モデルがコミット X のコードどおりだと確かめてから、この SKILL.md の同期コミットを X に進める。確かめていないのに進めない

## 壊した版で検査が働くことの確かめ方（作業用のコピーで。本物のコードは変えない）

コードとモデルの両方に同じ壊し方を入れる。コードの方は既存の `bun test` が赤になること、モデルの方は下の config で破れることを確かめる。

| 性質 | コードの壊し方 | モデルでの対応 | 出る結果 |
|---|---|---|---|
| `ClientOrderKept` | `server-store.ts` の `applyOne` から `applied_ops` の照合（`seen`）を消し、INSERT を `INSERT OR IGNORE` に | `ApplyOne` の `IF \E a \in st.applied : SameOpId(a, op)` を `IF FALSE` に | `SyncTodo.cfg` で 6 ステップ（送る→タイムアウト→再送→両方届く） |
| `Converged` | `sync.ts` の `mergeRows` の `row.version > cur.version` を外して常に置き換える | `MergeRows` の候補から手元の行 `c[i]` を外す（届いた行があれば必ずそれに置き換える） | `SyncTodo.cfg` で 15 ステップ（タブ1 の古い push 応答が、pull で取り込んだ新しい行を上書き） |
| `Converged`（todo をまたぐ） | `sync.ts` の `applyPushResult` に `lastSeq: Math.max(state.lastSeq, ...rows.map((r) => r.seq))` を足す（push の時点で lastSeq を進める） | `PushOk` で `lastSeq'[t]` を返ってきた行の seq の最大値まで進める | **`SyncTodo.cfg`（todo 1 件）では素通りする。`SyncTodoTwoTodos.cfg` で 11 ステップ**（両タブが別の todo を作って送る → タブ2 の lastSeq がタブ1 の行の seq を飛び越える → タブ2 にタブ1 の todo が出ない）。bun test は e2e の 'offline client catches up after reconnecting' が赤 |
| `AckedMeansApplied`・`NoOpLost` | `sync.ts` の `newOpId` で opId から clientId を外す | `SameOpId` を `a.no = b.no` だけに | `SyncTodo.cfg` で 10 ステップ（別タブの `2` がタブ1 の `2` と取り違えられる） |

## この検査が見ていないこと

- **範囲**: todo 1 件（`SyncTodoTwoTodos.cfg` だけ 2 件）・名前 2 種類・各タブの操作 2 回まで（`MaxOpNo = 2`）・2 タブ合わせて push 3 回まで（`MaxPush = 3`、2 件の config は 2 回）。これより大きい場合は保証しない
- **タブの一生**: タブは 2 枚まで。タブ 1 は最初から開いていて、タブ 2 は 1 回だけ、タブ 1 から（新しい URL か複製で）開く。3 枚目のタブ、2 回目の複製、複製したタブの複製、閉じたタブを開き直すこと（新しい URL でも、閉じたタブの復元でも）は無い。新しい URL で開き直すと新しい ID になって古いキーを読まないので、発見 3 には影響しない。閉じたタブの復元（sessionStorage が戻る）で送信待ちが戻ることはモデルに無い（本物のコードの対照の試験では戻った）
- **送る単位の上限**: 送信待ちは高々 2 件なので、`nextBatch` の 50 件ずつの分割（複数回に分けて一部だけ確認が来る場合）と、サーバの「200 件を超えると 400」は一度も起きない
- **pull のページ送り**（`TodoStore.pull` の limit 500）。モデルに無く、この範囲では起きないので、正しさは調べていない
- サーバの入力検査と 400（クライアントは正しい op しか作らない前提）。1 件でも不正な op が outbox に入ると、その先が永久に送られない可能性は見ていない
- localStorage への保存の失敗（`setState` の catch）。保存に失敗したままリロードすると古い `nextOpNo` に戻り、発見 1 と同じ opId の取り違えが起きうるが、モデルには入れていない（`Save` は必ず成功する）
- 画面の並び順・`pending` 表示・絞り込み。編集中に描画を止める処理（`editingId`）は、表示だけでなく積まれる op にも効く（古いクロージャ）。通常の config は「今の表示どおりの操作」だけを積み、`SyncTodoStaleUI.cfg` がその上位集合で 4 つとも成り立つことを確かめている
- 「いつかは同期が済む」こと（活性）。性質はすべて不変条件で、`Converged` は「済んだら一致する」だけを見る
- 削除が最終であること・`create` で墓標が戻らないことは `tests/server-store.test.ts` に任せた（id が毎回新しい UUID なので、このモデルの範囲では別の op が同じ id を作らない）
- pull の失敗と push の応答の消失は、それぞれ「pull していない」「PushGivesUp」と同じ状態になるので、アクションとして別に置いていない
