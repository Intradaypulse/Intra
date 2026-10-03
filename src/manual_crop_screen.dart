import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_scan/document_scan.dart';
import 'package:flutter/material.dart';

import 'draggable_corner_overlay.dart';
import 'crop_geometry.dart';

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
    topLeft: (x: 0, y: 0),
    topRight: (x: 1, y: 0),
    bottomRight: (x: 1, y: 1),
    bottomLeft: (x: 0, y: 1),
  );

  DocumentCorners? _corners;
  Size? _imageSize;
  bool _busy = true;
  String? _error;
  int? _activeCorner;
  ScanFilter _filter = ScanFilter.enhance;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare({bool redetect = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final size = await _decodeSize(widget.imagePath);
      if (size == null) throw StateError('The photo could not be opened.');
      final detected =
          (redetect ? null : widget.initialCorners) ??
          await _detector.detect(
            ScanInput.file(widget.imagePath),
            sensitivity: DetectionSensitivity.strict,
          );
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _corners = detected != null && validCropCorners(detected) ? detected : _fallback;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not prepare photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Size?> _decodeSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try { return Size(descriptor.width.toDouble(), descriptor.height.toDouble()); }
        finally { descriptor.dispose(); }
      } finally { buffer.dispose(); }

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
    if (_busy || corners == null) return;
    if (!validCropCorners(corners)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Keep corners in order and select a non-empty document area.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final scan = await _scanner.scan(
        ScanInput.file(widget.imagePath),
        corners: corners,
        filter: _filter,
        output: const ScanOutputFormat.jpegAt(96),
        maxDimension: 4096,
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
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not crop photo: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _cornerZoom(DocumentCorners corners, Size size) {
    final point = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft][_activeCorner!];
    return Positioned(
      top: 12, left: point.x > .5 ? 12 : null, right: point.x <= .5 ? 12 : null,
      child: IgnorePointer(child: Container(
        width: 132, height: 132,
        decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3),
          borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(blurRadius: 8)]),
        child: ClipRRect(borderRadius: BorderRadius.circular(13), child: Stack(children: [
          Positioned(left: 66 - point.x * 500, top: 66 - point.y * 500 * size.height / size.width,
            width: 500, height: 500 * size.height / size.width,
            child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 1600)),
          const Center(child: Icon(Icons.add, color: Colors.lightBlueAccent, size: 24)),
        ])),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    final corners = _corners;

    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(
        title: const Text('Adjust document'),
        actions: [
          TextButton(
            onPressed: _busy || _corners == null ? null : _confirm,
            child: const Text('Use'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: _prepare,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : _busy || size == null || corners == null
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                        aspectRatio: size.width / size.height,
                        child: SizedBox(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.fill,
                                cacheWidth: 1600,
                              ),
                              DraggableCornerOverlay(
                                corners: corners,
                                onCornerMoved: _moveCorner,
                                onActiveCornerChanged: (index) => setState(() => _activeCorner = index),
                              ),
                              if (_activeCorner != null)
                                _cornerZoom(corners, size),
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
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton(onPressed: () => _prepare(redetect: true), child: const Text('Detect again')),
                      TextButton(onPressed: () => setState(() => _corners = const DocumentCorners(
                        topLeft: (x: 0, y: 0), topRight: (x: 1, y: 0),
                        bottomRight: (x: 1, y: 1), bottomLeft: (x: 0, y: 1))),
                        child: const Text('Full photo')),
                    ]),
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
    ));
  }
}
