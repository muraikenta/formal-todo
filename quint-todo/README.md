# Quint で Todo アプリ（第6章）

Todo アプリの決まりを Quint の仕様に書き、仕様の検査（ランダム実行・TLC の全網羅）と、仕様から作った実行列を本物のアプリに流す**モデルベーステスト（MBT）**までを通した。全体は [README](../README.md)。

## ファイル

- [todo.qnt](todo.qnt) … 仕様。状態（todos・nextId）と6つの操作（追加・切り替え・削除・編集・全部切り替え・完了済みを消す）。不変条件 `safety` = 形の性質＋前後の性質
- [app/todo-core.mjs](app/todo-core.mjs) … アプリの中身（状態遷移だけ）。画面と MBT の両方がこれを読む
- [app/index.html](app/index.html) … 画面（追加・ダブルクリックで編集・×で削除・全部切り替え・絞り込み・完了済みを消す・localStorage に保存）
- [mbt.mjs](mbt.mjs) … ITF トレースを中身に1歩ずつ流し、todos・nextId・残り件数を突き合わせる
- [mutate.mjs](mutate.mjs) … アプリをわざと壊した19版を MBT が全部拾えるか
- [mutate-spec.mjs](mutate-spec.mjs) … 仕様をわざと壊した20版を不変条件が全部拾えるか
- [gen-traces.sh](gen-traces.sh) … トレース200本を作る（seed 固定。`traces/` は git に入れない）
- [check.sh](check.sh) … 上を全部まとめて流す（約2分）

## 動かす

画面（Claude の desktop アプリでは `.claude/launch.json` の `quint-todo` で開ける）:

```bash
cd quint-todo/app && python3 -m http.server 8781
```

検査を全部:

```bash
quint-todo/check.sh
```

## 仕様が決めていること

- 追加: 前後の空白（全角を含む）を取って空なら弾く。id は nextId から振り、末尾に足す
- 編集: 空白を取って空になったら削除（TodoMVC と同じ）
- 全部切り替え: 全部完了なら全部未完了、1つでも未完了があれば全部完了
- 無い id への切り替え・削除・編集は何もしない
- 絞り込み・編集の取り消し（Escape）・タブ間の同期は仕様の外（画面の層。ブラウザで確かめた）
