#!/usr/bin/env bash
# PostgreSQL を Docker で立て、Alice と Bob のトークンを出して、サーバを起動する。
# 使い方: ./run.sh   （止めるときは Ctrl-C。DB は `docker rm -f h5i-todo-pg` で消える）
set -euo pipefail
cd "$(dirname "$0")"
export PATH=/opt/homebrew/opt/rustup/bin:$PATH
PORT=${PORT:-8787}
if ! docker ps --format '{{.Names}}' | grep -qx h5i-todo-pg; then
  docker rm -f h5i-todo-pg >/dev/null 2>&1 || true
  docker run -d --name h5i-todo-pg -p 127.0.0.1:55433:5432 -e POSTGRES_USER=h5i -e POSTGRES_PASSWORD=h5i postgres:17 >/dev/null
  until docker exec h5i-todo-pg pg_isready -U h5i >/dev/null 2>&1; do sleep 1; done
fi
export DATABASE_URL=postgres://h5i:h5i@127.0.0.1:55433/h5i
export H5I_APP_SECRET=${H5I_APP_SECRET:-dev-secret-change-me}
cargo build -q -p todo-server
ALICE=$(H5I_APP_ISSUE=1:1 ./target/debug/todo-server)   # org 1, user 1
BOB=$(H5I_APP_ISSUE=1:2 ./target/debug/todo-server)     # org 1, user 2
echo "open: http://127.0.0.1:$PORT/#alice=$ALICE&bob=$BOB"
LISTEN=127.0.0.1:$PORT exec ./target/debug/todo-server
