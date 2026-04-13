import 'recognition_candidate.dart';

class RecognitionEvent {
  const RecognitionEvent({
    required this.trackId,
    required this.confidence,
    required this.similarity,
    required this.qualityScore,
    required this.timestamp,
    required this.imageAcceptedForRecognition,
    this.matchedStudentId,
    this.matchedStudentName,
    this.matchedStudentRollNumber,
    this.faceBox,
    this.reasonIfRejected,
    this.topCandidates = const [],
  });

  final int trackId;
  final String? matchedStudentId;
  final String? matchedStudentName;
  final String? matchedStudentRollNumber;
  final double confidence;
  final double similarity;
  final Map<String, dynamic>? faceBox;
  final double qualityScore;
  final DateTime timestamp;
  final bool imageAcceptedForRecognition;
  final String? reasonIfRejected;
  final List<RecognitionCandidate> topCandidates;

  factory RecognitionEvent.fromJson(Map<String, dynamic> json) {
    final candidateJson = (json['topCandidates'] as List<dynamic>? ?? json['top_candidates'] as List<dynamic>? ?? <dynamic>[]);
    return RecognitionEvent(
      trackId: (json['trackId'] as num? ?? json['track_id'] as num).toInt(),
      matchedStudentId: json['matchedStudentId'] as String? ?? json['matched_student_id'] as String?,
      matchedStudentName: json['matchedStudentName'] as String? ?? json['matched_student_name'] as String?,
      matchedStudentRollNumber:
          json['matchedStudentRollNumber'] as String? ?? json['matched_student_roll_number'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
      faceBox: json['faceBox'] as Map<String, dynamic>? ?? json['face_box'] as Map<String, dynamic>?,
      qualityScore: (json['qualityScore'] as num? ?? json['quality_score'] as num? ?? 0.0).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      imageAcceptedForRecognition: json['imageAcceptedForRecognition'] as bool? ?? json['image_accepted_for_recognition'] as bool? ?? false,
      reasonIfRejected: json['reasonIfRejected'] as String? ?? json['reason_if_rejected'] as String?,
      topCandidates: candidateJson
          .whereType<Map<String, dynamic>>()
          .map(RecognitionCandidate.fromJson)
          .toList(growable: false),
    );
  }
}
