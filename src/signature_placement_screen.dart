import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'pdf_service.dart';
import 'lru_future_cache.dart';
import 'signature_screen.dart';
import 'signature_geometry.dart';

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
  Uint8List? _placedSignature;
  double _signatureAspect = 2.25;
  Uint8List? _cachedSignature;
  double? _cachedRotation;
  String? _previewError;
  final _thumbs = LruFutureCache<int, Uint8List?>(capacity: 24);
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final previous = _source;
      final picked = await widget.service.pickPdfFile();
      if (picked == null) return;
      if (!mounted) {
        await widget.service.secureDeleteTemporary(picked);
        return;
      }
      var file = picked;

      setState(() {
        _busy = true;
        _status = 'Loading PDF pages…';
      });

      var infos = _pageInfos;
      try {
        while (true) {
          try {
            infos = await widget.service.pageInfos(file);
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

        if (!mounted) return;

        _source = file;
        _pageInfos = infos;
        _thumbs.clear();
        _preview = null;

        _page = 0;
        await _loadPreview();

        if (mounted) {
          setState(() {
            _status = 'Drag, pinch and rotate the signature on the page.';
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not load PDF: $e')));
        }
      } finally {
        if (picked.path != file.path) {
          await widget.service.secureDeleteTemporary(picked);
        }
        if (_source?.path != file.path || !mounted) {
          await widget.service.secureDeleteTemporary(file);
        }
        if (_source?.path != previous?.path) {
          await widget.service.secureDeleteTemporary(previous);
        }
        if (mounted) setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not choose PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() async {
    final source = _source;
    if (source == null) return;
    try {
      final preview = await widget.service.renderPage(source, _page, width: 1400);
      if (preview == null) throw StateError('Page renderer returned no image.');
      if (mounted) setState(() { _preview = preview; _previewError = null; });
    } catch (e) {
      if (mounted) setState(() { _preview = null; _previewError = 'Could not render this page. Please retry.'; });
    }
  }

  void _updateSignatureImage() {
    if (identical(_cachedSignature, _signature) && _cachedRotation == _rotationDegrees) return;
    final decoded = _signature == null ? null : img.decodePng(_signature!);
    if (decoded == null) return;
    final rotated = img.copyRotate(decoded, angle: _rotationDegrees,
        interpolation: img.Interpolation.linear);
    _placedSignature = Uint8List.fromList(img.encodePng(rotated));
    _signatureAspect = rotated.width / rotated.height;
    _cachedSignature = _signature;
    _cachedRotation = _rotationDegrees;
  }

  Rect _placement(double pageWidth, double pageHeight) => signaturePlacement(
    pageWidth: pageWidth, pageHeight: pageHeight, x: _x, y: _y,
    widthFraction: _widthFraction, imageAspect: _signatureAspect);

  void _clampPlacement() {
    if (_pageInfos.isEmpty) return;
    final info = _pageInfos[_page];
    final rect = _placement(info.width, info.height);
    _x = rect.left / info.width;
    _y = rect.top / info.height;
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
      _updateSignatureImage();
      _clampPlacement();
    });
  }

  Future<void> _selectPage(int index) async {
    if (_busy || (index == _page && _previewError == null)) return;
    setState(() {
      _page = index;
      _clampPlacement();
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
    if (_busy || source == null || signature == null || _pageInfos.isEmpty || _preview == null) return;

    setState(() {
      _busy = true;
      _status = 'Applying signature…';
    });

    try {
      final finalSignature = _placedSignature ?? signature;
      final pageInfo = _pageInfos[_page];
      final placement = _placement(pageInfo.width, pageInfo.height);
      final xPt = placement.left;
      final yPt = pageInfo.height - placement.bottom;
      final widthPt = placement.width;
      final heightPt = placement.height;

      final output = await widget.service.stampSignatureAt(
        source,
        finalSignature,
        page: _page,
        rect: PdfRect(x: xPt, y: yPt, width: widthPt, height: heightPt),
      );

      if (!mounted) {
        await output.delete();
        return;
      }
      setState(() => _busy = false);
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not apply signature.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Signature failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _thumbs.clear();
    unawaited(widget.service.secureDeleteTemporary(_source));
    super.dispose();
  }

  Future<Uint8List?> _thumbnail(int index) {
    final control = PdfOperationControl();
    return _thumbs.getOrCreate(index,
      () => widget.service.renderPage(_source!, index, width: 180, control: control),
      onDiscard: control.cancel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final signature = _placedSignature;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sign PDF'),
          actions: [
            if (_source != null && signature != null)
              TextButton(
                onPressed: _busy || _preview == null ? null : _save,
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
              if (_pageInfos.isNotEmpty)
                SizedBox(
                  height: 88,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _pageInfos.length,
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
                                child: FutureBuilder<Uint8List?>(
                                  future: _thumbnail(index),
                                  builder: (context, snapshot) =>
                                      snapshot.data == null
                                      ? const Icon(
                                          Icons.picture_as_pdf_outlined,
                                        )
                                      : Image.memory(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                        ),
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
                            : _previewError != null
                            ? Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(_previewError!),
                                TextButton(onPressed: () => _selectPage(_page), child: const Text('Retry')),
                              ])
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

                            final placement = _placement(width, height);
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
                                      left: placement.left,
                                      top: placement.top,
                                      width: placement.width,
                                      height: placement.height,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onScaleStart: (_) {
                                          if (_busy) return;
                                          _startWidth = _widthFraction;
                                          _startRotation = _rotationDegrees;
                                        },
                                        onScaleUpdate: (details) {
                                          if (_busy) return;
                                          setState(() {
                                            _x =
                                                (_x +
                                                        details
                                                                .focalPointDelta
                                                                .dx /
                                                            width)
                                                    .clamp(0.0, 0.92);
                                            _y =
                                                (_y +
                                                        details
                                                                .focalPointDelta
                                                                .dy /
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
                                            _updateSignatureImage();
                                            _clampPlacement();
                                          });
                                        },
                                        child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
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
                        onPressed: _busy ? null : () => setState(() {
                          _x = 0.54;
                          _y = 0.72;
                          _widthFraction = 0.32;
                          _rotationDegrees = 0;
                          _updateSignatureImage();
                          _clampPlacement();
                        }),
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
