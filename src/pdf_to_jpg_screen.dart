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
  String _status = 'Choose a PDF to convert its pages to JPG.';

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
    final picked = await widget.service.pickPdfFile();
    if (picked == null) return;
    var file = picked;

    setState(() {
      _busy = true;
      _source = file;
      _images.clear();
      _selected.clear();
      _status = 'Converting pages…';
    });

    try {
      while (true) {
        try {
          final outputs = await widget.service.pdfToJpgFromFile(file);
          if (!mounted) return;
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
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Conversion failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF to JPG failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareSelected() async {
    if (_selected.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (final i in _selected.toList()..sort())
            XFile(_images[i].path),
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
    var saved = 0;
    try {
      for (final i in _selected.toList()..sort()) {
        final result = await widget.service.saveJpgToGallery(_images[i]);
        if (result != null) saved++;
      }
      if (!mounted) return;
      setState(() => _status = 'Saved $saved image(s) to Gallery/PDFMate.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved JPG image(s)')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery save failed: $e')),
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
    for (final file in _images) {
      file.delete().catchError((_) => file);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _images.isNotEmpty && _selected.length == _images.length;

    return Scaffold(
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
                      _source?.uri.pathSegments.last ?? _status,
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
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _images.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                        ),
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
                        onPressed:
                            (_busy || _selected.isEmpty) ? null : _shareSelected,
                        icon: const Icon(Icons.share_rounded),
                        label: Text('Share (${_selected.length})'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            (_busy || _selected.isEmpty) ? null : _saveSelected,
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
    );
  }
}
