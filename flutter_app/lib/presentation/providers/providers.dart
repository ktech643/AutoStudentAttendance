import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/config/attendance_thresholds.dart';
import '../../core/db/local_database.dart';
import '../../core/models/attendance_event.dart';
import '../../core/models/recognition_event.dart';
import '../../core/models/student.dart';
import '../../data/repositories/api_attendance_repository.dart';
import '../../data/repositories/api_student_repository.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/local_queue_repository.dart';
import '../../data/repositories/sqflite_local_queue_repository.dart';
import '../../data/repositories/student_repository.dart';
import '../../data/services/api_client.dart';
import '../../data/services/auth_bootstrap_service.dart';
import '../../data/services/analytics_hook.dart';
import '../../data/services/face_attendance_platform_service.dart';
import '../../data/services/recognition_decision_engine.dart';
import '../../data/services/docker_recognition_source.dart';
import '../../data/services/recognition_source.dart';
import '../../data/services/simulated_recognition_service.dart';
import '../../data/services/sync_service.dart';
import 'kiosk_state.dart';

final appConfigProvider = Provider<AppConfig>((ref) => defaultAppConfig);

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(baseUrl: config.apiBaseUrl);
});

final attendanceThresholdsProvider = StateProvider<AttendanceThresholds>((_) => const AttendanceThresholds());

final localQueueRepositoryProvider = Provider<LocalQueueRepository>(
  (ref) => SqfliteLocalQueueRepository(LocalDatabase.instance),
);

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => ApiAttendanceRepository(ref.watch(apiClientProvider)),
);

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => ApiStudentRepository(ref.watch(apiClientProvider)),
);

final simulatedRecognitionServiceProvider = Provider<SimulatedRecognitionService>((ref) {
  final service = SimulatedRecognitionService();
  ref.onDispose(service.dispose);
  return service;
});

/// Students used by simulated recognition (real UUIDs / names / rolls). Refresh from the kiosk screen.
final simulatedStudentPoolProvider = StateProvider<List<Student>>((ref) => const []);

/// Whether the configured backend is the Docker AttendX API.
/// Detected by attempting to fetch /health and checking for docker-specific fields.
/// We also use a simple heuristic: if /embeddings/all is unavailable the backend is Docker.
final isDockerBackendProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(apiClientProvider);
  try {
    final r = await client.dio.get<Map<String, dynamic>>('/health');
    final data = r.data ?? {};
    // Docker health returns { model_fast, model_accurate } — our FastAPI doesn't.
    return data.containsKey('model_fast') || data.containsKey('models_loaded');
  } catch (_) {
    return false;
  }
});

final recognitionSourceProvider = Provider<RecognitionSource>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.simulatedRecognition) {
    return SimulatedRecognitionSource(
      ref.watch(simulatedRecognitionServiceProvider),
      () => ref.read(simulatedStudentPoolProvider),
    );
  }
  // Use DockerRecognitionSource when the backend is Docker AttendX (server-side InsightFace).
  // Fall back to native on-device recognition for our custom FastAPI backend.
  final isDocker = ref.watch(isDockerBackendProvider).valueOrNull ?? false;
  if (isDocker) {
    return DockerRecognitionSource(dio: ref.watch(apiClientProvider).dio);
  }
  return PlatformRecognitionSource(FaceAttendancePlatformService());
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    attendanceRepository: ref.watch(attendanceRepositoryProvider),
    localQueueRepository: ref.watch(localQueueRepositoryProvider),
    connectivity: Connectivity(),
  );
});

final analyticsHookProvider = Provider<AnalyticsHook>((_) => ConsoleAnalyticsHook());
final authBootstrapServiceProvider = Provider<AuthBootstrapService>(
  (ref) => AuthBootstrapService(ref.watch(apiClientProvider)),
);
final appBootstrapProvider = FutureProvider<void>((ref) async {
  final config = ref.read(appConfigProvider);
  await ref.read(authBootstrapServiceProvider).loginDefaultAdmin(config);
});

final studentListProvider = FutureProvider<List<Student>>((ref) {
  return ref.watch(studentRepositoryProvider).fetchStudents();
});

