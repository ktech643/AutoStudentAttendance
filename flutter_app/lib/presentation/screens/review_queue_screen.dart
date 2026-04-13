import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/unknown_face_review.dart';
import '../providers/providers.dart';

class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  late Future<List<UnknownFaceReview>> _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final api = ref.read(apiClientProvider).dio;
    setState(() {
      _future = _load(api);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<List<UnknownFaceReview>>(
        future: _future,
        builder: (context, snapshot) {
          // Error state — covers 404 (Docker), network errors, etc.
          if (snapshot.hasError) {
            final err = snapshot.error;
            final isNotFound =
                err is DioException && err.response?.statusCode == 404;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isNotFound
                        ? Icons.inbox_outlined
                        : Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isNotFound
                        ? 'Review queue not available'
                        : 'Could not load review queue',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isNotFound
                        ? 'This backend does not support a review queue.\nLow-confidence matches are handled automatically.'
                        : snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                    onPressed: _refresh,
                  ),
                ],
              ),
            );
          }

          // Loading state.
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data!;
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Colors.green.shade400),
                  const SizedBox(height: 16),
                  Text('All clear — no pending reviews',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Borderline-confidence recognitions will appear here\nfor manual approval.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) => _ReviewCard(
                item: items[index],
                onAction: _refresh,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<List<UnknownFaceReview>> _load(Dio api) async {
    final response = await api.get<List<dynamic>>('/review-queue');
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(UnknownFaceReview.fromJson)
        .toList(growable: false);
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item, required this.onAction});

  final UnknownFaceReview item;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final api = ProviderScope.containerOf(context, listen: false)
        .read(apiClientProvider)
        .dio;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.face_retouching_natural, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reason: ${item.reason}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (item.topCandidates.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Top candidates:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              ...item.topCandidates.map((c) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(c.studentName)),
                        _ConfidenceBadge(similarity: c.similarity),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve top match'),
                    onPressed: item.topCandidates.isEmpty
                        ? null
                        : () async {
                            await api.post(
                              '/review-queue/${item.id}/approve',
                              data: {
                                'student_id':
                                    item.topCandidates.first.studentId,
                              },
                            );
                            onAction();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  onPressed: () async {
                    await api.post(
                      '/review-queue/${item.id}/reject',
                      data: {'reason': 'rejected by operator'},
                    );
                    onAction();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.similarity});
  final double similarity;

  @override
  Widget build(BuildContext context) {
    final pct = (similarity * 100).toStringAsFixed(0);
    final color = similarity >= 0.85
        ? Colors.green
        : similarity >= 0.70
            ? Colors.orange
            : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: color.shade700),
      ),
    );
  }
}
