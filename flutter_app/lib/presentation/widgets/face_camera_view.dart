import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Live camera preview for iOS, Android, and web. Disposes the controller when disposed.
///
/// [onReady] is called once when preview is usable, or with null on failure after [retry].
class FaceCameraView extends StatefulWidget {
  const FaceCameraView({
    super.key,
    required this.onReady,
    this.preferredLens = CameraLensDirection.front,
  });

  /// Invoked with controller when initialized, or null if unavailable / error.
  final ValueChanged<CameraController?> onReady;

  /// Prefer front (selfie) when available — good for enrollment / kiosk.
  final CameraLensDirection preferredLens;

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

class _FaceCameraViewState extends State<FaceCameraView> {
  CameraController? _controller;
  bool _loading = true;
  String? _error;
  int _retryToken = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = ++_retryToken;
    setState(() {
      _loading = true;
      _error = null;
    });

    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    if (!mounted || token != _retryToken) {
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted || token != _retryToken) {
          return;
        }
        setState(() {
          _loading = false;
          _error = 'No camera found';
        });
        widget.onReady(null);
        return;
      }

      CameraDescription picked;
      try {
        picked = cameras.firstWhere((c) => c.lensDirection == widget.preferredLens);
      } catch (_) {
        picked = cameras.first;
      }

      final controller = CameraController(
        picked,
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted || token != _retryToken) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
      widget.onReady(controller);
    } catch (e, st) {
      debugPrint('FaceCameraView init failed: $e\n$st');
      if (!mounted || token != _retryToken) {
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      widget.onReady(null);
    }
  }

  @override
  void dispose() {
    _retryToken++;
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  void _retry() {
    _init();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final c = _controller;
    if (_error != null || c == null || !c.value.isInitialized) {
      return ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, size: 48, color: Colors.white54),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Camera unavailable',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry camera'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: CameraPreview(c),
        ),
      ),
    );
  }
}
