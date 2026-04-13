import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ios_face_attendance_plugin/ios_native_plugin.dart';

import '../../data/services/docker_recognition_source.dart';
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

    // Show a SnackBar toast whenever attendance is auto-marked.
    ref.listen<KioskState>(kioskControllerProvider, (previous, next) {
      if (next.markedToast != null &&
          next.markedToast != previous?.markedToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.markedToast!),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        // Clear immediately so it doesn't retrigger on rebuilds.
        controller.clearMarkedToast();
      }
    });

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

class _KioskPreviewStack extends ConsumerStatefulWidget {
  const _KioskPreviewStack({
    required this.kioskState,
    required this.cameraMountId,
    required this.onCameraReady,
  });

  final KioskState kioskState;
  final int cameraMountId;
  final ValueChanged<bool> onCameraReady;

  @override
  ConsumerState<_KioskPreviewStack> createState() => _KioskPreviewStackState();
}

class _KioskPreviewStackState extends ConsumerState<_KioskPreviewStack> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final isDocker = ref.watch(isDockerBackendProvider).valueOrNull ?? false;
    final source = ref.watch(recognitionSourceProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera preview ─────────────────────────────────────────────────
        if (isDocker && source is DockerRecognitionSource)
          // Docker: preview comes from the source's own camera session.
          // Using FaceCameraView here would open a second session → blank preview.
          _DockerCameraPreview(
            source: source,
            onReady: widget.onCameraReady,
          )
        else if (!config.simulatedRecognition &&
            defaultTargetPlatform == TargetPlatform.iOS)
          // Native iOS plugin owns the session — render via PlatformView.
          const NativeCameraPreview()
        else
          // Simulated / web — Flutter camera package.
          FaceCameraView(
            key: ValueKey<int>(widget.cameraMountId),
            onReady: (c) {
              widget.onCameraReady(c != null && c.value.isInitialized);
            },
          ),

        // ── Overlays ───────────────────────────────────────────────────────
        RecognitionOverlay(event: widget.kioskState.latestRecognition),
        Positioned(
          top: 12,
          left: 12,
          right: widget.kioskState.attendanceBannerName != null ? 220 : 12,
          child: _StatusBar(kioskState: widget.kioskState),
        ),
        if (widget.kioskState.attendanceBannerName != null)
          Positioned(
            top: 12,
            right: 12,
            width: 200,
            child: _AttendanceMarkBanner(kioskState: widget.kioskState),
          ),
      ],
    );
  }
}

/// Shows the camera preview from [DockerRecognitionSource.cameraNotifier].
/// Listens to the ValueNotifier so it rebuilds once the camera is initialised.
class _DockerCameraPreview extends StatefulWidget {
  const _DockerCameraPreview({
    required this.source,
    required this.onReady,
  });

  final DockerRecognitionSource source;
  final ValueChanged<bool> onReady;

  @override
  State<_DockerCameraPreview> createState() => _DockerCameraPreviewState();
}

class _DockerCameraPreviewState extends State<_DockerCameraPreview> {
  CameraController? _ctrl;

  @override
  void initState() {
    super.initState();
    widget.source.cameraNotifier.addListener(_onCameraChanged);
    // Might already be ready if start() was called before we mounted.
    _ctrl = widget.source.cameraNotifier.value;
    if (_ctrl != null) widget.onReady(true);
  }

  void _onCameraChanged() {
    if (!mounted) return;
    setState(() => _ctrl = widget.source.cameraNotifier.value);
    widget.onReady(_ctrl != null);
  }

  @override
  void dispose() {
    widget.source.cameraNotifier.removeListener(_onCameraChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white38),
              SizedBox(height: 12),
              Text('Starting camera…',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Fill without stretching — swap w/h because iOS previewSize is landscape.
    final ps = ctrl.value.previewSize;
    if (ps == null) return const ColoredBox(color: Colors.black);

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: ps.height,  // portrait: swap landscape dimensions
          height: ps.width,
          child: CameraPreview(ctrl),
        ),
      ),
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
