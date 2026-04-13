#!/usr/bin/env bash
# Physical iPhone: export FLUTTER_API_BASE_URL=http://<your-mac-lan-ip>:8000 (not 127.0.0.1).
set -euo pipefail
cd "$(dirname "$0")/.."
API="${FLUTTER_API_BASE_URL:-http://127.0.0.1:8000}"
exec flutter run -d ios \
  --dart-define=FLUTTER_API_BASE_URL="$API" \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION=true \
  --dart-define=FLUTTER_ADMIN_EMAIL="${FLUTTER_ADMIN_EMAIL:-admin@school.com}" \
  --dart-define=FLUTTER_ADMIN_PASSWORD="${FLUTTER_ADMIN_PASSWORD:-changeMe123}"
