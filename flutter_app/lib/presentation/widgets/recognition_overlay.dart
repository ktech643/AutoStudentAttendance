import 'package:flutter/material.dart';

import '../../core/models/recognition_event.dart';

class RecognitionOverlay extends StatelessWidget {
  const RecognitionOverlay({
    super.key,
    required this.event,
  });

  final RecognitionEvent? event;

  @override
  Widget build(BuildContext context) {
    if (event == null || event!.faceBox == null) {
      return const SizedBox.shrink();
    }

    final faceBox = event!.faceBox!;
    final left = (faceBox['x'] as num? ?? 0).toDouble();
    final top = (faceBox['y'] as num? ?? 0).toDouble();
    final width = (faceBox['w'] as num? ?? 0.2).toDouble();
    final height = (faceBox['h'] as num? ?? 0.2).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned(
              left: constraints.maxWidth * left,
              top: constraints.maxHeight * top,
              width: constraints.maxWidth * width,
              height: constraints.maxHeight * height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: event!.matchedStudentId == null ? Colors.orangeAccent : Colors.greenAccent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
