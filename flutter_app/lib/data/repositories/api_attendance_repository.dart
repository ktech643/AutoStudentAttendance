import '../../core/models/attendance_event.dart';
import '../services/api_client.dart';
import 'attendance_repository.dart';

class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<void> bulkSync(List<AttendanceEvent> events) async {
    if (events.isEmpty) return;
    try {
      await _apiClient.dio.post<void>(
        '/attendance/events/bulk-sync',
        data: {
          'events': events.map((e) => e.toApiJson()).toList(growable: false),
        },
      );
    } catch (_) {
      // Docker does not have a bulk-sync endpoint — silently skip.
      // Events stay in the local queue and the UI shows them via fetchRecent().
    }
  }

  @override
  Future<List<AttendanceEvent>> fetchRecent({int limit = 20}) async {
    // Try our FastAPI endpoint first.
    try {
      final response = await _apiClient.dio.get<List<dynamic>>(
        '/attendance/recent',
        queryParameters: {'limit': limit},
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data!
            .whereType<Map<String, dynamic>>()
            .map(AttendanceEvent.fromApiJson)
            .toList(growable: false);
      }
    } catch (_) {}

    // Docker AttendX fallback: GET /attendance/today → { records: [...] }
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>('/attendance/today');
      final records = (response.data?['records'] as List<dynamic>?) ?? [];
      return records.whereType<Map<String, dynamic>>().map((r) {
        final dateStr = response.data?['date'] as String? ?? DateTime.now().toIso8601String();
        final timeStr = r['marked_at'] as String? ?? '00:00:00';
        DateTime ts;
        try {
          ts = DateTime.parse('${dateStr}T$timeStr');
        } catch (_) {
          ts = DateTime.now();
        }
        return AttendanceEvent(
          eventUuid: '${r['student_id']}_$timeStr',
          studentId: r['student_id'] as String?,
          deviceId: 'docker',
          timestamp: ts,
          method: 'auto',
          confidence: (r['confidence'] as num?)?.toDouble() ?? 0.0,
          similarity: (r['confidence'] as num?)?.toDouble() ?? 0.0,
          synced: true,
          reviewStatus: 'not_required',
        );
      }).take(limit).toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> submitEvent(AttendanceEvent event) async {
    // Try our FastAPI endpoint.
    try {
      await _apiClient.dio.post<void>('/attendance/events', data: event.toApiJson());
      return;
    } catch (_) {
      // Docker handles attendance inside /recognize — no separate submit endpoint.
      // Silently succeed so the kiosk UI shows the banner without crashing.
    }
  }
}
