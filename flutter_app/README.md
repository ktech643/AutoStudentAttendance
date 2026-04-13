# Flutter App Module

Flutter front-end for kiosk attendance operations and admin workflows.

## Features included
- Attendance kiosk screen with live recognition overlay and counters
- Student management and enrollment flow
- Attendance logs and review queue screens
- Settings for recognition thresholds
- Native iOS platform channel integration (`MethodChannel` + `EventChannel`)
- Simulated recognition mode for UI/dev testing without camera/model
- Offline queue in SQLite with sync service

## Run

```bash
flutter pub get
flutter run -d ios \
  --dart-define=FLUTTER_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=FLUTTER_SIMULATED_RECOGNITION=true \
  --dart-define=FLUTTER_ADMIN_EMAIL=admin@school.com \
  --dart-define=FLUTTER_ADMIN_PASSWORD=changeMe123
```

Set `FLUTTER_SIMULATED_RECOGNITION=false` when using the real native iOS pipeline.

## Architecture (clean-ish layers)
- `core/`: config, models, db, utilities
- `data/`: repositories and services
- `presentation/`: providers and screens

## Notes
- Threshold values in `core/config/attendance_thresholds.dart` are deployment-tuning defaults.
- Enrollment currently uses mock embeddings in Flutter; production enrollment should come from native model output.
