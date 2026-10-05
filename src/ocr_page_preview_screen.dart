import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'pdf_service.dart';
import 'ocr_languages.dart';

class _OcrHit {
  const _OcrHit(this.text, this.box, this.block, this.line);
  final String text;
  final Rect box;
  final int block, line;
}

List<_OcrHit> _hits(OcrPagePreview preview) => [
  for (var b = 0; b < preview.text.blocks.length; b++)
    for (var l = 0; l < preview.text.blocks[b].lines.length; l++)
      if (preview.text.blocks[b].lines[l].elements.isEmpty)
        _OcrHit(
          preview.text.blocks[b].lines[l].text,
          preview.text.blocks[b].lines[l].boundingBox,
          b,
          l,
        )
      else
        for (final word in preview.text.blocks[b].lines[l].elements)
          _OcrHit(word.text, word.boundingBox, b, l),
];

class OcrPagePreviewScreen extends StatefulWidget {
  const OcrPagePreviewScreen({
    super.key,
    required this.service,
    required this.source,
    required this.pageCount,
    this.initialPage = 0,
    this.password,
    this.script,
  });
  final PdfService service;
  final File source;
  final int pageCount, initialPage;
  final String? password;
  final TextRecognitionScript? script;
  @override
  State<OcrPagePreviewScreen> createState() => _OcrPagePreviewScreenState();
}

class _OcrPagePreviewScreenState extends State<OcrPagePreviewScreen> {
  late int _page;
  late TextRecognitionScript? _script;
  OcrPagePreview? _preview;
  PdfOperationControl? _control;
  bool _busy = false;
  String? _error;
  final Set<int> _selected = {};
  bool _showText = true;
  final _imageKey = GlobalKey();
  final _transform = TransformationController();
  void _transformChanged() {
    if (mounted && _rangeStart != null) setState(() {});
  }

  int? _rangeStart, _rangeEnd;

  void _selectParagraph(int index, List<_OcrHit> hits) {
    final block = hits[index].block;
    setState(() {
      _rangeStart = hits.indexWhere((hit) => hit.block == block);
      _rangeEnd = hits.lastIndexWhere((hit) => hit.block == block);
      _selected
        ..clear()
        ..addAll(
          List.generate(_rangeEnd! - _rangeStart! + 1, (i) => _rangeStart! + i),
        );
    });
  }

