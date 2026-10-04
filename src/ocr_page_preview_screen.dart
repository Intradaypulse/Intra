import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'pdf_service.dart';
import 'ocr_languages.dart';

class _OcrHit {
  const _OcrHit(this.text, this.box);
  final String text;
  final Rect box;
}

List<_OcrHit> _hits(OcrPagePreview preview) => [
  for (final block in preview.text.blocks)
    for (final line in block.lines)
      if (line.elements.isEmpty) _OcrHit(line.text, line.boundingBox)
      else for (final word in line.elements) _OcrHit(word.text, word.boundingBox),
];

class OcrPagePreviewScreen extends StatefulWidget {
  const OcrPagePreviewScreen({super.key, required this.service, required this.source,
    required this.pageCount, this.initialPage = 0, this.password, this.script});
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

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _script = widget.script;
    _load();
  }
  @override
  void dispose() { _control?.cancel(); super.dispose(); }

  Future<void> _load() async {
    if (_busy) return;
    final control = PdfOperationControl();
    _control = control;
    setState(() { _busy = true; _error = null; _preview = null; _selected.clear(); });
    try {
      final preview = await widget.service.recognizePage(widget.source, _page,
        script: _script, password: widget.password, control: control);
      control.check();
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = e is PdfOperationCancelled ? 'Cancelled. Tap Retry to scan.' : 'Could not scan page: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _control = null;
    }
  }

  Future<void> _copy(bool all) async {
    final preview = _preview;
    if (preview == null) return;
    final lines = _hits(preview);
    final text = all ? preview.text.text : [for (var i = 0; i < lines.length; i++)
      if (_selected.contains(i)) lines[i].text].join(' ');
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Text copied.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final lines = preview == null ? <_OcrHit>[] : _hits(preview);
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: Text('Copy text • page ${_page + 1}')),
      bottomNavigationBar: SafeArea(child: Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          IconButton(tooltip: 'Previous page', onPressed: _busy || _page <= 0 ? null : () { _page--; _load(); }, icon: const Icon(Icons.chevron_left)),
          OutlinedButton(onPressed: preview == null || _selected.isEmpty ? null : () => _copy(false), child: const Text('Copy selected')),
          FilledButton(onPressed: preview == null || lines.isEmpty ? null : () => _copy(true), child: const Text('Copy page')),
          IconButton(tooltip: 'Next page', onPressed: _busy || _page >= widget.pageCount - 1 ? null : () { _page++; _load(); }, icon: const Icon(Icons.chevron_right)),
        ])),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<TextRecognitionScript>(
          initialValue: _script, isExpanded: true,
          decoration: const InputDecoration(labelText: 'OCR model'),
          items: [const DropdownMenuItem(value: null, child: Text('Detect automatically')),
            for (final script in TextRecognitionScript.values) DropdownMenuItem(value: script,
              child: Text(ocrLanguages.firstWhere((language) => language.script == script).name))],
          onChanged: _busy ? null : (value) { _script = value; _load(); },
        )),
        if (_busy) ...[
          const LinearProgressIndicator(),
          TextButton(onPressed: () => _control?.cancel(), child: const Text('Cancel')),
        ],
        if (preview != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(lines.isEmpty ? 'No text found. Try another OCR model.'
            : 'Tap words on the image to select them. Long-press a word to copy it. ${preview.languages.isEmpty ? '' : 'Languages: ${preview.languages.join(', ')}'}')),
        if (preview != null) SwitchListTile(dense: true,
          title: const Text('Show recognized text on image'), value: _showText,
          onChanged: (value) => setState(() => _showText = value)),
        Expanded(child: _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center), TextButton(onPressed: _load, child: const Text('Retry')),
        ])) : preview == null ? const Center(child: Text('Scanning page…'))
          : LayoutBuilder(builder: (context, constraints) {
            final scale = (constraints.maxWidth / preview.width).clamp(0.0, constraints.maxHeight / preview.height);
            final width = preview.width * scale, height = preview.height * scale;
            return InteractiveViewer(maxScale: 5, child: Center(child: SizedBox(width: width, height: height,
              child: Stack(children: [
                Positioned.fill(child: Image.memory(preview.bytes, fit: BoxFit.fill)),
                for (var i = 0; i < lines.length; i++)
                  Positioned(left: lines[i].box.left * scale, top: lines[i].box.top * scale,
                    width: lines[i].box.width * scale, height: lines[i].box.height * scale,
                    child: Semantics(label: lines[i].text, excludeSemantics: true, selected: _selected.contains(i), button: true,
                      child: GestureDetector(behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          if (!_selected.add(i)) _selected.remove(i);
                        }),
                        onLongPress: () async {
                          try {
                            await Clipboard.setData(ClipboardData(text: lines[i].text));
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Word copied.')));
                          } catch (error) {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copy failed: $error')));
                          }
                        },
                        child: Container(decoration: BoxDecoration(
                          color: _selected.contains(i) ? Colors.blue.withValues(alpha: .3) : (_showText ? Colors.white.withValues(alpha: .85) : Colors.transparent),
                          border: Border.all(color: Colors.blue.withValues(alpha: .35))),
                          child: _showText ? FittedBox(fit: BoxFit.contain, alignment: Alignment.centerLeft,
                            child: Text(lines[i].text, style: const TextStyle(color: Colors.black))) : null),
                      )),
                  ),
              ]),
            )));
          })),

      ])),
    ));
  }
}
