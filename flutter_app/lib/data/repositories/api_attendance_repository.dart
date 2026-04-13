import '../../core/models/attendance_event.dart';
import '../services/api_client.dart';
import 'attendance_repository.dart';

class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<void> bulkSync(List<AttendanceEvent> events) async {
    if (events.isEmpty) {
      return;
    }
    await _apiClient.dio.post<void>(
      '/attendance/events/bulk-sync',
      data: {'events': events.map((event) => event.toApiJson()).toList(growable: false)},
    );
  }

  @override
  Future<List<AttendanceEvent>> fetchRecent({int limit = 20}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/attendance/recent',
      queryParameters: {'limit': limit},
    );
    return response.data!
        .whereType<Map<String, dynamic>>()
        .map(AttendanceEvent.fromApiJson)
        .toList(growable: false);
  }

  @override
  Future<void> submitEvent(AttendanceEvent event) async {
    await _apiClient.dio.post<void>(
      '/attendance/events',
      data: event.toApiJson(),
    );
  }
}