  void _extendRange(
    Offset global,
    List<_OcrHit> hits,
    double scale, {
    bool start = false,
  }) {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || hits.isEmpty || scale <= 0) return;
    final point = box.globalToLocal(global) / scale;
    var nearest = 0;
    var distance = double.infinity;
    for (var i = 0; i < hits.length; i++) {
      final r = hits[i].box;
      final dx = point.dx - point.dx.clamp(r.left, r.right);
      final dy = point.dy - point.dy.clamp(r.top, r.bottom);
      final d = dx * dx + dy * dy;
      if (d < distance) {
        distance = d;
        nearest = i;
      }
    }
    setState(() {
      if (start) {
        _rangeStart = nearest;
        if (nearest > _rangeEnd!) _rangeEnd = nearest;
      } else {
        _rangeEnd = nearest;
        if (nearest < _rangeStart!) _rangeStart = nearest;
      }
      final a = _rangeStart!, b = _rangeEnd!;
      final low = a < b ? a : b, high = a > b ? a : b;
      _selected
        ..clear()
        ..addAll(List.generate(high - low + 1, (i) => low + i));
    });
  }

  List<Widget> _handles(
    List<_OcrHit> hits,
    double scale,
    double imageWidth,
    double imageHeight,
    double viewWidth,
    double viewHeight,
  ) {
    if (_rangeStart == null || _rangeEnd == null || hits.isEmpty) return [];
    Offset position(bool start) {
      final r = hits[start ? _rangeStart! : _rangeEnd!].box;
      final point = MatrixUtils.transformPoint(
        _transform.value,
        Offset(
          (viewWidth - imageWidth) / 2 + (start ? r.left : r.right) * scale,
          (viewHeight - imageHeight) / 2 + r.bottom * scale,
        ),
      );
      return Offset(
        (point.dx - 14).clamp(0.0, math.max(0.0, viewWidth - 28)).toDouble(),
        point.dy.clamp(0.0, math.max(0.0, viewHeight - 28)).toDouble(),
      );
    }

    var first = position(true), last = position(false);
    // Separate touch targets, even for a one-character selection at an edge.
    if ((first.dx - last.dx).abs() < 32 && (first.dy - last.dy).abs() < 32) {
      if (last.dy >= 32) {
        first = Offset(first.dx, last.dy - 32);
      } else {
        last = Offset(last.dx, math.min(viewHeight - 28, first.dy + 32));
      }
    }
    return [
      for (final start in [true, false])
        Positioned(
          left: (start ? first : last).dx,
          top: (start ? first : last).dy,
          child: Semantics(
            label: start ? 'Selection start' : 'Selection end',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) => _extendRange(
                details.globalPosition,
                hits,
                scale,
                start: start,
              ),
              child: const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.circle, size: 22, color: Colors.blue),
              ),
            ),
          ),
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _script = widget.script;
    _transform.addListener(_transformChanged);
    _load();
  }

  @override
  void dispose() {
    _control?.cancel();
    _transform.removeListener(_transformChanged);
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    final control = PdfOperationControl();
    _control = control;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _selected.clear();
      _rangeStart = null;
      _rangeEnd = null;
    });
    try {
      final preview = await widget.service.recognizePage(
        widget.source,
        _page,
        script: _script,
        password: widget.password,
        control: control,
      );
      control.check();
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is PdfOperationCancelled
              ? 'Cancelled. Tap Retry to scan.'
              : 'Could not scan page: $e',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
      _control = null;
    }
  }

  Future<void> _copy(bool all) async {
    final preview = _preview;
    if (preview == null) return;
    final lines = _hits(preview);
    final buffer = StringBuffer();
    _OcrHit? previous;
    for (var i = 0; i < lines.length; i++) {
      if (!_selected.contains(i)) continue;
      final hit = lines[i];
      if (previous != null)
        buffer.write(
          previous.block != hit.block
              ? '\n\n'
              : previous.line != hit.line
              ? '\n'
              : ' ',
        );
      buffer.write(hit.text);
      previous = hit;
    }
    final text = all ? preview.text.text : buffer.toString();
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Text copied.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Copy failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final lines = preview == null ? <_OcrHit>[] : _hits(preview);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text('Copy text • page ${_page + 1}')),
        bottomNavigationBar: SafeArea(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _busy || _page <= 0
                    ? null
                    : () {
                        _page--;
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              OutlinedButton(
                onPressed: preview == null || _selected.isEmpty
                    ? null
                    : () => _copy(false),
                child: const Text('Copy selected'),
              ),
              FilledButton(
                onPressed: preview == null || lines.isEmpty
                    ? null
                    : () => _copy(true),
                child: const Text('Copy page'),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _busy || _page >= widget.pageCount - 1
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<TextRecognitionScript>(
                  initialValue: _script,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'OCR model'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Detect automatically'),
                    ),
                    for (final script in TextRecognitionScript.values)
                      DropdownMenuItem(
                        value: script,
                        child: Text(
                          ocrLanguages
                              .firstWhere(
                                (language) => language.script == script,
                              )
                              .name,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          _script = value;
                          _load();
                        },
                ),
              ),
              if (_busy) ...[
                const LinearProgressIndicator(),
                TextButton(
                  onPressed: () => _control?.cancel(),
                  child: const Text('Cancel'),
                ),
              ],
              if (preview != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    lines.isEmpty
                        ? 'No text found. Try another OCR model.'
                        : 'Long-press to select a paragraph. Drag the blue handles to adjust it; tap to select individual words. ${preview.languages.isEmpty ? '' : 'Languages: ${preview.languages.join(', ')}'}',
                  ),
                ),
              if (preview != null)
                SwitchListTile(
                  dense: true,
                  title: const Text('Show recognized text on image'),
                  value: _showText,
                  onChanged: (value) => setState(() => _showText = value),
                ),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : preview == null
                    ? const Center(child: Text('Scanning page…'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final scale = (constraints.maxWidth / preview.width)
                              .clamp(
                                0.0,
                                constraints.maxHeight / preview.height,
                              );
                          final width = preview.width * scale,
                              height = preview.height * scale;
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  maxScale: 5,
                                  child: Center(
                                    child: SizedBox(
                                      width: width,
                                      height: height,
                                      child: Stack(
                                        key: _imageKey,
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned.fill(
                                            child: Image.memory(
                                              preview.bytes,
                                              fit: BoxFit.fill,
                                            ),
                                          ),
                                          for (var i = 0; i < lines.length; i++)
                                            Positioned(
                                              left: lines[i].box.left * scale,
                                              top: lines[i].box.top * scale,
                                              width: lines[i].box.width * scale,
                                              height:
                                                  lines[i].box.height * scale,
                                              child: Semantics(
                                                label: lines[i].text,
                                                excludeSemantics: true,
                                                selected: _selected.contains(i),
                                                button: true,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () => setState(() {
                                                    _rangeStart = null;
                                                    _rangeEnd = null;
                                                    if (!_selected.add(i))
                                                      _selected.remove(i);
                                                  }),
                                                  onLongPress: () =>
                                                      _selectParagraph(
                                                        i,
                                                        lines,
                                                      ),
                                                  onLongPressMoveUpdate:
                                                      (details) => _extendRange(
                                                        details.globalPosition,
                                                        lines,
                                                        scale,
                                                      ),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _selected.contains(i)
                                                          ? Colors.blue
                                                                .withValues(
                                                                  alpha: .3,
                                                                )
                                                          : (_showText
                                                                ? Colors.white
                                                                      .withValues(
                                                                        alpha:
                                                                            .85,
                                                                      )
                                                                : Colors
                                                                      .transparent),
                                                      border: Border.all(
                                                        color: Colors.blue
                                                            .withValues(
                                                              alpha: .35,
                                                            ),
                                                      ),
                                                    ),
                                                    child: _showText
                                                        ? FittedBox(
                                                            fit: BoxFit.contain,
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Text(
                                                              lines[i].text,
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .black,
                                                                  ),
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              ..._handles(
                                lines,
                                scale,
                                width,
                                height,
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
