import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'lru_future_cache.dart';
import 'pdf_service.dart';

class _PageItem {
  _PageItem({required this.originalIndex});

  final int originalIndex;
  int rotation = 0;
  bool selected = false;
}

class PageOrganizerScreen extends StatefulWidget {
  const PageOrganizerScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<PageOrganizerScreen> createState() => _PageOrganizerScreenState();
}

class _PageOrganizerScreenState extends State<PageOrganizerScreen> {
  File? _source;
  String? _password;
  final List<_PageItem> _pages = [];
  final LruFutureCache<int, Uint8List?> _thumbCache =
      LruFutureCache<int, Uint8List?>(capacity: 32);

  bool _busy = false;
  String _status = 'Choose a PDF to visually organize its pages.';

  @override
  void dispose() {
    _thumbCache.clear();
    super.dispose();
  }

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
            border: OutlineInputBorder(),
            labelText: 'Password',
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

  Future<Uint8List?> _thumbnailFor(int originalIndex) {
    final source = _source;
    if (source == null) return Future<Uint8List?>.value(null);
    return _thumbCache.getOrCreate(
      originalIndex,
      () => widget.service.renderPage(
        source,
        originalIndex,
        password: _password,
        width: 260,
      ),
    );
  }

  Future<void> _pick() async {
    final file = await widget.service.pickPdfFile();
    if (file == null) return;

    setState(() {
      _busy = true;
      _status = 'Reading page index…';
      _pages.clear();
      _thumbCache.clear();
      _source = file;
      _password = null;
    });

    try {
      while (true) {
        try {
          final count = await widget.service.pageCount(
            file,
            password: _password,
          );
          if (!mounted) return;
          setState(() {
            _pages
              ..clear()
              ..addAll([
                for (var i = 0; i < count; i++)
                  _PageItem(originalIndex: i),
              ]);
            _status =
                '$count page(s) — thumbnails load only when visible.';
          });
          break;
        } on PdfPasswordRequired {
          if (!mounted) return;
          final password = await _askPassword();
          if (password == null) return;
          _password = password;
        } on PdfWrongPassword {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wrong password. Try again.')),
          );
          final password = await _askPassword();
          if (password == null) return;
          _password = password;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not open PDF.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleAll() {
    if (_pages.isEmpty) return;
    final select = !_pages.every((e) => e.selected);
    setState(() {
      for (final page in _pages) {
        page.selected = select;
      }
    });
  }

  void _deleteSelected() {
    final count = _pages.where((e) => e.selected).length;
    if (count == 0) return;
    if (count == _pages.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one page must remain.')),
      );
      return;
    }
    setState(() {
      for (final page in _pages.where((e) => e.selected)) {
        _thumbCache.remove(page.originalIndex);
      }
      _pages.removeWhere((e) => e.selected);
      _status = '${_pages.length} page(s) remaining.';
    });
  }

  void _rotateSelected(int degrees) {
    setState(() {
      for (final page in _pages.where((e) => e.selected)) {
        page.rotation = (page.rotation + degrees) % 360;
        if (page.rotation < 0) page.rotation += 360;
      }
    });
  }

  Future<void> _save() async {
    final source = _source;
    if (source == null || _pages.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Saving organized PDF…';
    });

    try {
      final output = await widget.service.organizePdf(
        source,
        pageOrder: [for (final page in _pages) page.originalIndex],
        rotations: {
          for (var i = 0; i < _pages.length; i++)
            if (_pages[i].rotation != 0) i: _pages[i].rotation,
        },
        password: _password,
      );

      if (!mounted) return;
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Save failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Organizer failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _pages.where((e) => e.selected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Page organizer'),
        actions: [
          if (_pages.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(_source == null ? 'Choose PDF' : 'Change'),
                    ),
                  ],
                ),
              ),
            ),
            if (_pages.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _toggleAll,
                      icon: const Icon(Icons.select_all_rounded),
                      label: Text(
                        selectedCount == _pages.length
                            ? 'Clear selection'
                            : 'Select all',
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonalIcon(
                      onPressed: selectedCount == 0
                          ? null
                          : () => _rotateSelected(-90),
                      icon: const Icon(Icons.rotate_left_rounded),
                      label: const Text('Left'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: selectedCount == 0
                          ? null
                          : () => _rotateSelected(90),
                      icon: const Icon(Icons.rotate_right_rounded),
                      label: const Text('Right'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed:
                          selectedCount == 0 ? null : _deleteSelected,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text('Delete ($selectedCount)'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _busy && _pages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _pages.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.view_module_outlined, size: 84),
                              SizedBox(height: 12),
                              Text('No PDF selected'),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
                          itemCount: _pages.length,
                          onReorderItem: (oldIndex, newIndex) {
                            setState(() {
                              final item = _pages.removeAt(oldIndex);
                              _pages.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final page = _pages[index];
                            return Card(
                              key: ValueKey(
                                'page-${page.originalIndex}',
                              ),
                              child: ListTile(
                                onTap: () => setState(
                                  () => page.selected = !page.selected,
                                ),
                                leading: SizedBox(
                                  width: 58,
                                  height: 76,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        child: RotatedBox(
                                          quarterTurns:
                                              (page.rotation ~/ 90) % 4,
                                          child: FutureBuilder<Uint8List?>(
                                            future: _thumbnailFor(
                                              page.originalIndex,
                                            ),
                                            builder: (context, snapshot) {
                                              final bytes = snapshot.data;
                                              if (bytes == null) {
                                                return const Center(
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return Image.memory(
                                                bytes,
                                                fit: BoxFit.cover,
                                                gaplessPlayback: true,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                      if (page.selected)
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.22),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              width: 3,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                title: Text('Page ${index + 1}'),
                                subtitle: Text(
                                  'Original ${page.originalIndex + 1}'
                                  '${page.rotation == 0 ? '' : ' • ${page.rotation}°'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: page.selected,
                                      onChanged: (v) => setState(
                                        () => page.selected = v ?? false,
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
          ],
        ),
      ),
    );
  }
}
