#!/usr/bin/env bash
# Start AttendX (Docker) on host port 8008 — phones use http://<mac-lan-ip>:8008
# If something already answers /health on 8008, docker compose is skipped.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC_IP="$(bash "${ROOT}/flutter_app/scripts/lib_mac_ip.sh")"

if curl -fsS "http://127.0.0.1:8008/health" >/dev/null 2>&1; then
  echo "Backend already up on http://127.0.0.1:8008 (skipping docker compose)."
else
  echo "Starting AttendX API (docker compose)…"
  cd "${ROOT}"
  docker compose -f docker-compose.attendx.yml -p faceattendance up -d attendx-api

  echo "Waiting for http://127.0.0.1:8008/health …"
  ok=0
  for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:8008/health" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 2
  done
  if [[ "${ok}" -ne 1 ]]; then
    echo "ERROR: backend did not become healthy on port 8008." >&2
    exit 1
  fi
fi

echo "Local:   http://127.0.0.1:8008"
echo "From phone (Wi‑Fi): http://${MAC_IP}:8008"
curl -sS "http://127.0.0.1:8008/health" | head -c 300
echo
