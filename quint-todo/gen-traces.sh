#!/bin/bash
# 正しい版の仕様（todo7: id 0〜6）からトレースを 200 本（各 30 歩）作る。seed 固定なので何度流しても同じトレースになる。
set -euo pipefail
cd "$(dirname "$0")"
rm -rf traces && mkdir traces
quint run todo.qnt --main=todo7 --mbt --invariant=safety \
  --max-steps=30 --n-traces=200 --max-samples=200 --seed=0x5eed \
  --out-itf='traces/t_{seq}.itf.json' >/dev/null
echo "traces: $(ls traces | wc -l | tr -d ' ') 本"
