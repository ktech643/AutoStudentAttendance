import '../../core/config/attendance_thresholds.dart';
import '../../core/models/recognition_event.dart';

enum RecognitionActionType {
  autoMark,
  createReview,
  ignore,
}

class RecognitionAction {
  const RecognitionAction({
    required this.type,
    required this.reason,
  });

  final RecognitionActionType type;
  final String reason;

  bool get shouldAutoMark => type == RecognitionActionType.autoMark;
  bool get shouldCreateReview => type == RecognitionActionType.createReview;
}

class _TrackState {
  _TrackState({
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.acceptedFrameCount,
    required this.lastDecisionAt,
  });

  DateTime firstSeenAt;
  DateTime lastSeenAt;
  int acceptedFrameCount;
  DateTime? lastDecisionAt;
}

class RecognitionDecisionEngine {
  RecognitionDecisionEngine(this.thresholds);

  AttendanceThresholds thresholds;
  final Map<int, _TrackState> _trackStates = <int, _TrackState>{};
  final Map<String, DateTime> _studentLastMarkedAt = <String, DateTime>{};

  void updateThresholds(AttendanceThresholds updated) {
    thresholds = updated;
  }

  RecognitionAction evaluate(RecognitionEvent event) {
    final now = event.timestamp.toUtc();
    final state = _trackStates[event.trackId] ??
        _TrackState(
          firstSeenAt: now,
          lastSeenAt: now,
          acceptedFrameCount: 0,
          lastDecisionAt: null,
        );
    _trackStates[event.trackId] = state;

    state.lastSeenAt = now;

    if (!event.imageAcceptedForRecognition) {
      state.acceptedFrameCount = 0;
      return RecognitionAction(
        type: RecognitionActionType.ignore,
        reason: event.reasonIfRejected ?? 'quality_rejected',
      );
    }

    final trackCooldownReady = state.lastDecisionAt == null ||
        now.difference(state.lastDecisionAt!).inSeconds >= thresholds.trackCooldownSeconds;
    if (!trackCooldownReady) {
      return const RecognitionAction(
        type: RecognitionActionType.ignore,
        reason: 'track_cooldown',
      );
    }

    if (event.similarity >= thresholds.autoMarkThreshold && event.matchedStudentId != null) {
      state.acceptedFrameCount += 1;
      final stableSeconds = now.difference(state.firstSeenAt).inMilliseconds / 1000.0;
      if (state.acceptedFrameCount < thresholds.consecutiveFramesRequired ||
          stableSeconds < thresholds.minStableTrackingSeconds) {
        return const RecognitionAction(
          type: RecognitionActionType.ignore,
          reason: 'waiting_for_consecutive_frames',
        );
      }

      final studentId = event.matchedStudentId!;
      final lastMarkedAt = _studentLastMarkedAt[studentId];
      if (lastMarkedAt != null &&
          now.difference(lastMarkedAt).inSeconds < thresholds.studentCooldownSeconds) {
        return const RecognitionAction(
          type: RecognitionActionType.ignore,
          reason: 'student_cooldown',
        );
      }

      _studentLastMarkedAt[studentId] = now;
      state.lastDecisionAt = now;
      state.acceptedFrameCount = 0;
      return const RecognitionAction(
        type: RecognitionActionType.autoMark,
        reason: 'auto_threshold_met',
      );
    }

    if (event.similarity >= thresholds.reviewThreshold) {
      state.lastDecisionAt = now;
      state.acceptedFrameCount = 0;
      return const RecognitionAction(
        type: RecognitionActionType.createReview,
        reason: 'borderline_similarity',
      );
    }

    state.acceptedFrameCount = 0;
    return const RecognitionAction(
      type: RecognitionActionType.ignore,
      reason: 'below_review_threshold',
    );
  }
}
