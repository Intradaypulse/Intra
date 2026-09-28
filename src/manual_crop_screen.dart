import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_scan/document_scan.dart';
import 'package:flutter/material.dart';

import 'draggable_corner_overlay.dart';

class ManualCropResult {
  const ManualCropResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

class ManualCropScreen extends StatefulWidget {
  const ManualCropScreen({
    super.key,
    required this.imagePath,
    this.initialCorners,
  });

  final String imagePath;
  final DocumentCorners? initialCorners;

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  final _detector = DocumentDetector();
  final _scanner = DocumentScanner();

  static const _fallback = DocumentCorners(
    topLeft: (x: 0.08, y: 0.08),
    topRight: (x: 0.92, y: 0.08),
    bottomRight: (x: 0.92, y: 0.92),
    bottomLeft: (x: 0.08, y: 0.92),
  );

  DocumentCorners? _corners;
  Size? _imageSize;
  bool _busy = true;
  ScanFilter _filter = ScanFilter.enhance;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final size = await _decodeSize(widget.imagePath);
    final detected = widget.initialCorners ??
        await _detector.detect(
          ScanInput.file(widget.imagePath),
          sensitivity: DetectionSensitivity.lenient,
        );
    if (!mounted) return;
    setState(() {
      _imageSize = size;
      _corners = detected ?? _fallback;
      _busy = false;
    });
  }

  Future<Size?> _decodeSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  void _moveCorner(int index, ({double x, double y}) point) {
    final c = _corners;
    if (c == null) return;
    setState(() {
      _corners = switch (index) {
        0 => c.copyWith(topLeft: point),
        1 => c.copyWith(topRight: point),
        2 => c.copyWith(bottomRight: point),
        _ => c.copyWith(bottomLeft: point),
      };
    });
  }

  Future<void> _confirm() async {
    final corners = _corners;
    if (corners == null) return;
    setState(() => _busy = true);
    try {
      final scan = await _scanner.scan(
        ScanInput.file(widget.imagePath),
        corners: corners,
        filter: _filter,
        output: const ScanOutputFormat.jpegAt(88),
      );
      if (!mounted) return;
      if (scan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not crop this page.')),
        );
        return;
      }
      Navigator.of(context).pop(
        ManualCropResult(
          bytes: scan.bytes,
          width: scan.width,
          height: scan.height,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    final corners = _corners;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust document'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _confirm,
            child: const Text('Use'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _busy || size == null || corners == null
                    ? const CircularProgressIndicator()
                    : FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.fill,
                              ),
                              DraggableCornerOverlay(
                                corners: corners,
                                onCornerMoved: _moveCorner,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (!_busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    const Text(
                      'Drag the 4 handles if auto-detection is not exact.',
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<ScanFilter>(
                      segments: const [
                        ButtonSegment(
                          value: ScanFilter.enhance,
                          label: Text('Enhance'),
                        ),
                        ButtonSegment(
                          value: ScanFilter.blackWhite,
                          label: Text('B&W'),
                        ),
                        ButtonSegment(
                          value: ScanFilter.magicColor,
                          label: Text('Color'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (value) =>
                          setState(() => _filter = value.first),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
