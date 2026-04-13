import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/models/recognition_event.dart';

/// Renders a Face ID–style bounding overlay on top of the camera preview.
///
/// Features:
/// - Smooth real-time bounding box tracking (Ticker-driven lerp at 60 fps)
/// - Animated vertical scan line while searching
/// - Corner brackets (not a full box) for a clean look
/// - Cyan when no match, green when a student is identified
/// - Pulse flash on successful attendance mark
/// - Fades out when no face is detected
class RecognitionOverlay extends StatefulWidget {
  const RecognitionOverlay({super.key, required this.event});

  final RecognitionEvent? event;

  @override
  State<RecognitionOverlay> createState() => _RecognitionOverlayState();
}

class _RecognitionOverlayState extends State<RecognitionOverlay> with TickerProviderStateMixin {
  // Smoothed box in normalized [0, 1] coords (top-left origin).
  double _cx = 0.25, _cy = 0.25, _cw = 0.50, _ch = 0.50;
  // Target from latest event.
  double _tx = 0.25, _ty = 0.25, _tw = 0.50, _th = 0.50;

  bool _hasFace = false;
  double _visibility = 0.0; // 0.0 = fully hidden, 1.0 = fully visible

  late final AnimationController _scanController;   // drives scan line
  late final AnimationController _pulseController;  // match flash
  late final Ticker _smoothTicker;                  // box lerp + visibility

  String? _lastMatchedId;

  @override
  void initState() {
    super.initState();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _smoothTicker = createTicker((_) {
      if (!mounted) return;
      setState(() {
        // Lerp box towards target
        const k = 0.22;
        _cx += (_tx - _cx) * k;
        _cy += (_ty - _cy) * k;
        _cw += (_tw - _cw) * k;
        _ch += (_th - _ch) * k;

        // Fade visibility
        final targetVisibility = _hasFace ? 1.0 : 0.0;
        _visibility += (targetVisibility - _visibility) * 0.12;
      });
    })..start();
  }

  @override
  void didUpdateWidget(RecognitionOverlay old) {
    super.didUpdateWidget(old);
    final box = widget.event?.faceBox;
    _hasFace = box != null;
    if (box != null) {
      _tx = (box['x'] as num? ?? _tx).toDouble();
      _ty = (box['y'] as num? ?? _ty).toDouble();
      _tw = (box['w'] as num? ?? _tw).toDouble();
      _th = (box['h'] as num? ?? _th).toDouble();
    }

    // Trigger pulse on new match
    final newMatch = widget.event?.matchedStudentId;
    if (newMatch != null && newMatch != _lastMatchedId) {
      _pulseController.forward(from: 0);
    }
    _lastMatchedId = newMatch;
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pulseController.dispose();
    _smoothTicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_visibility < 0.02) return const SizedBox.shrink();

    final event = widget.event;
    final hasMatch = event?.matchedStudentId != null;

    return LayoutBuilder(builder: (context, constraints) {
      final W = constraints.maxWidth;
      final H = constraints.maxHeight;

      return AnimatedBuilder(
        animation: Listenable.merge([_scanController, _pulseController]),
        builder: (context, _) {
          return CustomPaint(
            size: Size(W, H),
            painter: _FaceIdPainter(
              x: _cx * W,
              y: _cy * H,
              w: _cw * W,
              h: _ch * H,
              hasMatch: hasMatch,
              scanProgress: _scanController.value,
              pulseProgress: _pulseController.value,
              alpha: _visibility.clamp(0.0, 1.0),
            ),
          );
        },
      );
    });
  }
}

class _FaceIdPainter extends CustomPainter {
  const _FaceIdPainter({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.hasMatch,
    required this.scanProgress,
    required this.pulseProgress,
    required this.alpha,
  });

  final double x, y, w, h;
  final bool hasMatch;
  final double scanProgress;
  final double pulseProgress;
  final double alpha;

  static const _bracketRatio = 0.22;
  static const _lineWidth = 2.5;

  Color get _baseColor => hasMatch ? const Color(0xFF00E676) : const Color(0xFF00E5FF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(x, y, w, h);
    final bracketLen = math.min(w, h) * _bracketRatio;
    final opacity = alpha;

    // ── Corner brackets ─────────────────────────────────────────────────────
    final bracketPaint = Paint()
      ..color = _baseColor.withValues(alpha: opacity * 0.92)
      ..strokeWidth = _lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawBrackets(canvas, rect, bracketLen, bracketPaint);

    // ── Scan line (only while searching, fade out on match) ─────────────────
    if (!hasMatch) {
      final scanY = rect.top + rect.height * scanProgress;
      final scanAlpha = opacity * 0.65;
      final scanPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            _baseColor.withValues(alpha: scanAlpha),
            _baseColor.withValues(alpha: scanAlpha),
            Colors.transparent,
          ],
          stops: const [0.0, 0.25, 0.75, 1.0],
        ).createShader(Rect.fromLTWH(rect.left, scanY - 1, rect.width, 2))
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(rect.left, scanY - 1, rect.width, 2), scanPaint);
    }

    // ── Pulse on successful match ────────────────────────────────────────────
    if (pulseProgress > 0) {
      final expand = pulseProgress * 24;
      final fillAlpha = (1.0 - pulseProgress) * 0.30 * opacity;
      final outlineAlpha = (1.0 - pulseProgress) * 0.70 * opacity;

      final fillPaint = Paint()
        ..color = const Color(0xFF00E676).withValues(alpha: fillAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(expand), const Radius.circular(8)),
        fillPaint,
      );

      final outlinePaint = Paint()
        ..color = const Color(0xFF00E676).withValues(alpha: outlineAlpha)
        ..strokeWidth = _lineWidth
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(expand), const Radius.circular(8)),
        outlinePaint,
      );
    }
  }

  void _drawBrackets(Canvas canvas, Rect rect, double len, Paint paint) {
    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(len, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, len), paint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight.translate(-len, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, len), paint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(len, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(0, -len), paint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(-len, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(0, -len), paint);
  }

  @override
  bool shouldRepaint(_FaceIdPainter old) =>
      x != old.x ||
      y != old.y ||
      w != old.w ||
      h != old.h ||
      hasMatch != old.hasMatch ||
      scanProgress != old.scanProgress ||
      pulseProgress != old.pulseProgress ||
      alpha != old.alpha;
}
