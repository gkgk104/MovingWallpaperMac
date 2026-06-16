#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Starting MotionDock Marketplace."
echo "Keep this terminal open while using Marketplace. Press Control-C to stop."
exec "$ROOT_DIR/scripts/run-marketplace-server.sh"
