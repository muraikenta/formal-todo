# todo アプリ（Rust で書き、Lean で正しさを証明する）

[lean-aeneas](../lean-aeneas/Spec.lean) の sum_to でやった「仕様 → 実装 → 実装＝仕様 の証明」を、関数1本ではなく状態を持つ小さなアプリでやったもの（2026-11-27）。

## 構成

| 層 | ファイル | 証明 |
|---|---|---|
| 仕様（人が先に書く） | [lean/Spec.lean](lean/Spec.lean) | 仕様どうしの性質を証明 |
| 中核（状態の変え方と認可） | [kernel/src/lib.rs](kernel/src/lib.rs) → 自動翻訳 [lean/TodoKernel.lean](lean/TodoKernel.lean) | 実装＝仕様を証明 |
| 証明 | [lean/Proofs.lean](lean/Proofs.lean) | — |
| 画面と保存 | [cli/src/main.rs](cli/src/main.rs) | 証明しない（読み込み時に不変条件を検査） |

- 仕様: todo は「id・持ち主・題名・完了」のリスト＋次の id。どの操作も「誰が操作したか」を受け取る。操作は `add`（自分の todo を末尾に足す・id を使い切ったら none）／`toggle`（自分の todo の完了を反転）／`remove`（自分の todo を除く）／`openCount`（自分の未完了の件数）／`visible`（自分に見せてよい id）
- 不変条件 `Inv`: ①id が重複しない ②どの id も次の id より小さい ③次の id は u32 の上限以下。どの操作のあとも保たれることを仕様の上で証明（`inv_add` など）
- 仕様の性質: 足すと未完了が1件増える／2回切り替えると元に戻る／消したらその id はどこにも無い／ほかの todo は残る
- 実装＝仕様: Rust の状態を仕様の状態に読み替える `abs` を決め、「Rust で操作してから読み替え ＝ 読み替えてから仕様で操作」を全状態で証明（`add_correct`・`toggle_correct`・`remove_correct`・`open_count_correct`）
  - `add` が失敗しない（Vec の長さが上限を超えない）ことも `Inv` から導く（`length_le_nextId`: id が重複せずどれも next_id 未満なら、件数 ≤ next_id）
  - まとめとして「Rust の操作を何回続けても `Inv` は崩れない」（`add_preserves_inv` など3本）
  - `toggle` の Rust は「最初に見つかった1件だけ」反転し、仕様は「その id の全部」を反転する。一致するのは id が重複しないから → 証明は `Inv` を仮定する。CLI はファイルを読むときにこの前提を検査する

## 認可（2026-11-27 に追加）

自分が持ち主の todo にしか効かない・見えない。仕様の上で3つを証明し（[Spec.lean](lean/Spec.lean) の「認可」の節）、実装＝仕様の証明でそのまま Rust に持ち上げた（[Proofs.lean](lean/Proofs.lean) の「まとめ2」）。

1. **他人の todo は変わらない**: ユーザー A が足す・切り替える・消す、のどれをしても、B の持ち物は1件も変わらない（`add_others`・`toggle_others`・`remove_others`、Rust 版は `*_others_rust`）
2. **見えるのは自分の todo だけ**: 見せる id は、ちょうど「自分が持ち主の todo の id」（`visible_iff`、Rust 版は `visible_ids_only_own`）。CLI はこの一覧にある todo だけを表示する
3. **他人の id を指定しても何も起きない**: 失敗を返し、状態はそのまま（`toggle_foreign`・`remove_foreign`）。Rust の toggle は「id で探してから持ち主を確かめる」作りで、id が重複しないこと（不変条件）を使って仕様と一致させている

持ち主の確認をわざと外すと（Rust 側）:

| 壊し方 | 単体テスト | 証明 |
|---|---|---|
| remove が持ち主を確かめない | 通る | 止まる（remove_loop_spec） |
| remove でユーザー 0 だけは他人の todo も消せる（裏口） | 通る | 止まる（remove_loop_spec） |
| 一覧に id 1000 以上の他人の todo も混ざる | 通る | 止まる（visible_ids_loop_spec） |
| toggle が持ち主を確かめない | 落ちる | 止まる（toggle_correct） |

単体テストは「ボブがアリスの todo を切り替えられない」など思いついた場面しか見ないので、確かめ忘れた操作・特定のユーザー・特定の id だけの穴を素通りする。証明は全ユーザー・全 id・全状態で言う。

