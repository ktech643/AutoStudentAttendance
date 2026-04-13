# Architecture Notes

## System boundaries
- `flutter_app`: kiosk UX, operator workflows, state orchestration, offline queue, sync.
- `ios_native_plugin`: low-latency on-device face pipeline (camera, detection, quality gating, embedding, matching).
- `backend_fastapi`: identity, enrollment storage, idempotent attendance ingestion, review workflow, reporting, settings.

## Recognition decision split
- Native plugin performs frame-by-frame detection, quality gating, embeddings, candidate matching.
- Flutter applies attendance policy (consecutive frames, stable time, thresholds, cooldown).
- Backend applies final idempotency and duplicate checks by `event_uuid` and student cooldown checks.

## Data privacy model
- Student profile table is separate from embedding vectors.
- Embeddings are hidden from normal student responses.
- Optional image snapshot paths are retained only when policy enables storage.
- Review actions are audit logged with actor + target + reason.

## Offline reliability
- Attendance events are attempted online first.
- On network/API failure, events queue to local SQLite.
- Sync service performs bulk replay and marks queued rows as synced.
- Event UUID ensures replay is idempotent.

## Performance targets (MVP assumptions)
- Throttled face processing ~8 fps on iPad.
- In-memory embedding lookup for low-latency matching.
- Non-blocking background queues for camera and model work.
- Structured debug counters/logs for tune-up.
