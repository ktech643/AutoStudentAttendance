#!/usr/bin/env bash
# Web dev: API on same machine (browser → localhost:8000).
set -euo pipefail
cd "$(dirname "$0")/.."
API="${FLUTTER_API_BASE_URL:-http://127.0.0.1:8000}"
exec flutter run -d chrome --web-port="${WEB_PORT:-0}" \
  --dart-define=FLUTTER_API_BASE_URL="$API" \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION=true \
  --dart-define=FLUTTER_ADMIN_EMAIL="${FLUTTER_ADMIN_EMAIL:-admin@school.com}" \
  --dart-define=FLUTTER_ADMIN_PASSWORD="${FLUTTER_ADMIN_PASSWORD:-changeMe123}"
