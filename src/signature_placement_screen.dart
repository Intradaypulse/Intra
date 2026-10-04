import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'pdf_service.dart';
import 'output_protection.dart';
import 'pdf_password_dialog.dart';
import 'lru_future_cache.dart';
import 'signature_screen.dart';
import 'signature_geometry.dart';
import 'signature_image.dart';

class SignaturePlacementScreen extends StatefulWidget {
  const SignaturePlacementScreen({super.key, required this.service, this.initialSignature});

  final PdfService service;
  final Uint8List? initialSignature;

  @override
  State<SignaturePlacementScreen> createState() =>
      _SignaturePlacementScreenState();
}

class _SignaturePlacementScreenState extends State<SignaturePlacementScreen> {
  File? _source;
  bool _wasProtected = false;
  Uint8List? _signature;
  Uint8List? _placedSignature;
  double _signatureAspect = 2.25;
  Uint8List? _cachedSignature;
  double _imageWidth = 900, _imageHeight = 400;
  double _rotatedWidth = 900, _rotatedHeight = 400;
  String? _previewError;
  final _thumbs = LruFutureCache<int, Uint8List?>(capacity: 24);
  List<PdfPageInfo> _pageInfos = [];
  Uint8List? _preview;
  int _page = 0;
  PdfRect? _pageBox;
  double get _pageWidth => _pageBox?.width ?? _pageInfos[_page].width;
  double get _pageHeight => _pageBox?.height ?? _pageInfos[_page].height;
  bool get _sideways => _pageInfos[_page].rotation % 180 != 0;
  double get _viewWidth => _sideways ? _pageHeight : _pageWidth;
  double get _viewHeight => _sideways ? _pageWidth : _pageHeight;

  double _x = 0.54;
  double _y = 0.72;
  double _widthFraction = 0.32;
  double _rotationDegrees = 0;

  double _startWidth = 0.32;
  double _startRotation = 0;

  bool _busy = false;
  String _status = 'Choose a PDF and draw your signature.';

  @override
  void initState() {
    super.initState();
    _signature = widget.initialSignature;
    if (_signature != null) _updateSignatureImage();
  }

