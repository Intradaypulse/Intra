import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'signature_store.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  late final SignatureController _controller;
  bool _exporting = false;
  bool _saveForReuse = false;
  final _name = TextEditingController(text: 'My signature');
  final _store = SignatureStore();

  @override
  void initState() {
    super.initState();
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

  Future<void> _done() async {
    if (_exporting || _controller.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final Uint8List? bytes = await _controller.toPngBytes(width: 900, height: 400);
      if (!mounted) return;
      if (bytes == null) throw StateError('Could not export signature.');
      if (_saveForReuse) await _store.save(_name.text, bytes);
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
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
            ? const Center(child: Text('Draw a signature and enable Save for reuse.'))
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
      final bytes = await selected.file.readAsBytes();
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
                    child: Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            CheckboxListTile(value: _saveForReuse, title: const Text('Save for reuse'),
              onChanged: _exporting ? null : (value) => setState(() => _saveForReuse = value!)),
            if (_saveForReuse) Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(controller: _name, enabled: !_exporting, maxLength: 60,
                decoration: const InputDecoration(labelText: 'Signature name'))),
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