final recentAttendanceProvider = FutureProvider<List<AttendanceEvent>>((ref) {
  return ref.watch(attendanceRepositoryProvider).fetchRecent(limit: 25);
});

final kioskControllerProvider = StateNotifierProvider<KioskController, KioskState>((ref) {
  final controller = KioskController(
    source: ref.watch(recognitionSourceProvider),
    attendanceRepository: ref.watch(attendanceRepositoryProvider),
    studentRepository: ref.watch(studentRepositoryProvider),
    queueRepository: ref.watch(localQueueRepositoryProvider),
    syncService: ref.watch(syncServiceProvider),
    decisionEngine: RecognitionDecisionEngine(ref.watch(attendanceThresholdsProvider)),
    analyticsHook: ref.watch(analyticsHookProvider),
    thresholdsProvider: ref.watch(attendanceThresholdsProvider.notifier),
    appConfig: ref.watch(appConfigProvider),
  );
  return controller;
});

class KioskController extends StateNotifier<KioskState> {
  KioskController({
    required RecognitionSource source,
    required AttendanceRepository attendanceRepository,
    required StudentRepository studentRepository,
    required LocalQueueRepository queueRepository,
    required SyncService syncService,
    required RecognitionDecisionEngine decisionEngine,
    required AnalyticsHook analyticsHook,
    required StateController<AttendanceThresholds> thresholdsProvider,
    required AppConfig appConfig,
  })  : _source = source,
        _attendanceRepository = attendanceRepository,
        _studentRepository = studentRepository,
        _queueRepository = queueRepository,
        _syncService = syncService,
        _decisionEngine = decisionEngine,
        _analyticsHook = analyticsHook,
        _thresholdsProvider = thresholdsProvider,
        _appConfig = appConfig,
        super(const KioskState()) {
    _syncService.start();
    refreshPendingCount();
    refreshRecentAttendance();
  }

  final RecognitionSource _source;
  final AttendanceRepository _attendanceRepository;
  final StudentRepository _studentRepository;
  final LocalQueueRepository _queueRepository;
  final SyncService _syncService;
  final RecognitionDecisionEngine _decisionEngine;
  final AnalyticsHook _analyticsHook;
  final StateController<AttendanceThresholds> _thresholdsProvider;
  final AppConfig _appConfig;
  final Uuid _uuid = const Uuid();
  StreamSubscription<RecognitionEvent>? _recognitionSubscription;
  Timer? _attendanceBannerTimer;

  void _scheduleAttendanceBanner(RecognitionEvent event, String status) {
    _attendanceBannerTimer?.cancel();
    state = state.copyWith(
      attendanceBannerName: event.matchedStudentName,
      attendanceBannerRoll: event.matchedStudentRollNumber,
      attendanceBannerStatus: status,
    );
    _attendanceBannerTimer = Timer(const Duration(seconds: 12), () {
      state = state.copyWith(clearAttendanceBanner: true);
    });
  }

  Future<void> startRecognition() async {
    // Push the latest enrolled embeddings to the native plugin so matching
    // can happen entirely on-device without per-frame network calls.
    if (!_appConfig.simulatedRecognition) {
      await _loadEmbeddingsToNative();
    }
    await _source.start(_thresholdsProvider.state);
    _recognitionSubscription?.cancel();
    _recognitionSubscription = _source.events().listen(_onRecognitionEvent);
    state = state.copyWith(
      recognitionActive: true,
      lastStatusMessage: 'Recognition started — waiting for camera preview',
    );
  }

  Future<void> _loadEmbeddingsToNative() async {
    try {
      final embeddings = await _studentRepository.fetchAllEmbeddingsForDevice();
      await _source.loadEnrolledEmbeddings(embeddings);
      state = state.copyWith(
        lastStatusMessage: 'Loaded ${embeddings.length} enrolled embeddings',
      );
    } catch (e) {
      // Non-fatal: recognition will still work but with empty embedding store.
      state = state.copyWith(lastStatusMessage: 'Warning: could not load embeddings ($e)');
    }
  }

  /// Call when [FaceCameraView] (or native surface) is ready / lost.
  void reportCameraPreviewReady(bool ready) {
    state = state.copyWith(
      cameraReady: ready,
      lastStatusMessage: ready ? 'Camera preview ready' : 'Camera preview stopped',
    );
  }

