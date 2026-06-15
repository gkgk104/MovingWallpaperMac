#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_PATH="$ROOT_DIR/marketplace-server/data/server.pid"
PORT="${PORT:-8787}"

if [[ -f "$PID_PATH" ]] && kill -0 "$(cat "$PID_PATH")" >/dev/null 2>&1; then
  kill "$(cat "$PID_PATH")"
  rm -f "$PID_PATH"
  echo "Marketplace server stopped."
elif command -v lsof >/dev/null 2>&1 && lsof -ti "tcp:$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  lsof -ti "tcp:$PORT" -sTCP:LISTEN | xargs kill
  rm -f "$PID_PATH"
  echo "Marketplace server stopped on port $PORT."
else
  rm -f "$PID_PATH"
  echo "Marketplace server is not running."
fi
