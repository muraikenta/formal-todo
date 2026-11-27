#!/bin/bash
# 全部まとめて確かめる（約3分）。どれか1つでも落ちたら止まる。
set -euo pipefail
cd "$(dirname "$0")"
echo "== quint test（具体例4本）";            quint test todo.qnt --main=todo4 | tail -1
echo "== quint run（todo7・ランダム1万本）";   quint run todo.qnt --main=todo7 --invariant=safety --max-steps=30 --max-samples=10000 | grep -E "ok\]|violation"
echo "== TLC（todo4・全状態）";               quint verify todo.qnt --main=todo4 --backend=tlc --invariant=safety | grep -E "distinct states found|ok\]|violation"
echo "== バグ版は違反が出ること";
if quint run todo.qnt --main=todo4_idFromLength --invariant=safety --max-steps=30 >/dev/null 2>&1; then echo "バグ版が通った（検査が効いていない）"; exit 1; else echo "違反を検出"; fi
echo "== 仕様の変異テスト";                    node mutate-spec.mjs | tail -1
echo "== トレース生成 → MBT";                 ./gen-traces.sh; node mbt.mjs
echo "== アプリの変異テスト";                  node mutate.mjs | tail -1
