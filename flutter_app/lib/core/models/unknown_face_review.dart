import 'recognition_candidate.dart';

class UnknownFaceReview {
  const UnknownFaceReview({
    required this.id,
    required this.eventId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.snapshotPath,
    this.topCandidates = const [],
  });

  final String id;
  final String eventId;
  final String? snapshotPath;
  final List<RecognitionCandidate> topCandidates;
  final String reason;
  final String status;
  final DateTime createdAt;

  factory UnknownFaceReview.fromJson(Map<String, dynamic> json) {
    final candidates = json['top_candidates'] as List<dynamic>? ?? <dynamic>[];
    return UnknownFaceReview(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      snapshotPath: json['snapshot_path'] as String?,
      topCandidates: candidates
          .whereType<Map<String, dynamic>>()
          .map(RecognitionCandidate.fromJson)
          .toList(growable: false),
      reason: json['reason'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
