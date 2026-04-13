class AttendanceThresholds {
  const AttendanceThresholds({
    this.autoMarkThreshold = 0.72,
    this.reviewThreshold = 0.62,
    this.consecutiveFramesRequired = 3,
    this.minStableTrackingSeconds = 1.0,
    this.studentCooldownSeconds = 300,
    this.trackCooldownSeconds = 10,
    this.minFaceSizeRatio = 0.10,
    this.minBlurScore = 100.0,
    this.minBrightness = 35.0,
    this.maxAbsYaw = 20.0,
    this.maxAbsPitch = 20.0,
    this.debugMode = false,
  });

  // Deployment tuning values. Adjust after field validation on real device setup.
  final double autoMarkThreshold;
  final double reviewThreshold;
  final int consecutiveFramesRequired;
  final double minStableTrackingSeconds;
  final int studentCooldownSeconds;
  final int trackCooldownSeconds;
  final double minFaceSizeRatio;
  final double minBlurScore;
  final double minBrightness;
  final double maxAbsYaw;
  final double maxAbsPitch;
  final bool debugMode;

  AttendanceThresholds copyWith({
    double? autoMarkThreshold,
    double? reviewThreshold,
    int? consecutiveFramesRequired,
    double? minStableTrackingSeconds,
    int? studentCooldownSeconds,
    int? trackCooldownSeconds,
    double? minFaceSizeRatio,
    double? minBlurScore,
    double? minBrightness,
    double? maxAbsYaw,
    double? maxAbsPitch,
    bool? debugMode,
  }) {
    return AttendanceThresholds(
      autoMarkThreshold: autoMarkThreshold ?? this.autoMarkThreshold,
      reviewThreshold: reviewThreshold ?? this.reviewThreshold,
      consecutiveFramesRequired: consecutiveFramesRequired ?? this.consecutiveFramesRequired,
      minStableTrackingSeconds: minStableTrackingSeconds ?? this.minStableTrackingSeconds,
      studentCooldownSeconds: studentCooldownSeconds ?? this.studentCooldownSeconds,
      trackCooldownSeconds: trackCooldownSeconds ?? this.trackCooldownSeconds,
      minFaceSizeRatio: minFaceSizeRatio ?? this.minFaceSizeRatio,
      minBlurScore: minBlurScore ?? this.minBlurScore,
      minBrightness: minBrightness ?? this.minBrightness,
      maxAbsYaw: maxAbsYaw ?? this.maxAbsYaw,
      maxAbsPitch: maxAbsPitch ?? this.maxAbsPitch,
      debugMode: debugMode ?? this.debugMode,
    );
  }

  Map<String, dynamic> toMap(String deviceId) {
    return {
      'device_id': deviceId,
      'auto_mark_threshold': autoMarkThreshold,
      'review_threshold': reviewThreshold,
      'consecutive_frames_required': consecutiveFramesRequired,
      'min_stable_tracking_seconds': minStableTrackingSeconds,
      'student_cooldown_seconds': studentCooldownSeconds,
      'track_cooldown_seconds': trackCooldownSeconds,
      'min_face_size_ratio': minFaceSizeRatio,
      'min_blur_score': minBlurScore,
      'min_brightness': minBrightness,
      'max_abs_yaw': maxAbsYaw,
      'max_abs_pitch': maxAbsPitch,
      'debug_mode': debugMode,
    };
  }

  Map<String, dynamic> toPlatformMap() {
    return {
      'auto_mark_threshold': autoMarkThreshold,
      'review_threshold': reviewThreshold,
      'consecutive_frames_required': consecutiveFramesRequired,
      'min_stable_tracking_seconds': minStableTrackingSeconds,
      'student_cooldown_seconds': studentCooldownSeconds,
      'track_cooldown_seconds': trackCooldownSeconds,
      'min_face_size_ratio': minFaceSizeRatio,
      'min_blur_score': minBlurScore,
      'min_brightness': minBrightness,
      'max_abs_yaw': maxAbsYaw,
      'max_abs_pitch': maxAbsPitch,
      'debug_mode': debugMode,
    };
  }

  factory AttendanceThresholds.fromMap(Map<String, dynamic> map) {
    return AttendanceThresholds(
      autoMarkThreshold: (map['auto_mark_threshold'] as num?)?.toDouble() ?? 0.72,
      reviewThreshold: (map['review_threshold'] as num?)?.toDouble() ?? 0.62,
      consecutiveFramesRequired: (map['consecutive_frames_required'] as num?)?.toInt() ?? 3,
      minStableTrackingSeconds: (map['min_stable_tracking_seconds'] as num?)?.toDouble() ?? 1.0,
      studentCooldownSeconds: (map['student_cooldown_seconds'] as num?)?.toInt() ?? 300,
      trackCooldownSeconds: (map['track_cooldown_seconds'] as num?)?.toInt() ?? 10,
      minFaceSizeRatio: (map['min_face_size_ratio'] as num?)?.toDouble() ?? 0.10,
      minBlurScore: (map['min_blur_score'] as num?)?.toDouble() ?? 100.0,
      minBrightness: (map['min_brightness'] as num?)?.toDouble() ?? 35.0,
      maxAbsYaw: (map['max_abs_yaw'] as num?)?.toDouble() ?? 20.0,
      maxAbsPitch: (map['max_abs_pitch'] as num?)?.toDouble() ?? 20.0,
      debugMode: (map['debug_mode'] as bool?) ?? false,
    );
  }
}
