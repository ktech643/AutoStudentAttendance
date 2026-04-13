# iOS Native Plugin Module

Native iOS face pipeline for Flutter attendance kiosk.

## Implemented
- AVFoundation front camera session
- Frame throttling (~8 fps processing)
- Vision face detection
- Quality gates (face size, brightness, blur proxy, pose)
- Embedding model abstraction via `FaceEmbeddingModel`
- Mock embedding model adapter for development
- Cosine similarity matcher with top candidates
- Per-student and per-track cooldown suppression
- EventChannel payload emission for live recognition events
- MethodChannel controls:
  - `startRecognition`
  - `stopRecognition`
  - `setThresholds`
  - `reloadEmbeddings`
  - `setDebugMode`

## Core files
- `ios/Classes/FaceAttendancePlugin.swift`
- `ios/Classes/FaceRecognitionPipeline.swift`
- `ios/Classes/QualityGate.swift`
- `ios/Classes/EmbeddingModel.swift`
- `ios/Classes/FaceMatcher.swift`

## CoreML integration TODO
1. Add ArcFace-style CoreML model (`.mlmodelc`) to plugin bundle.
2. Implement `CoreMLFaceEmbeddingModel: FaceEmbeddingModel`.
3. Add robust face alignment (landmark-based) before model inference.
4. Replace blur proxy with Laplacian variance using Accelerate.
5. Add passive liveness model adapter and expand anti-spoof policy.
