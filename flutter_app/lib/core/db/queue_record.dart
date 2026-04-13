class QueueRecord {
  const QueueRecord({
    required this.id,
    required this.payloadJson,
    required this.createdAt,
    required this.retryCount,
    required this.synced,
  });

  final int id;
  final String payloadJson;
  final DateTime createdAt;
  final int retryCount;
  final bool synced;

  factory QueueRecord.fromMap(Map<String, Object?> map) {
    return QueueRecord(
      id: map['id'] as int,
      payloadJson: map['payload_json'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      synced: (map['synced'] as int? ?? 0) == 1,
    );
  }
}
