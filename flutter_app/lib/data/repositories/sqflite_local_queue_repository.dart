import 'dart:convert';

import '../../core/db/local_database.dart';
import '../../core/models/attendance_event.dart';
import 'package:sqflite/sqflite.dart';
import 'local_queue_repository.dart';

class SqfliteLocalQueueRepository implements LocalQueueRepository {
  SqfliteLocalQueueRepository(this._database);

  final LocalDatabase _database;

  @override
  Future<void> enqueue(AttendanceEvent event) async {
    final db = await _database.db;
    await db.insert(
      'attendance_queue',
      {
        'event_uuid': event.eventUuid,
        'payload_json': jsonEncode(event.toApiJson()),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'retry_count': 0,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> markSyncedByEventUuid(String eventUuid) async {
    final db = await _database.db;
    await db.update(
      'attendance_queue',
      {'synced': 1},
      where: 'event_uuid = ?',
      whereArgs: [eventUuid],
    );
  }

  @override
  Future<List<AttendanceEvent>> pendingEvents({int limit = 200}) async {
    final db = await _database.db;
    final rows = await db.query(
      'attendance_queue',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map((row) {
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      return AttendanceEvent.fromApiJson(payload).copyWith(synced: false);
    }).toList(growable: false);
  }

  @override
  Future<int> pendingCount() async {
    final db = await _database.db;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM attendance_queue WHERE synced = 0');
    return (result.first['count'] as int?) ?? 0;
  }
}
