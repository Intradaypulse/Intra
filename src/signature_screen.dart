import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:signature/signature.dart';
import 'signature_store.dart';
import 'signature_backup_screen.dart';
import 'signature_image.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, this.store});
  final SignatureStore? store;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  late final SignatureController _controller;
  bool _exporting = false;
  bool _saveForReuse = true;
  final _name = TextEditingController(text: 'My signature');
  late final SignatureStore _store;
  Uint8List? _lastSaved;
  String? _lastSavedName;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SignatureStore();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _done({bool close = true}) async {
    if (_exporting || _controller.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final bytes = await exportSignaturePng(_controller);
      if (!mounted) return;
      if (_saveForReuse && (!listEquals(_lastSaved, bytes) || _lastSavedName != _name.text.trim())) {
        await _store.save(_name.text, bytes);
        _lastSaved = bytes;
        _lastSavedName = _name.text.trim();
      }
      if (!mounted) return;
      if (close) {
        Navigator.of(context).pop(bytes);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signature saved for reuse.')));
      }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signature export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saved() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      var signatures = await _store.load();
      var deleting = false;
      if (!mounted) return;
      final selected = await showDialog<SavedSignature>(context: context,
        builder: (context) => StatefulBuilder(builder: (context, refresh) => AlertDialog(
          title: const Text('Saved signatures'),
          content: SizedBox(width: 360, height: 300, child: signatures.isEmpty
            ? const Center(child: Text('Draw a signature, then tap Save signature.'))
            : ListView.builder(itemCount: signatures.length, itemBuilder: (context, index) {
              final signature = signatures[index];
              return ListTile(title: Text(signature.name),
                leading: Container(color: Colors.white, width: 80, height: 44,
                  child: Image.file(signature.file, cacheWidth: 200,
                    errorBuilder: (_, error, stack) => const Icon(Icons.broken_image))),
                onTap: deleting ? null : () => Navigator.pop(context, signature),
                trailing: IconButton(tooltip: 'Delete saved signature', icon: const Icon(Icons.delete_outline),
                  onPressed: deleting ? null : () async {
                    refresh(() => deleting = true);
                    try {
                      await _store.delete(signature);
                      signatures = await _store.load();
                      if (context.mounted) refresh(() {});
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                    } finally { if (context.mounted) refresh(() => deleting = false); }
                  }),
              );
            })),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        )));
      if (selected == null) return;
      final bytes = trimSignaturePng(await selected.file.readAsBytes());
      if (mounted) Navigator.pop(context, bytes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load signatures: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !_exporting, child: Scaffold(
      appBar: AppBar(
        title: const Text('Draw signature'),
        actions: [
          IconButton(tooltip: 'Signature backup', icon: const Icon(Icons.backup_outlined),
            onPressed: _exporting ? null : () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => SignatureBackupScreen(store: _store)))),
          IconButton(tooltip: 'Saved signatures', onPressed: _exporting ? null : _saved,
            icon: const Icon(Icons.history_edu)),
          IconButton(
            tooltip: 'Clear',
            onPressed: _exporting ? null : _controller.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sign inside the box. Next, choose the page and position for your signature.',
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: IgnorePointer(ignoring: _exporting, child: Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                    )),
                  ),
                ),
              ),
            ),
            CheckboxListTile(value: _saveForReuse, title: const Text('Save for reuse'),
              onChanged: _exporting ? null : (value) => setState(() => _saveForReuse = value!)),
            if (_saveForReuse) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(controller: _name, enabled: !_exporting, maxLength: 60,
                decoration: const InputDecoration(labelText: 'Signature name'))),
            if (_saveForReuse) OutlinedButton.icon(
              onPressed: _exporting ? null : () => _done(close: false),
              icon: const Icon(Icons.save_outlined), label: const Text('Save signature')),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _exporting ? null : _done,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Use signature'),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
