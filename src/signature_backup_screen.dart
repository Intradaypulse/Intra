import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'pdf_service.dart';
import 'signature_store.dart';

class SignatureBackupScreen extends StatefulWidget {
  const SignatureBackupScreen({super.key, this.store, this.service});
  final SignatureStore? store;
  final PdfService? service;
  @override State<SignatureBackupScreen> createState() => _SignatureBackupScreenState();
}
class _SignatureBackupScreenState extends State<SignatureBackupScreen> {
  late final _store = widget.store ?? SignatureStore();
  late final _service = widget.service ?? PdfService();
  bool _busy = false;
  String? _result;
  Future<void> _run(Future<String> Function() operation) async {
    if (_busy) return;
    setState(() { _busy = true; _result = null; });
    try {
      final result = await operation();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _result = 'Could not complete backup: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<String> _export() async {
    final bytes = await _store.exportBackup();
    await _service.exportSignatureBackup(bytes);
    return 'Signature backup saved to Downloads/PDFMate.';
  }

  Future<String> _restore() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (picked == null) return 'Restore cancelled.';
    final builder = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in picked.readAsByteStream()) {
      count += chunk.length;
      if (count > SignatureStore.maxBackupBytes) throw const FormatException('Backup is too large.');
      builder.add(chunk);
    }
    final restored = await _store.restoreBackup(builder.takeBytes());
    return restored == 0 ? 'All signatures in this backup are already saved.' : '$restored signature(s) restored.';
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !_busy,
    child: Scaffold(appBar: AppBar(title: const Text('Signature backup')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Save a copy of your signatures outside the app, then restore it after reinstalling or changing phones.'),
        const SizedBox(height: 12),
        const Text('The backup contains your signature images. Keep it private.'),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _busy ? null : () => _run(_export),
          icon: const Icon(Icons.save_alt), label: const Text('Save backup to Downloads')),
        OutlinedButton.icon(onPressed: _busy ? null : () => _run(_restore),
          icon: const Icon(Icons.restore), label: const Text('Restore signature backup')),
        if (_busy) const LinearProgressIndicator(),
        if (_result != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_result!)),
      ])));
}
