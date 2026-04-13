import 'recognition_candidate.dart';

class AttendanceEvent {
  const AttendanceEvent({
    required this.eventUuid,
    required this.deviceId,
    required this.timestamp,
    required this.method,
    required this.confidence,
    required this.similarity,
    required this.synced,
    required this.reviewStatus,
    this.id,
    this.studentId,
    this.imageSnapshotPath,
    this.topCandidates = const [],
    this.reason,
  });

  final String? id;
  final String eventUuid;
  final String? studentId;
  final String deviceId;
  final DateTime timestamp;
  final String method;
  final double confidence;
  final double similarity;
  final bool synced;
  final String reviewStatus;
  final String? imageSnapshotPath;
  final List<RecognitionCandidate> topCandidates;
  final String? reason;

  AttendanceEvent copyWith({
    String? id,
    bool? synced,
  }) {
    return AttendanceEvent(
      id: id ?? this.id,
      eventUuid: eventUuid,
      studentId: studentId,
      deviceId: deviceId,
      timestamp: timestamp,
      method: method,
      confidence: confidence,
      similarity: similarity,
      synced: synced ?? this.synced,
      reviewStatus: reviewStatus,
      imageSnapshotPath: imageSnapshotPath,
      topCandidates: topCandidates,
      reason: reason,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'event_uuid': eventUuid,
      'student_id': studentId,
      'device_id': deviceId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'method': method,
      'confidence': confidence,
      'similarity': similarity,
      'review_status': reviewStatus,
      'image_snapshot_path': imageSnapshotPath,
      'top_candidates': topCandidates.map((candidate) => candidate.toJson()).toList(growable: false),
      'reason': reason,
    };
  }

  factory AttendanceEvent.fromApiJson(Map<String, dynamic> json) {
    final rawCandidates = json['top_candidates'] as List<dynamic>? ?? <dynamic>[];
    return AttendanceEvent(
      id: json['id'] as String?,
      eventUuid: json['event_uuid'] as String,
      studentId: json['student_id'] as String?,
      deviceId: json['device_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      method: json['method'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      similarity: (json['similarity'] as num).toDouble(),
      synced: json['synced'] as bool? ?? true,
      reviewStatus: json['review_status'] as String? ?? 'not_required',
      imageSnapshotPath: json['image_snapshot_path'] as String?,
      topCandidates: rawCandidates
          .whereType<Map<String, dynamic>>()
          .map(RecognitionCandidate.fromJson)
          .toList(growable: false),
      reason: json['reason'] as String?,
    );
  }
}