  Future<void> stopRecognition() async {
    await _recognitionSubscription?.cancel();
    _recognitionSubscription = null;
    await _source.stop();
    state = state.copyWith(
      recognitionActive: false,
      cameraReady: false,
      lastStatusMessage: 'Recognition stopped',
    );
  }

  void updateThresholds(AttendanceThresholds thresholds) {
    _thresholdsProvider.state = thresholds;
    _decisionEngine.updateThresholds(thresholds);
  }

  Future<void> _onRecognitionEvent(RecognitionEvent event) async {
    state = state.copyWith(
      latestRecognition: event,
      framesProcessed: state.framesProcessed + 1,
    );
    _analyticsHook.track('frame_processed', properties: {'trackId': event.trackId});
    if (!event.imageAcceptedForRecognition) {
      state = state.copyWith(rejectedByQuality: state.rejectedByQuality + 1);
      _analyticsHook.track('quality_rejected', properties: {'reason': event.reasonIfRejected});
      return;
    }

    state = state.copyWith(recognitionAttempts: state.recognitionAttempts + 1);
    final action = _decisionEngine.evaluate(event);
    if (action.shouldAutoMark) {
      final submitted = await _persistAttendance(event, 'auto', 'not_required');
      if (submitted) {
        state = state.copyWith(successfulMatches: state.successfulMatches + 1);
        _scheduleAttendanceBanner(event, 'Attendance marked');
      }
      _analyticsHook.track('attendance_auto_marked', properties: {'studentId': event.matchedStudentId});
      return;
    }

    if (action.shouldCreateReview) {
      final submitted = await _persistAttendance(event, 'auto', 'pending');
      if (submitted) {
        _scheduleAttendanceBanner(event, 'Attendance saved • review pending');
      }
      _analyticsHook.track('attendance_review_created');
    }
  }

  Future<bool> _persistAttendance(
    RecognitionEvent event,
    String method,
    String reviewStatus,
  ) async {
    final attendanceEvent = AttendanceEvent(
      eventUuid: _uuid.v4(),
      studentId: event.matchedStudentId,
      deviceId: _appConfig.deviceId,
      timestamp: event.timestamp,
      method: method,
      confidence: event.confidence,
      similarity: event.similarity,
      synced: true,
      reviewStatus: reviewStatus,
      topCandidates: event.topCandidates,
      reason: reviewStatus == 'pending' ? 'borderline_similarity' : null,
    );

    try {
      await _attendanceRepository.submitEvent(attendanceEvent);
      state = state.copyWith(isOnline: true);
      _analyticsHook.track('attendance_submitted_online');
      await refreshRecentAttendance();
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) {
        state = state.copyWith(duplicatePrevented: state.duplicatePrevented + 1);
        _analyticsHook.track('duplicate_prevented');
        return false;
      }
      await _queueRepository.enqueue(attendanceEvent.copyWith(synced: false));
      state = state.copyWith(
        isOnline: false,
        queuedOffline: state.queuedOffline + 1,
      );
      _analyticsHook.track('attendance_queued_offline');
      await refreshPendingCount();
      return false;
    } catch (_) {
      await _queueRepository.enqueue(attendanceEvent.copyWith(synced: false));
      state = state.copyWith(
        isOnline: false,
        queuedOffline: state.queuedOffline + 1,
      );
      _analyticsHook.track('attendance_queued_offline');
      await refreshPendingCount();
      return false;
    }
  }

  Future<void> refreshRecentAttendance() async {
    try {
      final events = await _attendanceRepository.fetchRecent(limit: 15);
      state = state.copyWith(recentAttendance: events);
    } catch (_) {
      // Keep UI responsive even when API is down.
    }
  }

  Future<void> forceSync() async {
    await _syncService.flushPending();
    await refreshPendingCount();
    await refreshRecentAttendance();
  }

  Future<void> refreshPendingCount() async {
    final count = await _queueRepository.pendingCount();
    state = state.copyWith(pendingQueueCount: count);
  }

  @override
  void dispose() {
    _attendanceBannerTimer?.cancel();
    _recognitionSubscription?.cancel();
    unawaited(_source.stop());
    unawaited(_syncService.stop());
    super.dispose();
  }
}
