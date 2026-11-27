# formal-todo

Rust で書いた todo アプリを Lean で証明した記録と、同じ todo をほかの形式検証の道具（Quint・h5i・Nyxis・TLA+）で検証した記録です。初心者向けの解説 book と、そのコードの元になったアプリが入っています。

- 解説 book「形式検証入門ブック」: [book/book.html](book/book.html)（ブラウザで開くと章ごとに読めます）
- 調べた時期: 2026 年 11 月。道具の版は各フォルダの README と `lean-toolchain` にあります

## book の章とフォルダ

本編は Rust と Lean（Aeneas）だけで読めます。ほかの道具は付録にまとめました。

| 章 | 内容 | フォルダ |
|---|---|---|
| 第0章 | はじめに（仕様・実装・証明、テストとの違い。例はソート） | [sort-aeneas](sort-aeneas/README.md) |
| 第1章 | Lean と Rust で todo が仕様どおりと証明する（Aeneas） | [todo-aeneas](todo-aeneas/README.md) |
| 第2章 | 認可を証明する（他人の todo には触れない） | [todo-aeneas](todo-aeneas/README.md) |
| 第3章 | まとめ | — |
| 付録A | Quint で仕様を全部の状態について調べる（TLC・変異テスト・MBT） | [quint-todo](quint-todo/README.md) |
| 付録B | h5i と Nyxis：web アプリの枠組みごと認可を証明する | [h5i-todo](h5i-todo/README.md) ・ [nyxis-todo](nyxis-todo/README.md) |
| 付録C | TLA+ と TLC で同期を検査する（複数タブで操作が消える 3 つの不具合） | [todo](todo/README.md) ・ [todo/verification](todo/verification/README.md) |
| 付録D | Lean と Rust は相性がよく、JavaScript とは相性が悪い | [todo-aeneas](todo-aeneas/README.md) ・ [quint-todo](quint-todo/README.md) ・ [todo](todo/README.md) |
| 付録E | Lean で Web サーバーも作れる（Nyxis の仕組み） | [nyxis-todo](nyxis-todo/README.md) |
| 付録F | Lean の基本文法 | — |

## その他のフォルダ

| フォルダ | 中身 |
|---|---|
| [lean](lean/Jiyuu.lean) | Lean 4 の入門。自然数をゼロから定義し、足し算・掛け算の法則とリストを 2 回反転すると元に戻ることを証明 |
| [quint](quint/sumTo.qnt) | `sum_to` を Quint でモデル化。範囲（`MAX`）の選び方で境界のバグを見逃す例（`MAX=255` では見逃し、`253` で見つかる） |
| [lean-aeneas](lean-aeneas/Spec.lean) ・ [rust](rust/src/lib.rs) | Rust の `sum_to`（0 + 1 + … + n）を Aeneas で Lean に翻訳し、ガウスの公式まで証明 |
| [cedar-style](cedar-style/model/Model.lean) | AWS Cedar と同じ形（Lean の実行できるモデル ＋ Rust 実装との差分テスト）。特定の 1 入力だけ壊れるバグは 100 万件 × 3 seed でも見逃し、証明では止まる |
| [事例調査.md](事例調査.md) | Rust の形式検証の最近の事例（SymCrypt・Cedar・Verus など） |

## Aeneas の導入メモ（macOS）

`lean-aeneas`・`todo-aeneas`・`sort-aeneas` は Aeneas の Lean ライブラリを `~/src/aeneas/backends/lean` から参照します。各 `lakefile.toml` の `path` は筆者の環境（作業フォルダから `~/src/aeneas` への相対パス）のままなので、clone した場所に合わせて自分の Aeneas の `backends/lean` に書き換えてください。

- `brew install rustup opam make pkgconf` のあと、Aeneas を `~/src/aeneas` に clone してビルドする
- macOS 標準の make は古いので、GNU make（`/opt/homebrew/opt/make/libexec/gnubin`）を PATH の先頭に置く
- `opam install ./src --deps-only` は `pkgconf` が無いと止まる。先に brew で入れる
- Aeneas の `make` が `ppx_deriving_hash` が無いと落ちたら `opam install ppx_deriving_hash`
- 初回の `lake build` は Mathlib のキャッシュ展開込みで 2 分ほど

流れ（`lean-aeneas` の例）:

```bash
cd rust && charon cargo --preset=aeneas
```

```bash
~/src/aeneas/bin/aeneas -backend lean rust/jiyuu.llbc -dest lean-aeneas
```

```bash
cd lean-aeneas && lake build
```

## 注意

- 証明・検査は「仕様に書いたこと」しか守りません。各 README に、証明していない層（保存・画面・HTTP など）と見逃しを書いています
- `todo/` の同期の不具合 3 つは、検証で見つけたまま直していません（再現手順は [todo/verification/README.md](todo/verification/README.md)）

## ライセンス

[MIT](LICENSE)
