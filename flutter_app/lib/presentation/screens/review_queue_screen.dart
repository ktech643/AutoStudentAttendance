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
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider).dio;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Queue')),
      body: FutureBuilder<List<UnknownFaceReview>>(
        future: _load(api),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No pending review items'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reason: ${item.reason}'),
                      const SizedBox(height: 6),
                      Text('Candidates: ${item.topCandidates.map((e) => '${e.studentName} ${(e.similarity * 100).toStringAsFixed(0)}%').join(', ')}'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () async {
                              if (item.topCandidates.isEmpty) {
                                return;
                              }
                              await api.post(
                                '/review-queue/${item.id}/approve',
                                data: {
                                  'student_id': item.topCandidates.first.studentId,
                                },
                              );
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            child: const Text('Approve top match'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await api.post(
                                '/review-queue/${item.id}/reject',
                                data: {
                                  'reason': 'rejected by operator',
                                },
                              );
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<UnknownFaceReview>> _load(Dio api) async {
    final response = await api.get<List<dynamic>>('/review-queue');
    return response.data!
        .whereType<Map<String, dynamic>>()
        .map(UnknownFaceReview.fromJson)
        .toList(growable: false);
  }
}
