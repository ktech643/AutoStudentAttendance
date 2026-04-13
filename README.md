# Face Attendance System (Flutter + iOS + FastAPI)

Production-minded near-MVP for kiosk-style student face attendance: Flutter client (iOS, web), native iOS face pipeline plugin, and a FastAPI backend with PostgreSQL, JWT admin auth, review queue, and offline-safe event sync.

## Prerequisites

- **Flutter** SDK (stable), **Xcode** (for iOS), **Chrome** (for web)
- **Python 3.11+** (project uses a local venv under `backend_fastapi/.venv`)
- **PostgreSQL** running locally (default URL in `backend_fastapi/.env.example`)

## Quick start

### 1. Backend

```bash
cd backend_fastapi
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env        # edit DATABASE_URL and secrets
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- API docs: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
- Health: [http://127.0.0.1:8000/health](http://127.0.0.1:8000/health)

Use **`--host 0.0.0.0`** so a **physical phone** on the same Wi‑Fi can reach the API via your Mac’s LAN IP.

### 2. Flutter app (configuration)

The app reads the API URL and bootstrap credentials from **compile-time** `--dart-define` values (see `flutter_app/lib/core/config/app_config.dart`).

| Target | Typical `FLUTTER_API_BASE_URL` |
|--------|----------------------------------|
| Web (Chrome) | `http://127.0.0.1:8000` |
| iOS Simulator | `http://127.0.0.1:8000` |
| Physical iPhone | `http://<your-mac-lan-ip>:8000` (not `127.0.0.1`) |

Optional defines:

- `FLUTTER_SIMULATED_RECOGNITION=true` — UI and API testing without the native face pipeline
- `FLUTTER_DEVICE_ID`, `FLUTTER_ADMIN_EMAIL`, `FLUTTER_ADMIN_PASSWORD` — defaults match `backend_fastapi/.env.example`

### 3. Run scripts (optional)

From `flutter_app/`:

```bash
./scripts/run_web.sh
./scripts/run_ios_sim.sh
# Physical device: set FLUTTER_API_BASE_URL to your Mac’s LAN URL, then:
./scripts/run_ios_device.sh
```

### 4. Manual `flutter run` examples

**Web**

```bash
cd flutter_app
flutter pub get
flutter run -d chrome --web-port=8080 \
  --dart-define=FLUTTER_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION=true \
  --dart-define=FLUTTER_ADMIN_EMAIL=admin@school.com \
  --dart-define=FLUTTER_ADMIN_PASSWORD=changeMe123
```

**iOS Simulator**

```bash
cd flutter_app
flutter run -d ios \
  --dart-define=FLUTTER_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION=true \
  --dart-define=FLUTTER_ADMIN_EMAIL=admin@school.com \
  --dart-define=FLUTTER_ADMIN_PASSWORD=changeMe123
```

**iOS device (USB or wireless)**

```bash
export FLUTTER_API_BASE_URL=http://$(ipconfig getifaddr en0):8000   # adjust interface if needed
cd flutter_app
flutter run -d <device-id> \
  --dart-define=FLUTTER_API_BASE_URL=$FLUTTER_API_BASE_URL \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION=true \
  --dart-define=FLUTTER_ADMIN_EMAIL=admin@school.com \
  --dart-define=FLUTTER_ADMIN_PASSWORD=changeMe123
```

**Web + SQLite in browser**

Web uses `sqflite_common_ffi_web` and a small init in `lib/main.dart` so the offline queue can run in the browser. The backend enables **CORS** for browser clients (see `backend_fastapi/app/main.py`).

## Using the app

1. **Enroll** (first tab): enter name, roll number, class, and section → continue to the camera step → **Start auto capture** for timed samples with on-screen instructions, or add **Manual sample** entries. Finish enrolls mock embeddings to the API (suitable for dev until native embeddings are wired).
2. **Kiosk**: live camera preview (where the device supports it), simulated or native recognition, attendance banner with name and roll when a mark succeeds online.
3. **Students / Logs / Review / Settings**: management and admin flows against the same API.

Simulated recognition uses **real student IDs** from the server when students have enrollments (`embedding_count > 0`).

## Repository layout

```text
.
├── ARCHITECTURE.md         # Deeper system notes
├── backend_fastapi/      # FastAPI, SQLAlchemy, Alembic, PostgreSQL
├── flutter_app/          # Flutter UI (iOS, web, macOS targets)
├── ios_native_plugin/    # iOS MethodChannel / EventChannel face pipeline
├── .env.example          # Root env hints (if present)
└── README.md             # This file
```

Module-specific details:

- [backend_fastapi/README.md](backend_fastapi/README.md) — endpoints, migrations, tests
- [flutter_app/README.md](flutter_app/README.md) — Flutter architecture notes
- [ios_native_plugin/README.md](ios_native_plugin/README.md) — native plugin overview

## Architecture (summary)

1. Kiosk starts recognition (native plugin or simulated timer).
2. Flutter applies thresholds (consecutive frames, stability, cooldowns).
3. Attendance events are `POST`ed to the backend; failures are queued locally and synced when online.
4. Borderline matches can create review-queue items.

Default threshold tuning lives in `flutter_app/lib/core/config/attendance_thresholds.dart` and can be aligned with device settings from the API.

## Testing

```bash
# Backend
cd backend_fastapi && source .venv/bin/activate && pytest -q

# Flutter
cd flutter_app && flutter test
```

## Known MVP limitations

- Enrollment embeddings from Flutter are **mock vectors** unless replaced with native model output.
- Advanced liveness / anti-spoof is not bundled; quality heuristics only.
- iOS Simulator often has **no camera**; use a real device or web for preview testing.

## Core ML / native pipeline

For production face vectors on iOS, integrate a real embedding model in `ios_native_plugin` and emit `RecognitionEvent` payloads (including `matched_student_roll_number` when available). Keep `FLUTTER_SIMULATED_RECOGNITION=false` on device builds that use the native stack.
