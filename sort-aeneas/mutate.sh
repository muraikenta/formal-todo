#!/bin/bash
# Rust の実装をわざと壊して、テストと証明がそれぞれ気づくかを数える（終わると lib.rs と翻訳を元に戻す）
set -uo pipefail
cd "$(dirname "$0")"
export PATH=/opt/homebrew/opt/rustup/bin:$HOME/src/aeneas/charon/bin:$PATH
cp kernel/src/lib.rs /tmp/sort-lib.rs.orig
restore() { cp /tmp/sort-lib.rs.orig kernel/src/lib.rs; (cd kernel && charon cargo --preset=aeneas >/dev/null 2>&1); ~/src/aeneas/bin/aeneas -backend lean kernel/sort_kernel.llbc -dest lean >/dev/null 2>&1; }
trap restore EXIT
# 名前|置き換える前|置き換えた後
MUTANTS=(
  "等しいときも入れ替える（正しいまま）|v[j - 1] > v[j]|v[j - 1] >= v[j]"
  "先頭の位置まで沈めない|while j > 0 \&\&|while j > 1 \&\&"
  "大きい順に並べる|v[j - 1] > v[j]|v[j - 1] < v[j]"
  "2番目から始める|let mut i = 1;|let mut i = 2;"
  "最後の1つを差し込まない|while i < n|while i + 1 < n"
  "入れ替えずに左の値を写す（値が消える）|v.swap(j - 1, j);|v[j] = v[j - 1];"
  "7個目から先は並べない|while i < n|while i < n \\&\\& i < 6"
  "12345 だけは動かさない|while j > 0 \\&\\& v[j - 1] > v[j]|while j > 0 \\&\\& v[j - 1] > v[j] \\&\\& v[j] != 12345"
)
printf '| 壊し方 | cargo test | 証明 |\n|---|---|---|\n'
for m in "${MUTANTS[@]}"; do
  IFS='|' read -r name from to <<< "$m"
  cp /tmp/sort-lib.rs.orig kernel/src/lib.rs
  python3 -c "import sys;p='kernel/src/lib.rs';s=open(p).read();f=sys.argv[1].replace('\\\\&','&');t=sys.argv[2].replace('\\\\&','&');assert f in s, f;open(p,'w').write(s.replace(f,t,1))" "$from" "$to" || { echo "| $name | 置換失敗 | - |"; continue; }
  if (cd kernel && timeout 20 cargo test -q >/dev/null 2>&1); then t="通る"; else t="落ちる"; fi
  if (cd kernel && charon cargo --preset=aeneas >/dev/null 2>&1) && ~/src/aeneas/bin/aeneas -backend lean kernel/sort_kernel.llbc -dest lean >/dev/null 2>&1; then
    if (cd lean && lake build >/tmp/sort-mut.log 2>&1); then p="通る"; else p="止まる（$(grep -m1 -o 'Proofs.lean:[0-9]*' /tmp/sort-mut.log)）"; fi
  else p="翻訳失敗"; fi
  echo "| $name | $t | $p |"
done
