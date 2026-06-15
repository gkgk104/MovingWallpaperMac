#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/marketplace-server"

mkdir -p data
PID_PATH="$PWD/data/server.pid"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -f "$PID_PATH"
}

trap cleanup EXIT INT TERM

node server.js &
SERVER_PID="$!"
echo "$SERVER_PID" > "$PID_PATH"
wait "$SERVER_PID"
