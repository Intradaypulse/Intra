import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'pdf_service.dart';
import 'ocr_languages.dart';

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
    final lines = [for (final block in preview.text.blocks) ...block.lines];
    final text = all ? preview.text.text : [for (var i = 0; i < lines.length; i++)
      if (_selected.contains(i)) lines[i].text].join('\n');
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
    final lines = preview == null ? <TextLine>[] : [for (final block in preview.text.blocks) ...block.lines];
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: Text('Copy text • page ${_page + 1}')),
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
            : 'Tap lines on the page to select text. ${preview.languages.isEmpty ? '' : 'Languages: ${preview.languages.join(', ')}'}')),
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
                  Positioned(left: lines[i].boundingBox.left * scale, top: lines[i].boundingBox.top * scale,
                    width: lines[i].boundingBox.width * scale, height: lines[i].boundingBox.height * scale,
                    child: Semantics(label: lines[i].text, selected: _selected.contains(i), button: true,
                      child: GestureDetector(behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() {
                          if (!_selected.add(i)) _selected.remove(i);
                        }),
                        child: Container(decoration: BoxDecoration(
                          color: _selected.contains(i) ? Colors.blue.withValues(alpha: .3) : Colors.transparent,
                          border: Border.all(color: Colors.blue.withValues(alpha: .35)))),
                      )),
                  ),
              ]),
            )));
          })),
        Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
          IconButton(tooltip: 'Previous page', onPressed: _busy || _page <= 0 ? null : () { _page--; _load(); }, icon: const Icon(Icons.chevron_left)),
          OutlinedButton(onPressed: preview == null || _selected.isEmpty ? null : () => _copy(false), child: const Text('Copy selected')),
          FilledButton(onPressed: preview == null || lines.isEmpty ? null : () => _copy(true), child: const Text('Copy page')),
          IconButton(tooltip: 'Next page', onPressed: _busy || _page >= widget.pageCount - 1 ? null : () { _page++; _load(); }, icon: const Icon(Icons.chevron_right)),
        ]),
      ])),
    ));
  }
}
