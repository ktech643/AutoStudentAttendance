import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/attendance_event.dart';
import '../providers/providers.dart';

class AttendanceLogsScreen extends ConsumerStatefulWidget {
  const AttendanceLogsScreen({super.key});

  @override
  ConsumerState<AttendanceLogsScreen> createState() => _AttendanceLogsScreenState();
}

class _AttendanceLogsScreenState extends ConsumerState<AttendanceLogsScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(attendanceRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Logs'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download),
            label: const Text('Export (TODO)'),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            title: Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: _selectedDate,
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<AttendanceEvent>>(
              future: repository.fetchRecent(limit: 100),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final events = snapshot.data!;
                if (events.isEmpty) {
                  return const Center(child: Text('No attendance records'));
                }
                return ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final localTime = event.timestamp.toLocal();
                    return ListTile(
                      title: Text(event.studentId ?? 'Unknown'),
                      subtitle: Text('${DateFormat.yMMMd().add_Hms().format(localTime)} • ${event.reviewStatus}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SyncBadge(synced: event.synced),
                          Text('${(event.similarity * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.synced});

  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: synced ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: synced ? Colors.green : Colors.orange),
      ),
      child: Text(
        synced ? 'Synced' : 'Pending',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