証明していないこと: 「いま誰か」が本当にその人か（本人確認）。CLI は `TODO_USER` を信じるだけ。web アプリにするなら、ログインの仕組みが渡すユーザーを kernel に渡す形になる。

## 動かし方

```bash
cd todo-aeneas && ./build.sh
```

```bash
cd todo-aeneas/cli && PATH=/opt/homebrew/opt/rustup/bin:$PATH TODO_USER=1 cargo run -q -- add 牛乳を買う
```

`build.sh` は Rust のテスト → Charon → Aeneas → `lake build` まで流す（Rust を直したら流し直す）。CLI は `TODO_USER=<ユーザー番号>` を付けて `add <題名>`／`list`／`toggle <id>`（完了⇔未完了）／`rm <id>`。保存先は `TODO_FILE`（無ければ `./todos.tsv`。認可を足す前の3列の形式は読めない）。

## わざと壊して確かめたこと（認可を足す前の版で確認）

| 壊し方（Rust） | 単体テスト | 証明 |
|---|---|---|
| toggle が反転でなく常に「完了」にする | 通る | 止まる（toggle_correct） |
| remove が id = 40億 のときだけ消さない | 通る | 止まる（remove_correct） |
| add が次の id を進めない | 落ちる | 止まる（add_correct） |
| 件数が完了済みも数える | 落ちる | 止まる（open_count_correct） |

仕様の `openCount` を「完了の件数」に書き間違えると、仕様の小さい例（`openCount s2 = 2`）と性質の証明で止まる。どれも戻して `./build.sh` が通る状態に戻した。

## 別の目で穴を探させた結果（2つの観点で6件、反証役を通しても全部本物。重複を除くと5件）

証明した中核には穴が無く、**穴はすべて「証明していない層」と「証明の仮定の出どころ」にあった**。

| 見つかった穴 | 直し方 |
|---|---|
| 題名に改行・タブを入れると保存ファイルが壊れ、消した todo が復活する（id が next_id 未満なので読み込み時の検査も通る） | 題名の改行・タブを拒否。保存する前に「読み戻すと同じ状態になるか」を確かめ、違えば保存しない |
| 読めないファイル（UTF-8 でない等）を空とみなし、`list` を1回打つだけで全件と next_id が消える | ファイルが無いときだけ空から始め、それ以外は止める |
| 完了の列が 0/1 以外でも黙って未完了と読む | 0/1 以外は止める |
| コマンド名が `done` なのに中身は切り替えで、2回打つと未完了に戻る（仕様どおりに証明されているので定理は何も言わない） | コマンド名を `toggle` に |
| `add_correct` の仮定（Vec の長さが上限未満）を誰が満たすのか示していない | 仮定を `Inv` に替え、そこから導いた |

- 発表で言えること: 証明は「仕様に書いたこと」しか守らない。名前と中身のずれ・保存の往復・外から来たデータは、仕様に書くか、境界で検査するかを決める必要がある
- 信頼の土台として確かめたこと: 翻訳結果に axiom 0 件。`#print axioms` は Lean 標準の3つ（propext・Classical.choice・Quot.sound）だけ。残る前提は「Aeneas の Vec のモデルが本物の Rust と同じ」こと（メモリ不足で落ちる場合は扱わない）と、`lake build` だけでは Rust と翻訳結果の対応を見ないので `build.sh` を流し直すこと

## 詰まったところ

- `std::mem::take` は Aeneas のライブラリに無く axiom（中身の無い宣言）になる → 証明できないので `std::mem::replace(&mut v, Vec::new())` に書き換えた。翻訳後に `grep axiom lean/TodoKernel.lean` で 0 件を確かめる
- `Vec` の `into_iter` は Aeneas 側に定義はあるが仕様の補題（`next` が何を返すか）が無い → `Proofs.lean` に自分で書いた（`into_iter_next_spec`）。`IntoIter` は中身が `Vec` の別名で、`simp` が型の食い違いで動かなくなるので、残りの中身を返す関数 `iv` をはさむ
- 証明の量（認可を足したあと）: 仕様 約250行、証明 約450行（Rust の中核は約120行、CLI 約130行）。ループのある関数は「ループ不変条件」を人が書く必要がある
