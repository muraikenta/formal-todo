// /statechart の view: モデルの状態を画面とサーバの言葉で表す。
const KIND = { create: "追加", rename: "名前", setDone: "完了", delete: "削除" };
const ids = (fn) => Object.keys(fn ?? {}).sort();

const tab = (v, t) => {
  if (v.closed?.[t]) return "閉じた";
  if (!v.open[t]) return "まだ開いていない";
  const ops = Object.values(v.outbox[t] ?? {});
  const n = ops.length;
  // 送信待ちの中身（どのタブの操作が残っているか・消えたかを経路で追えるように）
  const kinds = ops.map((o) => `${o.no}:${KIND[o.kind] ?? o.kind}`).join("・");
  const sending = v.pushing[t] !== 0 ? "・送信中" : "";
  // lastSeq は「サーバの変更をどこまで取り込んだか」。todo をまたぐ取りこぼしの経路を追うために出す
  return `ID ${v.cid[t]}・${n ? `送信待ち ${n} 件（${kinds}）` : "送信待ちなし"}${sending}・取り込み済み seq ${v.lastSeq[t]}`;
};

// todo が何件でも、全部の行を出す（2 件目以降が見えないと、todo をまたぐ経路を追えない）
const server = (v) => {
  const shown = ids(v.rows)
    .map((i) => [i, v.rows[i]])
    .filter(([, r]) => r.version !== 0)
    .map(([i, r]) => `todo${i}「${r.title}」${r.done ? "完了" : "未完了"}${r.deleted ? "・削除済み" : ""}（seq ${r.seq}）`);
  return shown.length ? shown.join("、") : "todo なし";
};

export const state = (v) => ({ タブ1: tab(v, 1), タブ2: tab(v, 2), サーバ: server(v) });

// どのタブの出来事かは、前後でタブ 1 の値が変わったかで決める（変わっていなければタブ 2）
const PER_TAB = ["open", "closed", "nextNo", "outbox", "conf", "lastSeq", "pushing", "pushN", "pullSt"];
const whichTab = (from, to) =>
  PER_TAB.some((k) => JSON.stringify(from[k]?.[1]) !== JSON.stringify(to[k]?.[1])) ? 1 : 2;

const LABEL = {
  YouCreate: (t) => `タブ${t}で todo を追加する`,
  YouRename: (t) => `タブ${t}で名前を変える`,
  YouToggle: (t) => `タブ${t}で完了を切り替える`,
  YouDelete: (t) => `タブ${t}で削除する`,
  Reload: (t) => `タブ${t}をリロードする`,
  CloseTab: (t) => `タブ${t}を閉じる`,
  PushStart: (t) => `タブ${t}が送信待ちを送る`,
  PushGivesUp: (t) => `タブ${t}の送信が失敗・タイムアウトする`,
  PushOk: (t) => `タブ${t}に送信の応答が届く`,
  PullRead: (t) => `タブ${t}が差分を問い合わせる`,
  PullOk: (t) => `タブ${t}に差分が届く`,
};

export const step = (action, from, to) => {
  if (action === "OpenNewTab") return "別のタブで同じ URL を開く";
  if (action === "DuplicateTab") return "タブを複製する";
  if (action === "ServerPush") return "サーバが届いた要求を反映する";
  if (action === "RequestLost") return "要求がサーバに届かない";
  const f = LABEL[action];
  return f ? f(whichTab(from, to)) : action;
};

export const title = "Sync Todo: 2 つのタブとサーバ";
