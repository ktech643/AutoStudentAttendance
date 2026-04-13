import '../../core/models/attendance_event.dart';

abstract class AttendanceRepository {
  Future<List<AttendanceEvent>> fetchRecent({int limit = 20});
  Future<void> submitEvent(AttendanceEvent event);
  Future<void> bulkSync(List<AttendanceEvent> events);
}
