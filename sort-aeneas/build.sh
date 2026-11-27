#!/bin/bash
# Rust の kernel を Lean に翻訳して、テスト・証明まで通す（Rust を直したら流し直す）
set -euo pipefail
cd "$(dirname "$0")"
export PATH=/opt/homebrew/opt/rustup/bin:$HOME/src/aeneas/charon/bin:$PATH
(cd kernel && cargo test -q && charon cargo --preset=aeneas)
~/src/aeneas/bin/aeneas -backend lean kernel/sort_kernel.llbc -dest lean > /dev/null
(cd lean && lake build)
