class RecognitionCandidate {
  const RecognitionCandidate({
    required this.studentId,
    required this.studentName,
    required this.similarity,
    required this.confidence,
  });

  final String studentId;
  final String studentName;
  final double similarity;
  final double confidence;

  factory RecognitionCandidate.fromJson(Map<String, dynamic> json) {
    return RecognitionCandidate(
      studentId: json['studentId'] as String? ?? json['student_id'] as String,
      studentName: json['studentName'] as String? ?? json['student_name'] as String,
      similarity: (json['similarity'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'student_name': studentName,
      'similarity': similarity,
      'confidence': confidence,
    };
  }
}
