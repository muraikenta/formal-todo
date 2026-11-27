--------------------------- MODULE SyncTodo ---------------------------
(***************************************************************************)
(* Sync Todo の同期（楽観的更新 + 送信待ち + 再送 + pull）のモデル。        *)
(* 各アクションの上に、対応するコードのファイルと関数を書いてある。        *)
(* 1 アクション = コードで途中に await が挟まらない 1 区間。               *)
(*                                                                         *)
(* タブの一生（範囲）: タブ 1 は最初から開いている。タブ 2 は定数          *)
(* SecondTab に従って、「別のタブで同じ URL を開く」(OpenNewTab) か        *)
(* 「タブ 1 を複製する」(DuplicateTab) で 1 回だけ開く。3 枚目のタブ、     *)
(* 2 回目の複製、複製したタブの複製は無い。CanReload なら各タブは何度でも  *)
(* リロードでき、CanClose なら各タブは 1 回閉じられる（閉じたタブは二度と *)
(* 開かない。新しい URL で開き直すと新しいクライアント ID になり、閉じた   *)
(* タブの localStorage のキーは誰も読まないので、それと同じ）。            *)
(* 複製したタブには sessionStorage が写るので、src/app.ts の loadClientId  *)
(* は同じクライアント ID を返し、loadState は同じ localStorage の状態を    *)
(* 読む（ブラウザの仕様。HTML Standard の session storage の複製）。        *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Ids,        \* 作れる todo の id（crypto.randomUUID の代わり。1 回ずつしか出ない）
          Titles,     \* 付けられる名前
          MaxOpNo,    \* 各タブの nextOpNo の上限（操作の回数の上限）
          MaxPush,    \* 2 つのタブが push を始める回数の合計の上限
          SecondTab,  \* タブ 2 の開き方: "new"（別タブで URL を開く）か "duplicate"（タブを複製する）
          CanReload,  \* TRUE ならタブのリロード（Reload）を入れる
          CanClose,   \* TRUE ならタブを閉じる（CloseTab）を入れる
          StaleUI     \* TRUE なら画面の操作の条件を「古い描画のままのクロージャ」まで広げる（下の YouRename など）

Tabs == {1, 2}
Cids == {"c1", "c2"}   \* クライアント ID（crypto.randomUUID の代わり）
\* 行が無いこと（コードの null / undefined）。TLC は型の違う値を比べられないので、
\* version = 0 の行で表す（実在の行の version は 1 から）
None == [id |-> 0, title |-> "", done |-> FALSE, version |-> 0, deleted |-> FALSE, seq |-> 0]
NoLocal == [title |-> "", done |-> FALSE, deleted |-> FALSE, ex |-> FALSE]
Idle == [busy |-> FALSE, changes |-> {}, seq |-> 0]

VARIABLES
  \* ---- サーバ: src/server-store.ts の TodoStore ----
  rows,        \* todos テーブル: id -> 行 or None
  srvSeq,      \* meta テーブルの 'seq'
  applied,     \* applied_ops。コードは op_id だけを保存する。ここでは op 全体を持ち、
               \* 照合は opId だけで行う（opId 以外はゴースト＝性質を書くためだけ）
  \* ---- クライアント: src/sync.ts の ClientState と src/app.ts のフラグ ----
  open,        \* タブが開いているか
  closed,      \* タブを閉じたか（閉じたタブは二度と開かない）
  cid,         \* ClientState.clientId（sessionStorage の todo-client-id）
  nextNo,      \* ClientState.nextOpNo
  outbox,      \* ClientState.outbox
  conf,        \* ClientState.confirmed: id -> 行 or None
  lastSeq,     \* ClientState.lastSeq
  pushing,     \* app.ts の pushing。0 = 送っていない、n = n 回目の push の応答待ち
  pushN,       \* そのタブが始めた push の回数（要求を見分ける番号）
  pullSt,      \* app.ts の pulling。Idle か、届く途中の pull の応答（busy = TRUE）
  \* ---- ブラウザの保存先 ----
  store,       \* localStorage の todo-state:<clientId>。クライアント ID -> 最後に setState で保存した
               \* [nextNo, outbox, conf, lastSeq]。複製したタブ同士は同じキーに上書きし合う
  \* ---- ネットワーク ----
  reqs,        \* 送ったがサーバがまだ処理していない push 要求 [tab, n, ops]
  resps,       \* サーバが処理し、届く途中の push 応答 [tab, n, results]
  \* ---- ゴースト（性質を書くためだけ。コードには無い） ----
  usedIds,     \* 作成に使った id
  made,        \* ユーザーの操作で outbox に積んだ op 全部
  acked,       \* クライアントが「確認が来た」として outbox から外した op
  lastExec,    \* クライアント ID ごとに、サーバが applyOne で最後に反映処理した op の連番
  orderOk      \* 反映処理した op の連番が、クライアント ID ごとに毎回増えてきたか

vars == <<rows, srvSeq, applied, open, closed, cid, nextNo, outbox, conf, lastSeq,
          pushing, pushN, pullSt, store, reqs, resps, usedIds, made, acked, lastExec, orderOk>>

-----------------------------------------------------------------------------
(* op と行 *)
MkOp(c, no, kind, id, title, done) ==
  [cid |-> c, no |-> no, kind |-> kind, id |-> id, title |-> title, done |-> done]
SameOpId(a, b) == a.cid = b.cid /\ a.no = b.no

Min(a, b) == IF a < b THEN a ELSE b
Max(a, b) == IF a > b THEN a ELSE b
Range(s) == {s[i] : i \in DOMAIN s}

-----------------------------------------------------------------------------
(* src/sync.ts: applyOp（outbox を画面用に当て直す） *)
ApplyOp(todos, op) ==
  LET cur == todos[op.id] IN
  CASE op.kind = "create"  -> IF cur.ex THEN todos
                              ELSE [todos EXCEPT ![op.id] = [title |-> op.title, done |-> FALSE, deleted |-> FALSE, ex |-> TRUE]]
    [] op.kind = "rename"  -> IF ~cur.ex \/ cur.deleted THEN todos
                              ELSE [todos EXCEPT ![op.id].title = op.title]
    [] op.kind = "setDone" -> IF ~cur.ex \/ cur.deleted THEN todos
                              ELSE [todos EXCEPT ![op.id].done = op.done]
    [] op.kind = "delete"  -> IF ~cur.ex THEN todos
                              ELSE [todos EXCEPT ![op.id].deleted = TRUE]

RECURSIVE Replay(_, _)
Replay(todos, ops) == IF ops = <<>> THEN todos ELSE Replay(ApplyOp(todos, Head(ops)), Tail(ops))

Local(r) == IF r.version = 0 THEN NoLocal ELSE [title |-> r.title, done |-> r.done, deleted |-> r.deleted, ex |-> TRUE]

(* src/sync.ts: view（墓標を除いた一覧。並び順と pending 表示は見ない） *)
ListOf(todos) == {[id |-> i, title |-> todos[i].title, done |-> todos[i].done] :
                    i \in {j \in Ids : todos[j].ex /\ ~todos[j].deleted}}
ViewTodos(t) == Replay([i \in Ids |-> Local(conf[t][i])], outbox[t])
View(t) == ListOf(ViewTodos(t))
ServerView == ListOf([i \in Ids |-> Local(rows[i])])

(* src/sync.ts: mergeRows。行を順に見て version が大きいときだけ置き換えるので、  *)
(* 結果は id ごとに「手元と届いた行のうち version が最大のもの」になる。        *)
MergeRows(c, rs) ==
  [i \in Ids |->
     LET cand == {r \in rs : r.id = i} \cup {c[i]} IN
     CHOOSE r \in cand : \A s \in cand : s.version <= r.version]

-----------------------------------------------------------------------------
(* src/server-store.ts: TodoStore.applyOne。st はサーバの状態のレコード *)
ApplyOne(st, op) ==
  IF \E a \in st.applied : SameOpId(a, op)
  THEN [st EXCEPT !.results = Append(@, [op |-> op, todo |-> st.rows[op.id]])]
  ELSE
    LET cur == st.rows[op.id]
        s1  == st.seq + 1
        nr  == CASE op.kind = "create" /\ cur.version = 0 ->
                      [id |-> op.id, title |-> op.title, done |-> FALSE, version |-> 1, deleted |-> FALSE, seq |-> s1]
                 [] op.kind = "rename" /\ cur.version # 0 /\ ~cur.deleted /\ cur.title # op.title ->
                      [cur EXCEPT !.title = op.title, !.version = @ + 1, !.seq = s1]
                 [] op.kind = "setDone" /\ cur.version # 0 /\ ~cur.deleted /\ cur.done # op.done ->
                      [cur EXCEPT !.done = op.done, !.version = @ + 1, !.seq = s1]
                 [] op.kind = "delete" /\ cur.version # 0 /\ ~cur.deleted ->
                      [cur EXCEPT !.deleted = TRUE, !.version = @ + 1, !.seq = s1]
                 [] OTHER -> cur
        changed == nr # cur
        rows2 == [st.rows EXCEPT ![op.id] = nr]
    IN [rows    |-> rows2,
        seq     |-> IF changed THEN s1 ELSE st.seq,
        applied |-> st.applied \cup {op},
        last    |-> [st.last EXCEPT ![op.cid] = op.no],
        ok      |-> st.ok /\ op.no > st.last[op.cid],
        results |-> Append(st.results, [op |-> op, todo |-> rows2[op.id]])]

RECURSIVE ApplyAll(_, _)
ApplyAll(st, ops) == IF ops = <<>> THEN st ELSE ApplyAll(ApplyOne(st, Head(ops)), Tail(ops))

-----------------------------------------------------------------------------
EmptyConf == [i \in Ids |-> None]
InitRec == [nextNo |-> 1, outbox |-> <<>>, conf |-> EmptyConf, lastSeq |-> 0]

Init ==
  /\ rows = [i \in Ids |-> None] /\ srvSeq = 0 /\ applied = {}
  /\ open = [t \in Tabs |-> t = 1]
  /\ closed = [t \in Tabs |-> FALSE]
  /\ cid = [t \in Tabs |-> "c1"]
  /\ nextNo = [t \in Tabs |-> 1]
  /\ outbox = [t \in Tabs |-> <<>>]
  /\ conf = [t \in Tabs |-> EmptyConf]
  /\ lastSeq = [t \in Tabs |-> 0]
  /\ pushing = [t \in Tabs |-> 0]
  /\ pushN = [t \in Tabs |-> 0]
  /\ pullSt = [t \in Tabs |-> Idle]
  /\ store = [c \in Cids |-> InitRec]   \* キーが無いときの loadState は initialState と同じ
  /\ reqs = {} /\ resps = {}
  /\ usedIds = {} /\ made = {} /\ acked = {}
  /\ lastExec = [c \in Cids |-> 0] /\ orderOk = TRUE

ServerUnchanged == UNCHANGED <<rows, srvSeq, applied, lastExec, orderOk>>

\* src/app.ts の setState: 状態を置き換えるたびに localStorage[todo-state:<clientId>] に保存する。
\* 各アクションの最後の連言に置く（ここで読む次の状態の値は、それより前の連言で決まっている）
Save(t) ==
  store' = [store EXCEPT ![cid[t]] =
              [nextNo |-> nextNo'[t], outbox |-> outbox'[t], conf |-> conf'[t], lastSeq |-> lastSeq'[t]]]

