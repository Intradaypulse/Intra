import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'pdf_service.dart';
import 'signature_screen.dart';

class SignaturePlacementScreen extends StatefulWidget {
  const SignaturePlacementScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<SignaturePlacementScreen> createState() =>
      _SignaturePlacementScreenState();
}

class _SignaturePlacementScreenState extends State<SignaturePlacementScreen> {
  File? _source;
  Uint8List? _signature;
  List<Uint8List> _thumbs = [];
  List<PdfPageInfo> _pageInfos = [];
  Uint8List? _preview;
  int _page = 0;

  double _x = 0.54;
  double _y = 0.72;
  double _widthFraction = 0.32;
  double _rotationDegrees = 0;

  double _startWidth = 0.32;
  double _startRotation = 0;

  bool _busy = false;
  String _status = 'Choose a PDF and draw your signature.';

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('PDF password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _pickPdf() async {
    final previous = _source;
    final picked = await widget.service.pickPdfFile();
    if (picked != null && previous != null && previous.path != picked.path) {
      await widget.service.secureDeleteTemporary(previous);
    }
    if (picked == null) return;
    var file = picked;

    setState(() {
      _busy = true;
      _status = 'Loading PDF pages…';
      _thumbs = [];
      _pageInfos = [];
      _preview = null;
    });

    try {
      while (true) {
        try {
          _pageInfos = await widget.service.pageInfos(file);
          break;
        } on PdfPasswordRequired {
          if (!mounted) return;
          final password = await _askPassword();
          if (password == null) return;
          try {
            file = await widget.service.decryptToTemporary(file, password);
          } on PdfWrongPassword {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wrong password.')),
              );
            }
          }
        }
      }

      final thumbs = await widget.service.renderThumbnails(file, width: 180);
      if (!mounted) return;

      _source = file;
      _thumbs = thumbs;
      _page = 0;
      await _loadPreview();

      if (mounted) {
        setState(() {
          _status = 'Drag, pinch and rotate the signature on the page.';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() async {
    final source = _source;
    if (source == null) return;
    final preview = await widget.service.renderPage(
      source,
      _page,
      width: 1400,
    );
    if (mounted) setState(() => _preview = preview);
  }

  Future<void> _drawSignature() async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (bytes == null || !mounted) return;
    setState(() {
      _signature = bytes;
      _x = 0.54;
      _y = 0.72;
      _widthFraction = 0.32;
      _rotationDegrees = 0;
    });
  }

  Future<void> _selectPage(int index) async {
    if (_busy || index == _page) return;
    setState(() {
      _page = index;
      _preview = null;
      _busy = true;
    });
    try {
      await _loadPreview();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final source = _source;
    final signature = _signature;
    if (source == null || signature == null || _pageInfos.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Applying signature…';
    });

    try {
      Uint8List finalSignature = signature;
      if (_rotationDegrees.abs() > 0.5) {
        final decoded = img.decodePng(signature);
        if (decoded != null) {
          final rotated = img.copyRotate(
            decoded,
            angle: _rotationDegrees,
            interpolation: img.Interpolation.linear,
          );
          finalSignature = Uint8List.fromList(img.encodePng(rotated));
        }
      }

      final decoded = img.decodePng(finalSignature);
      final aspect = decoded == null || decoded.height == 0
          ? 2.25
          : decoded.width / decoded.height;

      final pageInfo = _pageInfos[_page];
      final widthPt = pageInfo.width * _widthFraction;
      var heightPt = widthPt / aspect;
      final maxHeight = pageInfo.height * 0.45;
      if (heightPt > maxHeight) heightPt = maxHeight;

      final xPt = (pageInfo.width * _x)
          .clamp(0.0, math.max(0.0, pageInfo.width - widthPt))
          .toDouble();

      // Flutter preview origin is top-left; PDF coordinates are bottom-left.
      final topPt = (pageInfo.height * _y)
          .clamp(0.0, math.max(0.0, pageInfo.height - heightPt))
          .toDouble();
      final yPt = pageInfo.height - topPt - heightPt;

      final output = await widget.service.stampSignatureAt(
        source,
        finalSignature,
        page: _page,
        rect: PdfRect(
          x: xPt,
          y: yPt,
          width: widthPt,
          height: heightPt,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not apply signature.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(widget.service.secureDeleteTemporary(_source));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final signature = _signature;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign PDF'),
        actions: [
          if (_source != null && signature != null)
            TextButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _pickPdf,
                    child: Text(_source == null ? 'Choose PDF' : 'Change'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _drawSignature,
                    child: Text(signature == null ? 'Draw' : 'Redraw'),
                  ),
                ],
              ),
            ),
            if (_thumbs.isNotEmpty)
              SizedBox(
                height: 88,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _thumbs.length,
                  itemBuilder: (context, index) {
                    final selected = index == _page;
                    return GestureDetector(
                      onTap: () => _selectPage(index),
                      child: Container(
                        width: 62,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.memory(
                                _thumbs[index],
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              left: 3,
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                color: Colors.black54,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: Center(
                child: preview == null
                    ? _busy
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.draw_outlined, size: 88)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final info = _pageInfos[_page];
                          final aspect = info.width / info.height;
                          var width = constraints.maxWidth;
                          var height = width / aspect;
                          if (height > constraints.maxHeight) {
                            height = constraints.maxHeight;
                            width = height * aspect;
                          }

                          return SizedBox(
                            width: width,
                            height: height,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: Image.memory(
                                    preview,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                if (signature != null)
                                  Positioned(
                                    left: _x * width,
                                    top: _y * height,
                                    width: _widthFraction * width,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onScaleStart: (_) {
                                        _startWidth = _widthFraction;
                                        _startRotation = _rotationDegrees;
                                      },
                                      onScaleUpdate: (details) {
                                        setState(() {
                                          _x = (_x +
                                                  details.focalPointDelta.dx /
                                                      width)
                                              .clamp(0.0, 0.92);
                                          _y = (_y +
                                                  details.focalPointDelta.dy /
                                                      height)
                                              .clamp(0.0, 0.92);
                                          _widthFraction =
                                              (_startWidth * details.scale)
                                                  .clamp(0.12, 0.75);
                                          _rotationDegrees =
                                              _startRotation +
                                                  details.rotation *
                                                      180 /
                                                      math.pi;
                                        });
                                      },
                                      child: Transform.rotate(
                                        angle: _rotationDegrees *
                                            math.pi /
                                            180,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              width: 2,
                                            ),
                                          ),
                                          child: Image.memory(
                                            signature,
                                            fit: BoxFit.contain,
                                          ),
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
            ),
            if (signature != null && preview != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.open_with_rounded, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Drag to move • pinch to resize/rotate'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _x = 0.54;
                        _y = 0.72;
                        _widthFraction = 0.32;
                        _rotationDegrees = 0;
                      }),
                      child: const Text('Reset'),
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
