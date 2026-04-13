import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ios_face_attendance_plugin/ios_native_plugin.dart';

import '../providers/providers.dart';
import '../providers/kiosk_state.dart';
import '../widgets/face_camera_view.dart';
import '../widgets/recognition_overlay.dart';

class AttendanceKioskScreen extends ConsumerStatefulWidget {
  const AttendanceKioskScreen({super.key});

  @override
  ConsumerState<AttendanceKioskScreen> createState() => _AttendanceKioskScreenState();
}

class _AttendanceKioskScreenState extends ConsumerState<AttendanceKioskScreen> {
  static int _mountSeq = 0;
  late final int _cameraMountId = ++_mountSeq;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final students = await ref.read(studentRepositoryProvider).fetchStudents();
        ref.read(simulatedStudentPoolProvider.notifier).state = students;
      } catch (_) {}
      if (!mounted) return;
      final config = ref.read(appConfigProvider);
      // In native mode the plugin owns the camera — mark it ready immediately.
      if (!config.simulatedRecognition && defaultTargetPlatform == TargetPlatform.iOS) {
        ref.read(kioskControllerProvider.notifier).reportCameraPreviewReady(true);
      }
      await ref.read(kioskControllerProvider.notifier).startRecognition();
    });
  }

  @override
  void dispose() {
    ref.read(kioskControllerProvider.notifier).stopRecognition();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kioskState = ref.watch(kioskControllerProvider);
    final controller = ref.read(kioskControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Kiosk'),
        actions: [
          IconButton(
            onPressed: controller.forceSync,
            icon: const Icon(Icons.sync),
            tooltip: 'Force sync',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 760;
          final preview = _KioskPreviewStack(
            kioskState: kioskState,
            cameraMountId: _cameraMountId,
            onCameraReady: (ready) {
              ref.read(kioskControllerProvider.notifier).reportCameraPreviewReady(ready);
            },
          );
          final sidePanel = _RecentPanel(kioskState: kioskState);

          if (narrow) {
            return Column(
              children: [
                SizedBox(height: constraints.maxHeight * 0.52, child: preview),
                const Divider(height: 1),
                Expanded(child: sidePanel),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: preview),
              Expanded(flex: 2, child: sidePanel),
            ],
          );
        },
      ),
    );
  }
}

class _KioskPreviewStack extends ConsumerWidget {
  const _KioskPreviewStack({
    required this.kioskState,
    required this.cameraMountId,
    required this.onCameraReady,
  });

  final KioskState kioskState;
  final int cameraMountId;
  final ValueChanged<bool> onCameraReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final isDocker = ref.watch(isDockerBackendProvider).valueOrNull ?? false;

    // Docker mode: DockerRecognitionSource owns the camera — show FaceCameraView
    //   (it starts its own session; the source's internal camera is separate).
    //   We show a plain black background with overlay; the Docker source captures
    //   frames independently.  On iOS with our native plugin, use NativeCameraPreview.
    final useNativePreview = !config.simulatedRecognition &&
        !isDocker &&
        defaultTargetPlatform == TargetPlatform.iOS;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (useNativePreview)
          const NativeCameraPreview()
        else if (isDocker)
          // Docker: show a camera preview using FaceCameraView while the source
          // captures frames independently in the background.
          FaceCameraView(
            key: ValueKey<int>(cameraMountId),
            onReady: (c) {
              onCameraReady(c != null && c.value.isInitialized);
            },
          )
        else
          FaceCameraView(
            key: ValueKey<int>(cameraMountId),
            onReady: (c) {
              onCameraReady(c != null && c.value.isInitialized);
            },
          ),
        RecognitionOverlay(event: kioskState.latestRecognition),
        Positioned(
          top: 12,
          left: 12,
          right: kioskState.attendanceBannerName != null ? 220 : 12,
          child: _StatusBar(kioskState: kioskState),
        ),
        if (kioskState.attendanceBannerName != null)
          Positioned(
            top: 12,
            right: 12,
            width: 200,
            child: _AttendanceMarkBanner(kioskState: kioskState),
          ),
      ],
    );
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.kioskState});

  final KioskState kioskState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('Recent attendance'),
          subtitle: Text('Pending queue: ${kioskState.pendingQueueCount}'),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: kioskState.recentAttendance.length,
            itemBuilder: (context, index) {
              final event = kioskState.recentAttendance[index];
              return ListTile(
                dense: true,
                title: Text(event.studentId ?? 'Unknown face'),
                subtitle: Text(DateFormat.Hms().format(event.timestamp.toLocal())),
                trailing: Text('${(event.confidence * 100).toStringAsFixed(0)}%'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AttendanceMarkBanner extends StatelessWidget {
  const _AttendanceMarkBanner({required this.kioskState});

  final KioskState kioskState;

  @override
  Widget build(BuildContext context) {
    final name = kioskState.attendanceBannerName ?? '';
    final roll = kioskState.attendanceBannerRoll;
    final status = kioskState.attendanceBannerStatus ?? '';

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Colors.green.shade900.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              status,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              'Roll: ${roll?.isNotEmpty == true ? roll : "—"}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.kioskState});

  final KioskState kioskState;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _chip('Network', kioskState.isOnline ? 'Online' : 'Offline', kioskState.isOnline ? Colors.green : Colors.orange),
        _chip('Camera', kioskState.cameraReady ? 'Ready' : 'Not ready', kioskState.cameraReady ? Colors.green : Colors.red),
        _chip('Recognition', kioskState.recognitionActive ? 'Active' : 'Paused', kioskState.recognitionActive ? Colors.green : Colors.orange),
        _chip('Frames', '${kioskState.framesProcessed}', Colors.blueGrey),
        _chip('Attempts', '${kioskState.recognitionAttempts}', Colors.blueGrey),
        _chip('Matches', '${kioskState.successfulMatches}', Colors.green),
        _chip('Quality rejects', '${kioskState.rejectedByQuality}', Colors.orange),
      ],
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: color.withValues(alpha: 0.2),
      side: BorderSide(color: color),
    );
  }
}
