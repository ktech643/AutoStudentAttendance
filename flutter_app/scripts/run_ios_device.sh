#!/usr/bin/env bash
# Physical iPhone / iPad on Wi‑Fi or USB: API must be the Mac LAN IP + Docker port.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT_DIR="$(dirname "$0")"
MAC_IP="$(bash "${SCRIPT_DIR}/lib_mac_ip.sh")"
API="${FLUTTER_API_BASE_URL:-http://${MAC_IP}:8008}"
echo "Using FLUTTER_API_BASE_URL=${API}"
DEVICE="${FLUTTER_IOS_DEVICE_ID:-}"
if [[ -z "${DEVICE}" ]]; then
  DEVICE="$(flutter devices --machine 2>/dev/null | python3 -c "
import json, sys
try:
    for d in json.load(sys.stdin):
        if d.get('targetPlatform') == 'ios' and 'simulator' not in (d.get('name') or '').lower():
            print(d.get('id') or '')
            break
except Exception:
    pass
")"
fi
if [[ -z "${DEVICE}" ]]; then
  echo "No physical iOS device found. Connect iPhone or set FLUTTER_IOS_DEVICE_ID." >&2
  exit 1
fi
echo "Device: ${DEVICE}"
exec flutter run -d "${DEVICE}" \
  --dart-define=FLUTTER_API_BASE_URL="$API" \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION="${FLUTTER_SIMULATED_RECOGNITION:-false}" \
  --dart-define=FLUTTER_ADMIN_EMAIL="${FLUTTER_ADMIN_EMAIL:-admin@school.com}" \
  --dart-define=FLUTTER_ADMIN_PASSWORD="${FLUTTER_ADMIN_PASSWORD:-changeMe123}"
