import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/models/attendance_event.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/local_queue_repository.dart';

class SyncService {
  SyncService({
    required AttendanceRepository attendanceRepository,
    required LocalQueueRepository localQueueRepository,
    required Connectivity connectivity,
  })  : _attendanceRepository = attendanceRepository,
        _localQueueRepository = localQueueRepository,
        _connectivity = connectivity;

  final AttendanceRepository _attendanceRepository;
  final LocalQueueRepository _localQueueRepository;
  final Connectivity _connectivity;
  StreamSubscription<dynamic>? _subscription;

  void start() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      flushPending();
    });
  }

  Future<void> flushPending() async {
    final pending = await _localQueueRepository.pendingEvents();
    if (pending.isEmpty) {
      return;
    }

    try {
      await _attendanceRepository.bulkSync(pending);
      for (final AttendanceEvent event in pending) {
        await _localQueueRepository.markSyncedByEventUuid(event.eventUuid);
      }
    } catch (_) {
      // Intentionally silent for kiosk mode. UI reads pending counts for status.
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
