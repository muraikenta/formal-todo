# ソート（性質で書いた仕様 → Rust 実装 → 証明）

「仕様は性質として書く」を、ソートで試したもの（2026-11-27）。全体: [README](../README.md)

## 流れ

| 段 | ファイル | 中身 |
|---|---|---|
| 1. 仕様（人が先に書く） | [lean/Spec.lean](lean/Spec.lean) | 「並んでいる」と「入力の並べ替え」の2つだけ。アルゴリズムは書かない |
| 2. 実装 | [kernel/src/lib.rs](kernel/src/lib.rs) | 挿入ソート（`&mut [u32]` をその場で、`v.swap(j - 1, j)` で沈める） |
| 2'. 自動翻訳 | [lean/SortKernel.lean](lean/SortKernel.lean) | Charon → Aeneas が作る（手で書いていない）。ループは `loop`、添字の範囲外や `j - 1` の桁あふれは失敗になる |
| 3. 証明 | [lean/Proofs.lean](lean/Proofs.lean) | 主定理 `insertion_sort_correct` |

## 仕様（性質で書く）

```lean
def Sorted (l : List Nat) : Prop := l.Pairwise (· ≤ ·)
def IsSortOf (input output : List Nat) : Prop := Sorted output ∧ output.Perm input
```

- 小さい例で仕様そのものを確かめる（`decide`）: `[3,1,2]` → `[1,2,3]` は満たす／並んでいない・1つ消えた・すり替わった出力は満たさない
- 「並んでいる」だけだと弱いことも例で示す: 全部 0 にした `[0,0,0]` は並んでいるが、並べ替えではない
- **仕様が十分に強いことの証明** `sortOf_unique`: 2つの性質を満たす出力はただ1つ。つまり、この仕様を満たす実装はどれも同じ結果を返し、「おかしな実装」が入り込む余地が無い。性質で書いた仕様の弱点（書き忘れた性質は守られない）を、定理1本でふさいでいる
- さらに `isSortOf_iff_mergeSort`: そのただ1つの答えは、標準ライブラリの `mergeSort` の結果そのもの

## 主定理

```lean
theorem insertion_sort_correct (v : Slice U32) :
    insertion_sort v ⦃ v' => Spec.IsSortOf (nat v) (nat v') ⦄
```

前提なし。どんな長さ・どんな値の入力でも、止まり（無限ループせず）、panic せず、結果は入力をソートしたもの。`nat` は u32 の列を自然数の列に読み替える関数。sorry 0、使っている公理は Lean 標準の3つ（`propext`・`Classical.choice`・`Quot.sound`）。

- 言い換え `insertion_sort_eq_mergeSort`: 結果は入力を `mergeSort` で並べたものと等しい
- `out_unique`: 読み替え `nat` は情報を落とさない（仕様を満たす u32 の列はただ1つ）

### 証明の組み立て（ループ不変条件）

- 内側のループ（`insert`: v[i] を左へ沈める）: 列はいつも `pre ++ x :: post ++ rest` の形。`x` を抜いた `pre ++ post` は並んでいて、`x` は `post` のどれ以下。`x` の左が `x` 以下になったところで止まれば、`pre ++ x :: post` が並ぶ（`sorted_insert_mid`）
- `v.swap(j - 1, j)` は、列の上では「`a, x` を `x, a` にするだけ」（`swap_adj`）。並べ替えであることは隣どうしの入れ替え（`List.Perm.swap`）から
- 外側のループ: 「先頭 i 個が並んでいて、全体は元の並べ替え」。i = n で抜けたら全体が並ぶ
- 停止: 内側は j が減る、外側は n + 1 − i が減る（Aeneas の `loop.spec_decr_nat`）

## わざと壊して確かめる（[mutate.sh](mutate.sh)）

| 壊し方 | cargo test | 証明 |
|---|---|---|
| 等しいときも入れ替える（`>` → `>=`。正しいまま） | 通る | 通る |
| 先頭の位置まで沈めない（`j > 0` → `j > 1`） | 落ちる | 止まる |
| 大きい順に並べる（`>` → `<`） | 落ちる | 止まる |
| 2番目から始める（`i = 1` → `i = 2`） | 落ちる | 止まる |
| 最後の1つを差し込まない（`i < n` → `i + 1 < n`） | 落ちる | 止まる |
| 入れ替えずに左の値を写す（値が消える） | 落ちる | 止まる |
| 7個目から先は並べない | **通る（見逃す）** | 止まる |
| 12345 だけは動かさない | **通る（見逃す）** | 止まる |

- テストは例を6つしか見ないので、長い入力や特定の値でだけ起きるバグを見逃す。証明は全入力について言うので止まる
- `>=` への変更は正しいソートのままで、証明もそのまま通る。最初の証明は `>` に寄せて「x < y」と書いていたので止まった。「x ≤ y」に直すと通った。**証明が止まることはバグがあることの証明ではない**（証明が実装の書き方に寄りすぎていることもある）

## 別の目で穴を探させた結果（3観点 × 反証、2026-11-27）

仕様の十分さ・主定理の文面と隠れた仮定・証明していない層の3つで探させ、所見ごとに別のエージェントに反証させた。**穴は0件**、注意書きが7件。

- 確かめられたこと: `⦃⦄` は「止まる・panic しない」まで含む（Aeneas の `WP.spec` は全正当性。部分正当性の `⦃⦄div` とは別）／主定理に隠れた前提は無い／翻訳は今の `lib.rs` から作り直しても1バイトも変わらない／`Vec<u32>` や配列から呼ぶ側でもそのまま使える
- 直したこと: 「人がレビューするのは Spec.lean だけ」は言い過ぎ（主定理の文と `nat` も読む必要がある。引数を逆にすると別の主張）→ 書き直した／一意性が自然数の列についてだけだった → `out_unique` を足した／前提付きの `insert` が `pub` だった → 外に出さないようにした
- 証明していない層（信頼している部分）:
  - Charon が読む rustc（nightly）と、実際にビルドする rustc（stable）が違う。その先の LLVM のコード生成も証明の外
  - Charon/Aeneas の翻訳器。`&mut [u32]` は「新しい Slice を返す」関数として表される
  - Aeneas が手で書いた標準ライブラリのモデル（`swap`・添字など）
  - Lean のカーネル

## 動かし方

```bash
cd sort-aeneas && ./build.sh
```

```bash
cd sort-aeneas && ./mutate.sh
```

- `build.sh`: cargo test → Charon → Aeneas → `lake build`。初回の `lake build` は Mathlib の準備込みで約3分
- 道具の入れ方は [README](../README.md) の「Aeneas の導入メモ」
