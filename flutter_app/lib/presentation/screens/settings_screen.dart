import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/attendance_thresholds.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thresholds = ref.watch(attendanceThresholdsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SliderTile(
            label: 'Auto mark threshold',
            value: thresholds.autoMarkThreshold,
            min: 0.5,
            max: 0.95,
            onChanged: (value) => _update(ref, thresholds.copyWith(autoMarkThreshold: value)),
          ),
          _SliderTile(
            label: 'Review threshold',
            value: thresholds.reviewThreshold,
            min: 0.4,
            max: 0.9,
            onChanged: (value) => _update(ref, thresholds.copyWith(reviewThreshold: value)),
          ),
          _SliderTile(
            label: 'Consecutive frames',
            value: thresholds.consecutiveFramesRequired.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            onChanged: (value) => _update(ref, thresholds.copyWith(consecutiveFramesRequired: value.toInt())),
          ),
          _SliderTile(
            label: 'Student cooldown (s)',
            value: thresholds.studentCooldownSeconds.toDouble(),
            min: 30,
            max: 900,
            divisions: 29,
            onChanged: (value) => _update(ref, thresholds.copyWith(studentCooldownSeconds: value.toInt())),
          ),
          _SliderTile(
            label: 'Min face size ratio',
            value: thresholds.minFaceSizeRatio,
            min: 0.03,
            max: 0.3,
            onChanged: (value) => _update(ref, thresholds.copyWith(minFaceSizeRatio: value)),
          ),
          _SliderTile(
            label: 'Min blur score',
            value: thresholds.minBlurScore,
            min: 10,
            max: 250,
            onChanged: (value) => _update(ref, thresholds.copyWith(minBlurScore: value)),
          ),
          SwitchListTile(
            title: const Text('Debug mode'),
            value: thresholds.debugMode,
            onChanged: (value) => _update(ref, thresholds.copyWith(debugMode: value)),
          ),
        ],
      ),
    );
  }

  void _update(WidgetRef ref, AttendanceThresholds thresholds) {
    ref.read(kioskControllerProvider.notifier).updateThresholds(thresholds);
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(2),
              onChanged: onChanged,
            ),
            Text(value.toStringAsFixed(2)),
          ],
        ),
      ),
    );
  }
}
