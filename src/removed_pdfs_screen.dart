import 'package:flutter/material.dart';
import 'file_store.dart';

class RemovedPdfsScreen extends StatefulWidget {
  const RemovedPdfsScreen({super.key, required this.store});
  final PdfFileStore store;
  @override State<RemovedPdfsScreen> createState() => _RemovedPdfsScreenState();
}
class _RemovedPdfsScreenState extends State<RemovedPdfsScreen> {
  List<PdfRecord> _records = [];
  bool _busy = true;
  String? _error;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final records = await widget.store.loadRemoved();
      if (mounted) setState(() { _records = records; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load removed PDFs.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _restore(PdfRecord record) async {
    setState(() => _busy = true);
    try {
      await widget.store.restoreRemoved(record);
      await _load();
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF restored to My PDFs.'))); }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore failed. The file may have been moved or deleted.'))); }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !_busy,
    child: Scaffold(appBar: AppBar(title: const Text('Removed PDFs')),
      body: Column(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text(
          'These PDFs are still stored on your device. Restore them to My PDFs. Permanently deleted files are not listed.')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ListTile(title: Text(_error!),
          trailing: TextButton(onPressed: _busy ? null : _load, child: const Text('Retry'))),
        Expanded(child: _records.isEmpty && !_busy
          ? const Center(child: Text('No removed PDFs to restore.'))
          : ListView.builder(itemCount: _records.length, itemBuilder: (_, index) {
            final record = _records[index];
            return ListTile(leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(record.name),
              trailing: TextButton(onPressed: _busy ? null : () => _restore(record), child: const Text('Restore')));
          })),
      ])));
}