  Future<String?> _askPassword() => askPdfPassword(context);

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
          } catch (error) {
            if (pdfPasswordFailure(error) == null) rethrow;
            if (!mounted) return;
            final password = await _askPassword();
            if (password == null) return;
            try {
              file = await widget.service.decryptToTemporary(file, password);
            } catch (error) {
              if (pdfPasswordFailure(error) == null) rethrow;
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
        _wasProtected = file.path != picked.path || widget.service.wasProtected(file);
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
      _pageBox = await widget.service.pageVisibleBox(source, _page);
      final preview = await widget.service.renderPage(source, _page, width: 1400);
      if (preview == null) throw StateError('Page renderer returned no image.');
      if (mounted) setState(() { _preview = preview; _previewError = null; });
    } catch (e) {
      if (mounted) setState(() { _preview = null; _previewError = 'Could not render this page. Please retry.'; });
    }
  }

  void _updateSignatureImage() {
    if (!identical(_cachedSignature, _signature)) {
      if (_signature == null) return;
      final trimmed = trimSignaturePng(_signature!);
      final decoded = img.decodePng(trimmed);
      if (decoded == null) return;
      _imageWidth = decoded.width.toDouble();
      _imageHeight = decoded.height.toDouble();
      _placedSignature = trimmed;
      _cachedSignature = _signature;
    }
    final angle = _rotationDegrees * math.pi / 180;
    _rotatedWidth = _imageWidth * math.cos(angle).abs() + _imageHeight * math.sin(angle).abs();
    _rotatedHeight = _imageHeight * math.cos(angle).abs() + _imageWidth * math.sin(angle).abs();
    _signatureAspect = _rotatedWidth / _rotatedHeight;
  }

  Rect _placement(double pageWidth, double pageHeight) => signaturePlacement(
    pageWidth: pageWidth, pageHeight: pageHeight, x: _x, y: _y,
    widthFraction: _widthFraction, imageAspect: _signatureAspect);

  void _clampPlacement() {
    if (_pageInfos.isEmpty) return;
    final rect = _placement(_viewWidth, _viewHeight);
    _x = rect.left / _viewWidth;
    _y = rect.top / _viewHeight;
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
    final signature = _placedSignature;
    if (_busy || source == null || signature == null || _pageInfos.isEmpty || _preview == null) return;

    setState(() {
      _busy = true;
      _status = 'Applying signature…';
    });

    try {
      if (_wasProtected) {
        if (!await confirmUnprotectedOutput(context) || !mounted) return;
      }
      // Encode only when saving. The live preview uses a paint transform.
      final decodedSignature = img.decodePng(signature);
      if (decodedSignature == null) throw StateError('Invalid signature image.');
      var finalSignature = Uint8List.fromList(img.encodePng(img.copyRotate(
        decodedSignature, angle: _rotationDegrees, interpolation: img.Interpolation.linear)));
      final pageInfo = _pageInfos[_page];
      final placement = _placement(_viewWidth, _viewHeight);
      final rect = signaturePdfRect(placement, _pageWidth, _pageHeight, pageInfo.rotation);
      if (pageInfo.rotation != 0) {
        final image = img.decodePng(finalSignature);
        if (image == null) throw StateError('Invalid signature image.');
        finalSignature = img.encodePng(img.copyRotate(image, angle: -pageInfo.rotation));
      }
      final xPt = rect.left + (_pageBox?.x ?? 0);
      final yPt = rect.top + (_pageBox?.y ?? 0);
      final widthPt = rect.width;
      final heightPt = rect.height;

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
                            final aspect = _viewWidth / _viewHeight;
                            var width = constraints.maxWidth;
                            var height = width / aspect;
                            if (height > constraints.maxHeight) {
                              height = constraints.maxHeight;
                              width = height * aspect;
                            }

                            final placement = _placement(width, height);
                            return GestureDetector(
                              key: const ValueKey('signature-page-gestures'),
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: _busy || signature == null ? null : (_) {
                                _startWidth = _widthFraction;
                                _startRotation = _rotationDegrees;
                              },
                              onScaleUpdate: _busy || signature == null ? null : (details) {
                                setState(() {
                                  _x += details.focalPointDelta.dx / width;
                                  _y += details.focalPointDelta.dy / height;
                                  _widthFraction = (_startWidth * details.scale).clamp(.03, .95);
                                  _rotationDegrees = ((_startRotation + details.rotation * 180 / math.pi + 180) % 360) - 180;
                                  _updateSignatureImage();
                                  _clampPlacement();
                                });
                              },
                              child: SizedBox(
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
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                            key: const ValueKey('placed-signature'),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                width: 2,
                                              ),
                                            ),
                                            child: FittedBox(fit: BoxFit.contain,
                                              child: SizedBox(width: _rotatedWidth, height: _rotatedHeight,
                                                child: OverflowBox(minWidth: _imageWidth, maxWidth: _imageWidth,
                                                  minHeight: _imageHeight, maxHeight: _imageHeight,
                                                  child: Transform.rotate(angle: _rotationDegrees * math.pi / 180,
                                                    child: Image.memory(signature, fit: BoxFit.fill))))),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ));
                          },
                        ),
                ),
              ),
              if (signature != null && preview != null) ...[
                Row(children: [
                  const SizedBox(width: 12), const Text('Size'),
                  Expanded(child: Slider(value: _widthFraction, min: .03, max: .95,
                    onChanged: _busy ? null : (value) => setState(() {
                      _widthFraction = value; _clampPlacement();
                    }))),
                  Text('${(_widthFraction * 100).round()}%'), const SizedBox(width: 12),
                ]),
                Row(children: [
                  const SizedBox(width: 12), const Text('Rotate'),
                  Expanded(child: Slider(value: _rotationDegrees, min: -180, max: 180,
                    onChanged: _busy ? null : (value) => setState(() {
                      _rotationDegrees = value; _updateSignatureImage(); _clampPlacement();
                    }))),
                  Text('${_rotationDegrees.round()}°'), const SizedBox(width: 12),
                ]),
              ],
              if (signature != null && preview != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.open_with_rounded, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Drag anywhere • pinch to resize/rotate'),
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
