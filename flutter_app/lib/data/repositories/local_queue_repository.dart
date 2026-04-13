import '../../core/models/attendance_event.dart';

abstract class LocalQueueRepository {
  Future<void> enqueue(AttendanceEvent event);
  Future<List<AttendanceEvent>> pendingEvents({int limit = 200});
  Future<void> markSyncedByEventUuid(String eventUuid);
  Future<int> pendingCount();
}
