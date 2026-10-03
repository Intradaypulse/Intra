import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'pdf_service.dart';
import 'output_protection.dart';

class CompressionScreen extends StatefulWidget {
  const CompressionScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<CompressionScreen> createState() => _CompressionScreenState();
}

class _CompressionScreenState extends State<CompressionScreen> {
  File? _source;
  CompressionPreset _preset = CompressionPreset.balanced;
  CompressionResult? _result;
  String? _password;
  bool _busy = false;
  bool _outputHandedOff = false;

  @override
  void dispose() {
    unawaited(widget.service.secureDeleteTemporary(_source));
    final result = _result;
    if (!_outputHandedOff && result != null) {
      unawaited(widget.service.secureDeleteTemporary(result.file));
    }
    super.dispose();
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<String?> _askPassword({bool wrong = false}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(wrong ? 'Wrong password' : 'Protected PDF'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PDF password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
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
    if (_busy) return;
    setState(() => _busy = true);
    File? file;
    String? password;
    try {
      file = await widget.service.pickPdfFile();
      if (file == null || !mounted) return;
      while (true) {
        try {
          await widget.service.pageCount(file, password: password);
          break;
        } on PdfPasswordRequired {
          if (!mounted) return;
          final entered = await _askPassword();
          if (entered == null) return;
          password = entered;
        } on PdfWrongPassword {
          if (!mounted) return;
          final entered = await _askPassword(wrong: true);
          if (entered == null) return;
          password = entered;
        }
      }

      if (!mounted) return;
      final previous = _source;
      final previousResult = _result;
      setState(() {
        _source = file;
        _password = password;
        _result = null;
      });
      if (previous?.path != file.path) {
        await widget.service.secureDeleteTemporary(previous);
      }
      if (previousResult != null && !_outputHandedOff) {
        await widget.service.secureDeleteTemporary(previousResult.file);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: $error')),
        );
      }
    } finally {
      if (file != null && (_source?.path != file.path || !mounted)) {
        await widget.service.secureDeleteTemporary(file);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compress() async {
    final source = _source;
    if (source == null || _busy) return;

    if (widget.service.wasProtected(source) || (_password != null && _password!.isNotEmpty)) {
      setState(() => _busy = true);
      final allowed = await confirmUnprotectedOutput(context);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!allowed) return;
    }
    final oldResult = _result;
    setState(() {
      _busy = true;
      _result = null;
    });
    if (oldResult != null) {
      await widget.service.secureDeleteTemporary(oldResult.file);
    }

    try {
      final result = await widget.service.compressAdvanced(
        source,
        _preset,
        password: _password,
      );
      if (!mounted) {
        await widget.service.secureDeleteTemporary(result.file);
        return;
      }
      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compression failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: Text(
                  (_source == null ? null : widget.service.displayName(_source!)) ?? 'Choose a PDF',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: _source == null
                    ? const Text('No file selected')
                    : FutureBuilder<int>(
                        future: _source!.length(),
                        builder: (_, snap) => Text(
                          snap.hasData
                              ? _formatBytes(snap.data!)
                              : 'Reading size…',
                        ),
                      ),
                trailing: OutlinedButton(
                  onPressed: _busy ? null : _pick,
                  child: const Text('Choose'),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Compression level',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            RadioGroup<CompressionPreset>(
              groupValue: _preset,
              onChanged: (value) {
                if (!_busy && value != null) {
                  setState(() => _preset = value);
                }
              },
              child: const Column(
                children: [
                  RadioListTile(
                    value: CompressionPreset.highQuality,
                    title: Text('High quality'),
                    subtitle: Text(
                      'Best image quality, lighter optimization.',
                    ),
                  ),
                  RadioListTile(
                    value: CompressionPreset.balanced,
                    title: Text('Balanced'),
                    subtitle: Text(
                      'Recommended for documents and sharing.',
                    ),
                  ),
                  RadioListTile(
                    value: CompressionPreset.smallest,
                    title: Text('Smallest size'),
                    subtitle: Text(
                      'Strong image downsampling for maximum reduction.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_source == null || _busy) ? null : _compress,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.compress_rounded),
              label: const Text('Compress now'),
            ),
            if (result != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle_rounded),
                          SizedBox(width: 8),
                          Text(
                            'Compression complete',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Metric(
                        label: 'Original',
                        value: _formatBytes(result.originalBytes),
                      ),
                      _Metric(
                        label: 'Compressed',
                        value: _formatBytes(result.outputBytes),
                      ),
                      _Metric(
                        label: result.savedBytes >= 0 ? 'Saved' : 'Change',
                        value: result.savedBytes >= 0
                            ? '${_formatBytes(result.savedBytes)} '
                                '(${result.savedPercent.toStringAsFixed(1)}%)'
                            : '+${_formatBytes(-result.savedBytes)}',
                      ),
                      if (result.savedBytes < 0) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'This PDF was already highly optimized; recompression produced a slightly larger file.',
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Save to My PDFs'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ));
  }

  Future<void> _save() async {
    final result = _result;
    if (_busy || result == null) return;
    setState(() => _busy = true);
    try {
      final output = await widget.service.publishCompressionPreview(result.file);
      _outputHandedOff = true;
      if (mounted) Navigator.of(context).pop<File>(output);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save PDF. Please retry: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
