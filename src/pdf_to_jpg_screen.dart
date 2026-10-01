import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_service.dart';

class PdfToJpgScreen extends StatefulWidget {
  const PdfToJpgScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<PdfToJpgScreen> createState() => _PdfToJpgScreenState();
}

class _PdfToJpgScreenState extends State<PdfToJpgScreen> {
  File? _source;
  final List<File> _images = [];
  final Set<int> _selected = {};
  bool _busy = false;
  PdfOperationControl? _operation;
  String _status = 'Choose a PDF to convert its pages to JPG.';

  Future<(int, int)?> _chooseRange(int count) async {
    final controller = TextEditingController(text: '1-$count');
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pages to convert'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Range, e.g. 1-10 (1-$count)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Convert')),
        ],
      ),
    );
    controller.dispose();
    if (raw == null) return null;
    final match = RegExp(r'^(\d+)-(\d+)$').firstMatch(raw.trim());
    final first = int.tryParse(match?.group(1) ?? '');
    final last = int.tryParse(match?.group(2) ?? '');
    if (first == null || last == null || first < 1 || last < first || last > count) {
      throw FormatException('Choose pages between 1 and $count.');
    }
    return (first - 1, last);
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
          autofocus: true,
          obscureText: true,
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

  Future<void> _pickAndConvert() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final previous = _source;
      final picked = await widget.service.pickPdfFile();
      if (picked == null) return;
      if (!mounted) {
        await widget.service.secureDeleteTemporary(picked);
        return;
      }
      var file = picked;

      setState(() {
        _busy = true;

        _status = 'Converting pages…';
      });

      try {
        while (true) {
          try {
            final count = await widget.service.pageCount(file);
            if (!mounted) return;
            final range = await _chooseRange(count);
            if (range == null || !mounted) return;
            _operation = PdfOperationControl(onProgress: (done, total) {
              if (mounted) setState(() => _status = 'Converting ${done + 1} of $total pages…');
            });
            final outputs = await widget.service.pdfToJpgFromFile(file,
              startPage: range.$1, endPage: range.$2, control: _operation);
            if (!mounted) {
              for (final output in outputs) {
                await widget.service.secureDeleteTemporary(output);
              }
              return;
            }
            final previousImages = List<File>.of(_images);
            setState(() {
              _source = file;
              _images
                ..clear()
                ..addAll(outputs);
              _selected
                ..clear()
                ..addAll(List<int>.generate(outputs.length, (i) => i));
              _status = 'Converted ${outputs.length} page(s).';
            });
            for (final image in previousImages) {
              await widget.service.secureDeleteTemporary(image);
            }
            break;
          } on PdfPasswordRequired {
            if (!mounted) return;
            var wrong = false;
            while (true) {
              final password = await _askPassword(wrong: wrong);
              if (password == null) return;
              try {
                file = await widget.service.decryptToTemporary(file, password);
                break;
              } on PdfWrongPassword {
                wrong = true;
              }
            }
          }
        }
      } on PdfOperationCancelled {
        if (mounted) setState(() => _status = 'Conversion cancelled.');
      } catch (e) {
        if (mounted) {
          setState(() => _status = 'Conversion failed.');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('PDF to JPG failed: $e')));
        }
      } finally {
        _operation = null;
        if (picked.path != file.path) {
          await widget.service.secureDeleteTemporary(picked);
        }
        if (_source?.path != file.path || !mounted) {
          await widget.service.secureDeleteTemporary(file);
        }
        if (_source?.path != previous?.path) {
          await widget.service.secureDeleteTemporary(previous);
        }
        if (mounted) setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not choose PDF: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareSelected() async {
    if (_selected.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (final i in _selected.toList()..sort()) XFile(_images[i].path),
        ],
        text: 'PDF pages exported by PDFMate',
      ),
    );
  }

  Future<void> _saveSelected() async {
    if (_selected.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Saving to Gallery/PDFMate…';
    });

    final failed = <int>[];
    var saved = 0;
    try {
      for (final i in _selected.toList()..sort()) {
        try {
          await widget.service.saveJpgToGallery(_images[i]);
          saved++;
        } catch (_) {
          failed.add(i);
        }
      }

      if (!mounted) return;
      setState(() {
        _status = failed.isEmpty
            ? 'Saved $saved image(s) to Gallery/PDFMate.'
            : 'Saved $saved image(s); ${failed.length} failed.';
      });

      if (failed.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved $saved JPG image(s)')));
        return;
      }

      final retry = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some images were not saved'),
          content: Text(
            '${failed.length} JPG image(s) were not confirmed by Android. '
            'Retry only the failed pages?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

      if (retry == true) {
        var recovered = 0;
        for (final i in failed) {
          try {
            await widget.service.saveJpgToGallery(_images[i]);
            recovered++;
          } catch (_) {}
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recovered == failed.length
                  ? 'All failed JPGs saved on retry.'
                  : 'Recovered $recovered of ${failed.length} failed JPGs.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _images.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(List<int>.generate(_images.length, (i) => i));
      }
    });
  }

  @override
  void dispose() {
    _operation?.cancel();
    for (final file in _images) {
      unawaited(widget.service.secureDeleteTemporary(file));
    }
    unawaited(widget.service.secureDeleteTemporary(_source));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _images.isNotEmpty && _selected.length == _images.length;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PDF to JPG'),
          actions: [
            if (_images.isNotEmpty)
              TextButton(
                onPressed: _busy ? null : _toggleAll,
                child: Text(allSelected ? 'Clear' : 'Select all'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (_source == null ? null : widget.service.displayName(_source!)) ?? _status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _pickAndConvert,
                      child: Text(_source == null ? 'Choose PDF' : 'Change'),
                    ),
                  ],
                ),
              ),
              if (_busy) ...[
                const LinearProgressIndicator(),
                if (_operation != null) TextButton(
                  onPressed: () => _operation?.cancel(),
                  child: const Text('Cancel conversion'),
                ),
              ],
              Expanded(
                child: _images.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_status, textAlign: TextAlign.center),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 0.72,
                            ),
                        itemCount: _images.length,
                        itemBuilder: (context, index) {
                          final selected = _selected.contains(index);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _selected.remove(index);
                              } else {
                                _selected.add(index);
                              }
                            }),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    _images[index],
                                    fit: BoxFit.cover,
                                    cacheWidth: 360,
                                  ),
                                ),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      'Page ${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 5,
                                  right: 5,
                                  child: CircleAvatar(
                                    radius: 13,
                                    backgroundColor: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black45,
                                    child: Icon(
                                      selected
                                          ? Icons.check_rounded
                                          : Icons.circle_outlined,
                                      size: 17,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (_images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_busy || _selected.isEmpty)
                              ? null
                              : _shareSelected,
                          icon: const Icon(Icons.share_rounded),
                          label: Text('Share (${_selected.length})'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_busy || _selected.isEmpty)
                              ? null
                              : _saveSelected,
                          icon: const Icon(Icons.photo_library_rounded),
                          label: Text('Save (${_selected.length})'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