-----------------------------------------------------------------------------
(* src/app.ts: act -> src/sync.ts: enqueue -> setState（保存して描画）。     *)
(* 同期的に終わるので 1 ステップ。画面の操作の条件は app.ts の render と     *)
(* new-form の submit から。                                                *)
Enqueue(t, kind, id, title, done) ==
  LET op == MkOp(cid[t], nextNo[t], kind, id, title, done) IN
  /\ outbox' = [outbox EXCEPT ![t] = Append(@, op)]
  /\ nextNo' = [nextNo EXCEPT ![t] = @ + 1]
  /\ made' = made \cup {op}

CanAct(t) == open[t] /\ nextNo[t] <= MaxOpNo

YouCreate(t) ==
  /\ CanAct(t)
  /\ \E i \in Ids \ usedIds :
       /\ i = CHOOSE j \in Ids \ usedIds : TRUE
       /\ Enqueue(t, "create", i, CHOOSE x \in Titles : TRUE, FALSE)
       /\ usedIds' = usedIds \cup {i}
  /\ UNCHANGED <<rows, srvSeq, applied, open, closed, cid, conf, lastSeq, pushing, pushN, pullSt,
                 reqs, resps, acked, lastExec, orderOk>>
  /\ Save(t)

Visible(t, i) == LET v == ViewTodos(t)[i] IN v.ex /\ ~v.deleted

