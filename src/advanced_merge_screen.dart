import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'pdf_service.dart';

class _MergeItem {
  _MergeItem({
    required this.file,
    required this.name,
    required this.size,
    this.thumb,
  });

  File file;
  final String name;
  final int size;
  Uint8List? thumb;
}

class AdvancedMergeScreen extends StatefulWidget {
  const AdvancedMergeScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<AdvancedMergeScreen> createState() => _AdvancedMergeScreenState();
}

class _AdvancedMergeScreenState extends State<AdvancedMergeScreen> {
  final List<_MergeItem> _items = [];
  bool _busy = false;
  String _status = 'Add two or more PDFs, then drag to choose merge order.';

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<String?> _askPassword(String name) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Protected PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _add() async {
    final files = await widget.service.pickPdfFiles();
    if (files.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Preparing PDFs…';
    });

    try {
      for (var file in files) {
        final name = file.uri.pathSegments.last;
        Uint8List? thumb;

        while (true) {
          try {
            thumb = await widget.service.renderFirstThumbnail(file);
            break;
          } on PdfPasswordRequired {
            if (!mounted) return;
            final password = await _askPassword(name);
            if (password == null) {
              file = File('');
              break;
            }
            try {
              file = await widget.service.decryptToTemporary(file, password);
              thumb = await widget.service.renderFirstThumbnail(file);
              break;
            } on PdfWrongPassword {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wrong password.')),
                );
              }
            }
          }
        }

        if (file.path.isEmpty) continue;
        if (!mounted) return;
        final size = await file.length();
        setState(() {
          _items.add(
            _MergeItem(
              file: file,
              name: name,
              size: size,
              thumb: thumb,
            ),
          );
        });
      }

      if (mounted) {
        setState(() {
          _status = '${_items.length} PDF(s). Drag to reorder before merging.';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    if (_items.length < 2) return;
    setState(() {
      _busy = true;
      _status = 'Merging ${_items.length} PDFs…';
    });

    try {
      final output = await widget.service.mergeFiles(
        [for (final item in _items) item.file],
      );
      if (!mounted) return;
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Merge failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Merge failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      unawaited(widget.service.secureDeleteTemporary(item.file));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
        actions: [
          IconButton(
            tooltip: 'Add PDFs',
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(child: Text(_status)),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_merge_rounded, size: 84),
                          SizedBox(height: 12),
                          Text('Add PDFs to begin'),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                      itemCount: _items.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final item = _items.removeAt(oldIndex);
                          _items.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Card(
                          key: ValueKey(
                            '${item.file.path}-$index',
                          ),
                          child: ListTile(
                            leading: SizedBox(
                              width: 52,
                              height: 68,
                              child: item.thumb == null
                                  ? const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color(0x11000000),
                                      ),
                                      child: Icon(
                                        Icons.picture_as_pdf_rounded,
                                      ),
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.memory(
                                        item.thumb!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                            ),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '#${index + 1} • ${_formatBytes(item.size)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                            () => _items.removeAt(index),
                                          ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                                const Icon(Icons.drag_handle_rounded),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      (_busy || _items.length < 2) ? null : _merge,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.call_merge_rounded),
                  label: Text('Merge ${_items.length} PDFs'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
