import '../../core/models/attendance_event.dart';
import '../../core/models/recognition_event.dart';

class KioskState {
  const KioskState({
    this.isOnline = true,
    this.cameraReady = false,
    this.recognitionActive = false,
    this.latestRecognition,
    this.recentAttendance = const [],
    this.pendingQueueCount = 0,
    this.framesProcessed = 0,
    this.recognitionAttempts = 0,
    this.successfulMatches = 0,
    this.rejectedByQuality = 0,
    this.duplicatePrevented = 0,
    this.queuedOffline = 0,
    this.lastStatusMessage,
    this.attendanceBannerName,
    this.attendanceBannerRoll,
    this.attendanceBannerStatus,
  });

  final bool isOnline;
  final bool cameraReady;
  final bool recognitionActive;
  final RecognitionEvent? latestRecognition;
  final List<AttendanceEvent> recentAttendance;
  final int pendingQueueCount;
  final int framesProcessed;
  final int recognitionAttempts;
  final int successfulMatches;
  final int rejectedByQuality;
  final int duplicatePrevented;
  final int queuedOffline;
  final String? lastStatusMessage;
  final String? attendanceBannerName;
  final String? attendanceBannerRoll;
  final String? attendanceBannerStatus;

  KioskState copyWith({
    bool? isOnline,
    bool? cameraReady,
    bool? recognitionActive,
    RecognitionEvent? latestRecognition,
    List<AttendanceEvent>? recentAttendance,
    int? pendingQueueCount,
    int? framesProcessed,
    int? recognitionAttempts,
    int? successfulMatches,
    int? rejectedByQuality,
    int? duplicatePrevented,
    int? queuedOffline,
    String? lastStatusMessage,
    String? attendanceBannerName,
    String? attendanceBannerRoll,
    String? attendanceBannerStatus,
    bool clearAttendanceBanner = false,
  }) {
    return KioskState(
      isOnline: isOnline ?? this.isOnline,
      cameraReady: cameraReady ?? this.cameraReady,
      recognitionActive: recognitionActive ?? this.recognitionActive,
      latestRecognition: latestRecognition ?? this.latestRecognition,
      recentAttendance: recentAttendance ?? this.recentAttendance,
      pendingQueueCount: pendingQueueCount ?? this.pendingQueueCount,
      framesProcessed: framesProcessed ?? this.framesProcessed,
      recognitionAttempts: recognitionAttempts ?? this.recognitionAttempts,
      successfulMatches: successfulMatches ?? this.successfulMatches,
      rejectedByQuality: rejectedByQuality ?? this.rejectedByQuality,
      duplicatePrevented: duplicatePrevented ?? this.duplicatePrevented,
      queuedOffline: queuedOffline ?? this.queuedOffline,
      lastStatusMessage: lastStatusMessage ?? this.lastStatusMessage,
      attendanceBannerName: clearAttendanceBanner ? null : (attendanceBannerName ?? this.attendanceBannerName),
      attendanceBannerRoll: clearAttendanceBanner ? null : (attendanceBannerRoll ?? this.attendanceBannerRoll),
      attendanceBannerStatus: clearAttendanceBanner ? null : (attendanceBannerStatus ?? this.attendanceBannerStatus),
    );
  }
}