\* 画面の操作の条件。render は編集欄にフォーカスがある間（editingId）は一覧を描き直さずに
\* return する（app.ts の render の先頭）。だからイベントのクロージャの t・cb.checked・t.id は
\* 古い描画のままのことがあり、今の表示と同じ名前への rename、今と同じ値の setDone、
\* pull で墓標になった todo への操作も積まれうる。StaleUI = TRUE はその上位集合
\* （作ったことのある id なら何にでも・どの名前にでも・どちらの値にでも）を許す。
CanTouch(t, i) == IF StaleUI THEN i \in usedIds ELSE Visible(t, i)

\* render の finish: 名前が（描画したときの）表示と違うときだけ rename を積む
YouRename(t) ==
  /\ CanAct(t)
  /\ \E i \in Ids, ttl \in Titles :
       /\ CanTouch(t, i) /\ (StaleUI \/ ttl # ViewTodos(t)[i].title)
       /\ Enqueue(t, "rename", i, ttl, FALSE)
  /\ UNCHANGED <<rows, srvSeq, applied, open, closed, cid, conf, lastSeq, pushing, pushN, pullSt,
                 reqs, resps, usedIds, acked, lastExec, orderOk>>
  /\ Save(t)

\* チェックボックスの change: （描画したときの）表示の反対の値
YouToggle(t) ==
  /\ CanAct(t)
  /\ \E i \in Ids, d \in BOOLEAN :
       /\ CanTouch(t, i) /\ (StaleUI \/ d = ~ViewTodos(t)[i].done)
       /\ Enqueue(t, "setDone", i, "", d)
  /\ UNCHANGED <<rows, srvSeq, applied, open, closed, cid, conf, lastSeq, pushing, pushN, pullSt,
                 reqs, resps, usedIds, acked, lastExec, orderOk>>
  /\ Save(t)

YouDelete(t) ==
  /\ CanAct(t)
  /\ \E i \in Ids :
       /\ CanTouch(t, i)
       /\ Enqueue(t, "delete", i, "", FALSE)
  /\ UNCHANGED <<rows, srvSeq, applied, open, closed, cid, conf, lastSeq, pushing, pushN, pullSt,
                 reqs, resps, usedIds, acked, lastExec, orderOk>>
  /\ Save(t)

-----------------------------------------------------------------------------
(* タブ 2 を開く。src/app.ts の loadClientId と loadState（起動時に1回）。 *)
\* 新しいタブで URL を開く: sessionStorage は空なので新しい ID、状態は initialState
OpenNewTab ==
  /\ SecondTab = "new" /\ ~open[2] /\ ~closed[2]
  /\ open' = [open EXCEPT ![2] = TRUE]
  /\ cid' = [cid EXCEPT ![2] = "c2"]
  /\ UNCHANGED <<rows, srvSeq, applied, closed, nextNo, outbox, conf, lastSeq, pushing, pushN, pullSt,
                 store, reqs, resps, usedIds, made, acked, lastExec, orderOk>>

\* タブを複製する: sessionStorage が写るので同じ ID。状態は localStorage の todo-state:<ID>
\* （タブ 1 が setState のたびに保存したもの）から読む
DuplicateTab ==
  /\ SecondTab = "duplicate" /\ ~open[2] /\ ~closed[2] /\ open[1]
  /\ open' = [open EXCEPT ![2] = TRUE]
  /\ cid' = [cid EXCEPT ![2] = cid[1]]
  /\ nextNo' = [nextNo EXCEPT ![2] = store[cid[1]].nextNo]
  /\ outbox' = [outbox EXCEPT ![2] = store[cid[1]].outbox]
  /\ conf' = [conf EXCEPT ![2] = store[cid[1]].conf]
  /\ lastSeq' = [lastSeq EXCEPT ![2] = store[cid[1]].lastSeq]
  /\ UNCHANGED <<rows, srvSeq, applied, closed, pushing, pushN, pullSt,
                 store, reqs, resps, usedIds, made, acked, lastExec, orderOk>>

\* リロード: メモリ上の pushing・pulling・届く途中の応答は消え、sessionStorage の ID は残り、
\* loadState が localStorage[todo-state:<ID>] を読み直す。サーバに向かっている要求は届くかもしれない
\* （届いても応答を読むページはもう無い）。複製したタブでは、そのキーに最後に保存したのが
\* もう一方のタブかもしれない
Reload(t) ==
  /\ CanReload /\ open[t]
  /\ nextNo' = [nextNo EXCEPT ![t] = store[cid[t]].nextNo]
  /\ outbox' = [outbox EXCEPT ![t] = store[cid[t]].outbox]
  /\ conf' = [conf EXCEPT ![t] = store[cid[t]].conf]
  /\ lastSeq' = [lastSeq EXCEPT ![t] = store[cid[t]].lastSeq]
  /\ pushing' = [pushing EXCEPT ![t] = 0]
  /\ pullSt' = [pullSt EXCEPT ![t] = Idle]
  /\ resps' = {x \in resps : x.tab # t}
  /\ ServerUnchanged
  /\ UNCHANGED <<open, closed, cid, pushN, store, reqs, usedIds, made, acked>>

\* タブを閉じる。localStorage[todo-state:<ID>] は残るが、そのタブの sessionStorage と一緒に
\* ID は失われ、このあと開くタブ（新しい URL）は新しい ID を作るので、そのキーを誰も読まない
CloseTab(t) ==
  /\ CanClose /\ open[t]
  /\ open' = [open EXCEPT ![t] = FALSE]
  /\ closed' = [closed EXCEPT ![t] = TRUE]
  /\ pushing' = [pushing EXCEPT ![t] = 0]
  /\ pullSt' = [pullSt EXCEPT ![t] = Idle]
  /\ resps' = {x \in resps : x.tab # t}
  /\ ServerUnchanged
  /\ UNCHANGED <<cid, nextNo, outbox, conf, lastSeq, pushN, store, reqs, usedIds, made, acked>>

-----------------------------------------------------------------------------
(* push。src/app.ts の push と src/sync.ts の nextBatch / applyPushResult *)

\* push() の await の前まで: pushing でなく outbox が空でなければ先頭から送る
PushStart(t) ==
  /\ open[t] /\ pushing[t] = 0 /\ outbox[t] # <<>> /\ pushN[1] + pushN[2] < MaxPush
  /\ LET n == pushN[t] + 1 IN
       /\ reqs' = reqs \cup {[tab |-> t, n |-> n, ops |-> SubSeq(outbox[t], 1, Min(50, Len(outbox[t])))]}
       /\ pushing' = [pushing EXCEPT ![t] = n]
       /\ pushN' = [pushN EXCEPT ![t] = n]
  /\ ServerUnchanged
  /\ UNCHANGED <<open, closed, cid, nextNo, outbox, conf, lastSeq, pullSt, store, resps, usedIds, made, acked>>

\* 要求がサーバに届かない（送る前の失敗）
RequestLost ==
  /\ \E r \in reqs : reqs' = reqs \ {r}
  /\ ServerUnchanged
  /\ UNCHANGED <<open, closed, cid, nextNo, outbox, conf, lastSeq, pushing, pushN, pullSt, store, resps,
                 usedIds, made, acked>>

\* src/api.ts handlePush -> TodoStore.push（1 トランザクション）。
\* タイムアウトで諦めた要求でも、サーバに届けば反映される。応答はもう誰も読まない。
ServerPush ==
  /\ \E r \in reqs :
       LET st == ApplyAll([rows |-> rows, seq |-> srvSeq, applied |-> applied,
                           last |-> lastExec, ok |-> orderOk, results |-> <<>>], r.ops) IN
       /\ reqs' = reqs \ {r}
       /\ rows' = st.rows /\ srvSeq' = st.seq /\ applied' = st.applied
       /\ lastExec' = st.last /\ orderOk' = st.ok
       /\ resps' = IF pushing[r.tab] = r.n
                   THEN resps \cup {[tab |-> r.tab, n |-> r.n, results |-> st.results]}
                   ELSE resps
  /\ UNCHANGED <<open, closed, cid, nextNo, outbox, conf, lastSeq, pushing, pushN, pullSt, store,
                 usedIds, made, acked>>

\* 応答が消える場合は PushGivesUp に含めた（応答が消えたあとクライアントにできるのは
\* タイムアウトで諦めることだけで、PushGivesUp はその応答も捨てる）

\* await の後: setState(applyPushResult(state, res.results))。返ってきた opId を outbox から外す
PushOk ==
  /\ \E x \in resps :
       /\ pushing[x.tab] = x.n
       /\ LET t == x.tab
              ackedOps == {op \in Range(outbox[t]) : \E k \in DOMAIN x.results : SameOpId(x.results[k].op, op)}
              rs == {x.results[k].todo : k \in {k2 \in DOMAIN x.results : x.results[k2].todo.version # 0}}
          IN /\ outbox' = [outbox EXCEPT ![t] = SelectSeq(@, LAMBDA op : op \notin ackedOps)]
             /\ conf' = [conf EXCEPT ![t] = MergeRows(@, rs)]
             /\ acked' = acked \cup ackedOps
             /\ pushing' = [pushing EXCEPT ![t] = 0]
             /\ resps' = resps \ {x}
             /\ ServerUnchanged
             /\ UNCHANGED <<open, closed, cid, nextNo, lastSeq, pushN, pullSt, reqs, usedIds, made>>
             /\ Save(t)

\* catch: 失敗・タイムアウト（AbortSignal.timeout）・応答の消失。区別せず諦めて、あとで同じ op を再送
\* fetch を中断したので、この要求の応答はもう届かない。catch は render だけで setState しない
PushGivesUp(t) ==
  /\ pushing[t] # 0
  /\ pushing' = [pushing EXCEPT ![t] = 0]
  /\ resps' = {x \in resps : ~(x.tab = t /\ x.n = pushing[t])}
  /\ ServerUnchanged
  /\ UNCHANGED <<open, closed, cid, nextNo, outbox, conf, lastSeq, pushN, pullSt, store, reqs,
                 usedIds, made, acked>>

-----------------------------------------------------------------------------
(* pull。src/app.ts の pull、src/api.ts handlePull、TodoStore.pull、src/sync.ts applyPull *)
(* 要求の送信とサーバでの読み出しを 1 ステップにした（送ってから読まれるまでの間に       *)
(* クライアントが変えるのは pulling だけで、それは読む値に影響しない）。                 *)
(* ページ送り（TodoStore.pull の limit = 500 に達したとき）はモデルに無い。コードには    *)
(* あるが、この範囲（todo は高々 2 件）では起きないので、正しさは調べていない。         *)
PullRead(t) ==
  /\ open[t] /\ pullSt[t] = Idle
  /\ pullSt' = [pullSt EXCEPT ![t] =
        [busy |-> TRUE,
         changes |-> {rows[i] : i \in {j \in Ids : rows[j].version # 0 /\ rows[j].seq > lastSeq[t]}},
         seq |-> Max(srvSeq, lastSeq[t])]]
  /\ ServerUnchanged
  /\ UNCHANGED <<open, closed, cid, nextNo, outbox, conf, lastSeq, pushing, pushN, store, reqs, resps,
                 usedIds, made, acked>>

PullOk(t) ==
  /\ pullSt[t] # Idle
  /\ conf' = [conf EXCEPT ![t] = MergeRows(@, pullSt[t].changes)]
  /\ lastSeq' = [lastSeq EXCEPT ![t] = Max(@, pullSt[t].seq)]
  /\ pullSt' = [pullSt EXCEPT ![t] = Idle]
  /\ ServerUnchanged
  /\ UNCHANGED <<open, closed, cid, nextNo, outbox, pushing, pushN, reqs, resps, usedIds, made, acked>>
  /\ Save(t)

\* pull の失敗（catch で lastError を出すだけ）は入れていない。PullRead で変わるのは
\* pullSt だけなので、失敗して Idle に戻った状態は「まだ pull していない」状態と同じになる

-----------------------------------------------------------------------------
Next ==
  \/ \E t \in Tabs : YouCreate(t) \/ YouRename(t) \/ YouToggle(t) \/ YouDelete(t)
  \/ OpenNewTab \/ DuplicateTab
  \/ \E t \in Tabs : Reload(t) \/ CloseTab(t)
  \/ \E t \in Tabs : PushStart(t) \/ PushGivesUp(t)
  \/ RequestLost \/ ServerPush \/ PushOk
  \/ \E t \in Tabs : PullRead(t) \/ PullOk(t)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* 性質 *)

\* 1. 確認が来たとして送信待ちから外した操作は、その操作としてサーバに反映されている
\*    （別の操作と取り違えて「もう反映済み」と捨てられていない）
AckedMeansApplied == \A o \in acked : o \in applied

\* 2. 同じクライアントの操作は、サーバで操作した順に 1 回ずつ反映される
\*    （再送が二重に反映されたり、古い再送が新しい値を巻き戻したりしない）
ClientOrderKept == orderOk

\* 3. 送信待ちも届く途中の要求も無く、全タブが最後まで pull したら、全タブの一覧がサーバと同じ
Settled ==
  /\ reqs = {} /\ resps = {}
  /\ \A t \in Tabs : open[t] =>
       (outbox[t] = <<>> /\ pushing[t] = 0 /\ pullSt[t] = Idle /\ lastSeq[t] = srvSeq)
Converged == Settled => \A t \in Tabs : open[t] => View(t) = ServerView

\* 4. ユーザーが積んだ操作は、サーバに反映済みか、開いているタブの送信待ちにあるか、
\*    サーバに向かう途中の要求に入っている（どこからも送られなくなって消えていない）
NoOpLost ==
  \A o \in made :
     \/ o \in applied
     \/ \E t \in Tabs : open[t] /\ o \in Range(outbox[t])
     \/ \E r \in reqs : o \in Range(r.ops)

=============================================================================
