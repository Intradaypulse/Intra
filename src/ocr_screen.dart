import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'ads_service.dart';
import 'pdf_service.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  File? _source;
  TextRecognitionScript _script = TextRecognitionScript.latin;
  bool _busy = false;
  int _pageCount = 0;
  bool _heavyUnlocked = false;
  String _status = 'Choose a PDF to OCR.';
  String? _extractedText;

  String _scriptLabel(TextRecognitionScript script) => switch (script) {
        TextRecognitionScript.latin => 'Latin',
        TextRecognitionScript.chinese => 'Chinese',
        TextRecognitionScript.devanagiri => 'Devanagari / Hindi',
        TextRecognitionScript.japanese => 'Japanese',
        TextRecognitionScript.korean => 'Korean',
      };

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

  Future<void> _pick() async {
    final picked = await widget.service.pickPdfFile();
    if (picked == null) return;
    var file = picked;

    setState(() {
      _busy = true;
      _extractedText = null;
      _status = 'Checking PDF…';
    });

    try {
      while (true) {
        try {
          final count = await widget.service.pageCount(file);
          if (!mounted) return;
          setState(() {
            _source = file;
            _pageCount = count;
            _heavyUnlocked = count <= 10;
            _status = '$count page(s) ready for OCR.';
          });
          break;
        } on PdfPasswordRequired {
          if (!mounted) return;
          final password = await _askPassword();
          if (password == null) return;
          try {
            file = await widget.service.unlockPdf(file, password);
          } on PdfWrongPassword {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wrong password.')),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<bool> _ensureLargeOcrUnlocked() async {
    if (_pageCount <= 10 || _heavyUnlocked) return true;

    // If no rewarded ad is currently loaded, don't make the document tool
    // unusable; continue and preload for the next heavy task.
    if (!AdsService.instance.rewardedAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Rewarded ad is not ready — processing this large PDF without an ad.',
            ),
          ),
        );
      }
      return true;
    }

    final watch = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Large OCR job'),
        content: Text(
          'This PDF has $_pageCount pages. Watch one rewarded ad to unlock the full OCR/searchable-PDF job.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch ad'),
          ),
        ],
      ),
    );

    if (watch != true) return false;
    final earned = await AdsService.instance.showRewarded();
    if (!earned) return false;
    _heavyUnlocked = true;
    return true;
  }

  Future<void> _extract() async {
    final source = _source;
    if (source == null) return;
    if (!await _ensureLargeOcrUnlocked()) return;

    setState(() {
      _busy = true;
      _status = 'Recognizing text on-device…';
      _extractedText = null;
    });

    try {
      final pages = await widget.service.ocrPdf(
        source,
        script: _script,
      );
      final combined = [
        for (var i = 0; i < pages.length; i++)
          '--- Page ${i + 1} ---\n${pages[i]}',
      ].join('\n\n');

      if (!mounted) return;
      setState(() {
        _extractedText = combined;
        _status = 'OCR complete for ${pages.length} page(s).';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'OCR failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _makeSearchable() async {
    final source = _source;
    if (source == null) return;
    if (!await _ensureLargeOcrUnlocked()) return;

    setState(() {
      _busy = true;
      _status = 'Building searchable PDF…';
    });

    try {
      final output = await widget.service.makeSearchablePdf(
        source,
        script: _script,
      );
      if (!mounted) return;
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Searchable PDF failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Searchable PDF failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _extractedText;

    return Scaffold(
      appBar: AppBar(title: const Text('OCR & searchable PDF')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: Text(
                  _source?.uri.pathSegments.last ?? 'No PDF selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_status),
                trailing: OutlinedButton(
                  onPressed: _busy ? null : _pick,
                  child: const Text('Choose'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TextRecognitionScript>(
              initialValue: _script,
              decoration: const InputDecoration(
                labelText: 'OCR script / language family',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final script in TextRecognitionScript.values)
                  DropdownMenuItem(
                    value: script,
                    child: Text(_scriptLabel(script)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _script = value);
                    },
            ),
            const SizedBox(height: 10),
            const Text(
              'All recognition runs on-device. Choose the script matching the document for best accuracy.',
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_source == null || _busy) ? null : _extract,
                    icon: const Icon(Icons.text_snippet_outlined),
                    label: const Text('Extract text'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (_source == null || _busy) ? null : _makeSearchable,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Make searchable'),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
            if (text != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    'Recognized text',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy all'),
                  ),
                ],
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 420),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(text),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
