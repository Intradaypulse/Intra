import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:document_scan/document_scan.dart';
import 'package:flutter/material.dart';

import 'manual_crop_screen.dart';

class LiveScannerScreen extends StatefulWidget {
  const LiveScannerScreen({super.key});

  @override
  State<LiveScannerScreen> createState() => _LiveScannerScreenState();
}

class _LiveScannerScreenState extends State<LiveScannerScreen>
    with WidgetsBindingObserver {
  final _detector = DocumentDetector();
  final _analyzer = AutoCaptureAnalyzer();

  CameraController? _controller;
  StreamController<ScanInput>? _frames;
  StreamSubscription<DetectionEvent>? _detectionSub;

  late final ScanImageFormat _frameFormat = Platform.isIOS
      ? ScanImageFormat.bgra8888
      : ScanImageFormat.yuv420;

  DocumentCorners? _corners;
  AutoCaptureStatus _captureStatus = AutoCaptureStatus.searching;
  final List<Uint8List> _pages = [];

  bool _starting = false;
  bool _capturing = false;
  bool _autoCapture = true;
  bool _torch = false;
  bool _ready = false;
  String _hint = 'Starting camera…';
  String? _error;
  double? _detectAspect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    if (_controller != null || _starting) return;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No camera available.');
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _controller = controller;
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _resumeStream(controller);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _hint = 'Point at a document';
      });
    } on CameraException catch (e) {
      _fail('Camera unavailable: ${e.description ?? e.code}');
    } catch (e) {
      _fail('Could not start camera: $e');
    } finally {
      _starting = false;
    }
  }

  void _fail(String value) {
    if (!mounted) return;
    setState(() {
      _ready = false;
      _error = value;
      _hint = value;
    });
  }

  ScanInput? _toScanInput(CameraImage image, int rotation) {
    if (image.planes.isEmpty) return null;

    if (_frameFormat == ScanImageFormat.bgra8888) {
      final plane = image.planes.first;
      return ScanInput.bgraFrame(
        width: image.width,
        height: image.height,
        rotation: rotation,
        bytes: plane.bytes,
        bytesPerRow: plane.bytesPerRow,
      );
    }

    if (image.planes.length < 3) return null;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];

    return ScanInput.yuvFrame(
      width: image.width,
      height: image.height,
      rotation: rotation,
      yBytes: y.bytes,
      uBytes: u.bytes,
      vBytes: v.bytes,
      yRowStride: y.bytesPerRow,
      uvRowStride: u.bytesPerRow,
      uvPixelStride: u.bytesPerPixel ?? 1,
    );
  }

  void _onDetection(DetectionEvent event) {
    if (!mounted || _capturing) return;

    final state = _analyzer.addEvent(event);
    _captureStatus = state.status;

    switch (event) {
      case DetectionSuccess(:final corners):
        setState(() {
          _corners = corners;
          _error = null;
          _hint = state.shouldCapture
              ? 'Ready'
              : 'Document detected — hold steady';
        });
      case DetectionEmpty():
        setState(() {
          _corners = null;
          _error = null;
          _hint = 'Point at a document';
        });
      case DetectionSkipped():
        if (mounted) setState(() {});
      case DetectionError(:final error):
        setState(() => _error = 'Detection error: $error');
    }

    if (state.shouldCapture && _autoCapture && !_capturing) {
      unawaited(_captureStill());
    }
  }

  Future<void> _resumeStream(CameraController controller) async {
    final frames = StreamController<ScanInput>();
    _frames = frames;

    _detectionSub = _detector
        .detectStream(
          frames.stream,
          stabilize: CornerStabilizer(
            smoothing: 0.45,
            resetDistance: 0.16,
          ),
          minInterval: const Duration(milliseconds: 100),
          sensitivity: DetectionSensitivity.strict,
        )
        .listen(_onDetection);

    final rotation =
        Platform.isIOS ? 0 : controller.description.sensorOrientation;

    await controller.startImageStream((image) {
      if (!mounted || frames.isClosed || _capturing) return;

      if (_detectAspect == null) {
        final upright = rotation == 90 || rotation == 270;
        final width = (upright ? image.height : image.width).toDouble();
        final height = (upright ? image.width : image.height).toDouble();
        if (height > 0 && mounted) {
          setState(() => _detectAspect = width / height);
        }
      }

      final input = _toScanInput(image, rotation);
      if (input != null) frames.add(input);
    });
  }

  Future<void> _pauseStream() async {
    await _detectionSub?.cancel();
    _detectionSub = null;
    await _frames?.close();
    _frames = null;

    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _captureStill() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }

    _capturing = true;
    if (mounted) {
      setState(() {
        _corners = null;
        _hint = 'Capturing…';
      });
    }

    try {
      await _pauseStream();
      final photo = await controller.takePicture();

      final detected = await _detector.detect(
        ScanInput.file(photo.path),
        sensitivity: DetectionSensitivity.lenient,
      );

      if (!mounted) return;
      final result = await Navigator.of(context).push<ManualCropResult>(
        MaterialPageRoute(
          builder: (_) => ManualCropScreen(
            imagePath: photo.path,
            initialCorners: detected,
          ),
        ),
      );

      if (result != null && mounted) {
        setState(() {
          _pages.add(result.bytes);
          _hint = 'Page ${_pages.length} added';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Capture failed: $e');
    } finally {
      _analyzer.reset();
      _capturing = false;
      final current = _controller;
      if (mounted &&
          current != null &&
          current.value.isInitialized &&
          !current.value.isStreamingImages) {
        try {
          await _resumeStream(current);
        } catch (e) {
          if (mounted) setState(() => _error = 'Camera restart failed: $e');
        }
      }
      if (mounted) {
        setState(() {
          _captureStatus = AutoCaptureStatus.searching;
          _hint = 'Point at a document';
        });
      }
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = !_torch;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = next);
    } catch (_) {}
  }

  void _finish() {
    if (_pages.isEmpty) {
      Navigator.of(context).pop<List<Uint8List>>();
    } else {
      Navigator.of(context).pop<List<Uint8List>>(List.of(_pages));
    }
  }

  Future<void> _teardown() async {
    final controller = _controller;
    _controller = null;
    try {
      await _pauseStream();
    } catch (_) {}
    try {
      await controller?.dispose();
    } catch (_) {}
    if (mounted) setState(() => _ready = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_teardown());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _pages.isEmpty ? 'Scan document' : '${_pages.length} page(s)',
        ),
        actions: [
          IconButton(
            tooltip: 'Torch',
            onPressed: _ready ? _toggleTorch : null,
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Auto'),
              Switch(
                value: _autoCapture,
                onChanged: _capturing
                    ? null
                    : (value) {
                        setState(() {
                          _autoCapture = value;
                          _analyzer.reset();
                          _captureStatus = AutoCaptureStatus.searching;
                        });
                      },
              ),
            ],
          ),
          TextButton(
            onPressed: _pages.isEmpty ? null : _finish,
            child: const Text('Done'),
          ),
        ],
      ),
      body: !_ready || controller == null || !controller.value.isInitialized
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? _hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio:
                          _detectAspect ?? (1 / controller.value.aspectRatio),
                      child: CameraPreview(
                        controller,
                        child: CustomPaint(
                          painter: _LiveDocumentPainter(_corners),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 14,
                                left: 14,
                                right: 14,
                                child: _StatusChip(
                                  status: _captureStatus,
                                  message: _error ?? _hint,
                                ),
                              ),
                              Positioned(
                                bottom: 18,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: FloatingActionButton.large(
                                    heroTag: 'scanner_shutter',
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    onPressed:
                                        _capturing ? null : _captureStill,
                                    child: const Icon(Icons.camera_alt_rounded),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_pages.isNotEmpty)
                  Container(
                    height: 112,
                    color: const Color(0xFF101010),
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      itemCount: _pages.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final page = _pages.removeAt(oldIndex);
                          _pages.insert(newIndex, page);
                        });
                      },
                      itemBuilder: (context, index) {
                        return Container(
                          key: ValueKey(_pages[index]),
                          width: 82,
                          margin: const EdgeInsets.only(right: 8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _pages[index],
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Material(
                                  color: Colors.black54,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () =>
                                        setState(() => _pages.removeAt(index)),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 5,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _LiveDocumentPainter extends CustomPainter {
  const _LiveDocumentPainter(this.corners);

  final DocumentCorners? corners;

  @override
  void paint(Canvas canvas, Size size) {
    final c = corners;
    if (c == null) return;

    Offset point(({double x, double y}) p) =>
        Offset(p.x * size.width, p.y * size.height);

    final tl = point(c.topLeft);
    final tr = point(c.topRight);
    final br = point(c.bottomRight);
    final bl = point(c.bottomLeft);

    final path = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x334DFF88)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4DFF88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    for (final p in [tl, tr, br, bl]) {
      canvas.drawCircle(p, 6, Paint()..color = Colors.white);
      canvas.drawCircle(p, 4, Paint()..color = const Color(0xFF4DFF88));
    }
  }

  @override
  bool shouldRepaint(covariant _LiveDocumentPainter oldDelegate) =>
      oldDelegate.corners != corners;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.message,
  });

  final AutoCaptureStatus status;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      AutoCaptureStatus.searching => Colors.black54,
      AutoCaptureStatus.detecting => Colors.orange.shade800,
      AutoCaptureStatus.ready => Colors.green.shade700,
    };

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
