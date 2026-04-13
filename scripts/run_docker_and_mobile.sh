#!/usr/bin/env bash
# 1) Start Docker AttendX on :8008 (or reuse if already healthy)
# 2) Run Flutter on each connected physical iOS / Android device with
#    FLUTTER_API_BASE_URL=http://<mac-lan-ip>:8008
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/start_docker_backend.sh"

MAC_IP="$(bash "${ROOT}/flutter_app/scripts/lib_mac_ip.sh")"
export FLUTTER_API_BASE_URL="${FLUTTER_API_BASE_URL:-http://${MAC_IP}:8008}"
export FLUTTER_SIMULATED_RECOGNITION="${FLUTTER_SIMULATED_RECOGNITION:-false}"
export FLUTTER_ADMIN_EMAIL="${FLUTTER_ADMIN_EMAIL:-admin@school.com}"
export FLUTTER_ADMIN_PASSWORD="${FLUTTER_ADMIN_PASSWORD:-changeMe123}"

cd "${ROOT}/flutter_app"

DEFINES=(
  "--dart-define=FLUTTER_API_BASE_URL=${FLUTTER_API_BASE_URL}"
  "--dart-define=FLUTTER_SIMULATED_RECOGNITION=${FLUTTER_SIMULATED_RECOGNITION}"
  "--dart-define=FLUTTER_ADMIN_EMAIL=${FLUTTER_ADMIN_EMAIL}"
  "--dart-define=FLUTTER_ADMIN_PASSWORD=${FLUTTER_ADMIN_PASSWORD}"
)

MOBILE_IDS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && MOBILE_IDS+=("${line}")
done < <(flutter devices --machine 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in data:
    pid = d.get('targetPlatform') or ''
    name = (d.get('name') or '') + (d.get('modelName') or '')
    did = d.get('id') or ''
    if pid in ('darwin', 'web-javascript'):
        continue
    if 'simulator' in name.lower():
        continue
    if pid in ('ios', 'android-arm32', 'android-arm64', 'android-x86', 'android-x64') and did:
        print(did)
")

if [[ "${#MOBILE_IDS[@]}" -eq 0 ]]; then
  echo "No physical iOS/Android devices found. Connect a phone, then:" >&2
  echo "  export FLUTTER_API_BASE_URL=http://${MAC_IP}:8008" >&2
  echo "  cd flutter_app && flutter run -d <device-id> ${DEFINES[*]}" >&2
  exit 1
fi

echo "API base: ${FLUTTER_API_BASE_URL}"
echo "Launching Flutter on: ${MOBILE_IDS[*]}"

pids=()
for id in "${MOBILE_IDS[@]}"; do
  echo ">>> flutter run -d ${id}"
  flutter run -d "${id}" "${DEFINES[@]}" &
  pids+=("$!")
done

trap 'for p in "${pids[@]}"; do kill "${p}" 2>/dev/null || true; done' INT TERM
wait "${pids[@]}"
