class Student {
  const Student({
    required this.id,
    this.externalId,
    this.rollNumber,
    required this.fullName,
    required this.className,
    required this.section,
    required this.isActive,
    this.embeddingCount = 0,
  });

  final String id;
  final String? externalId;
  final String? rollNumber;
  final String fullName;
  final String className;
  final String section;
  final bool isActive;
  final int embeddingCount;

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      externalId: json['external_id'] as String?,
      rollNumber: json['roll_number'] as String?,
      fullName: json['full_name'] as String,
      className: json['class_name'] as String,
      section: json['section'] as String,
      isActive: json['is_active'] as bool? ?? true,
      embeddingCount: json['embedding_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'external_id': externalId,
      'roll_number': rollNumber,
      'full_name': fullName,
      'class_name': className,
      'section': section,
      'is_active': isActive,
      'embedding_count': embeddingCount,
    };
  }
}
