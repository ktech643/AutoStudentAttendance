import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/attendance_thresholds.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(attendanceThresholdsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recognition Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _sectionHeader(context, 'Match Thresholds'),
          _SliderTile(
            label: 'Auto-mark threshold',
            description:
                'Minimum confidence score (0–1) required to automatically '
                'record attendance without any human review.  Higher values '
                'reduce false positives but may miss some genuine matches.',
            value: t.autoMarkThreshold,
            displayFormat: (v) => '${(v * 100).toStringAsFixed(0)} %',
            min: 0.5,
            max: 0.99,
            onChanged: (v) => _update(ref, t.copyWith(autoMarkThreshold: v)),
          ),
          _SliderTile(
            label: 'Review threshold',
            description:
                'If a match falls between this value and the auto-mark '
                'threshold, a review entry is created instead of auto-marking.  '
                'Faces below this score are ignored entirely.',
            value: t.reviewThreshold,
            displayFormat: (v) => '${(v * 100).toStringAsFixed(0)} %',
            min: 0.3,
            max: 0.9,
            onChanged: (v) => _update(ref, t.copyWith(reviewThreshold: v)),
          ),
          _sectionHeader(context, 'Stability & Cooldowns'),
          _SliderTile(
            label: 'Consecutive frames required',
            description:
                'Number of consecutive video frames that must all match the '
                'same student before attendance is recorded.  Higher values '
                'prevent accidental marks from a single good frame.',
            value: t.consecutiveFramesRequired.toDouble(),
            displayFormat: (v) => '${v.toInt()} frame${v >= 2 ? "s" : ""}',
            min: 1,
            max: 6,
            divisions: 5,
            onChanged: (v) =>
                _update(ref, t.copyWith(consecutiveFramesRequired: v.toInt())),
          ),
          _SliderTile(
            label: 'Student cooldown',
            description:
                'Once a student\'s attendance is recorded the system will '
                'ignore further matches for this many seconds.  This prevents '
                'the same person from being marked multiple times in a single '
                'session (e.g., while they walk past the kiosk).',
            value: t.studentCooldownSeconds.toDouble(),
            displayFormat: (v) {
              final mins = (v / 60).floor();
              final secs = (v % 60).round();
              return mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
            },
            min: 30,
            max: 900,
            divisions: 29,
            onChanged: (v) =>
                _update(ref, t.copyWith(studentCooldownSeconds: v.toInt())),
          ),
          _sectionHeader(context, 'Image Quality Gates'),
          _SliderTile(
            label: 'Minimum face size',
            description:
                'How large the detected face must be relative to the full '
                'camera frame (0 = any size, 1 = full frame).  Increase this '
                'to reject faces that are too far away from the camera.',
            value: t.minFaceSizeRatio,
            displayFormat: (v) => '${(v * 100).toStringAsFixed(0)} %',
            min: 0.03,
            max: 0.4,
            onChanged: (v) => _update(ref, t.copyWith(minFaceSizeRatio: v)),
          ),
          _SliderTile(
            label: 'Minimum sharpness (blur score)',
            description:
                'Frames sharper than this Laplacian variance score pass the '
                'quality gate.  Lower values accept blurry images; higher '
                'values demand a crisp, in-focus face before attempting '
                'recognition.',
            value: t.minBlurScore,
            displayFormat: (v) => v.toStringAsFixed(0),
            min: 10,
            max: 300,
            onChanged: (v) => _update(ref, t.copyWith(minBlurScore: v)),
          ),
          _sectionHeader(context, 'Developer'),
          _SwitchTile(
            label: 'Debug mode',
            description:
                'Overlays real-time recognition data on the kiosk preview: '
                'track IDs, similarity scores, quality metrics, and per-frame '
                'decision reasons.  Turn off in production.',
            value: t.debugMode,
            onChanged: (v) => _update(ref, t.copyWith(debugMode: v)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4, left: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  void _update(WidgetRef ref, AttendanceThresholds thresholds) {
    ref.read(kioskControllerProvider.notifier).updateThresholds(thresholds);
  }
}

// ---------------------------------------------------------------------------

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.displayFormat,
    this.divisions,
  });

  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) displayFormat;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    displayFormat(clamped),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    height: 1.4,
                  ),
            ),
            Slider(
              value: clamped,
              min: min,
              max: max,
              divisions: divisions,
              label: displayFormat(clamped),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
