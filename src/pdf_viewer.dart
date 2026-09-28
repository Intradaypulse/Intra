import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfx/pdfx.dart';

import 'pdf_service.dart';

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({
    super.key,
    required this.path,
    required this.title,
  });

  final String path;
  final String title;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfService _service = PdfService();

  PdfControllerPinch? _controller;
  String? _workingPath;
  File? _temporaryDecrypted;
  List<Uint8List> _thumbs = [];

  int _page = 1;
  int _pages = 0;
  bool _busy = true;
  bool _showThumbs = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
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
            labelText: 'Password',
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

  Future<void> _prepare() async {
    var source = File(widget.path);

    try {
      // Preflight with the PDF engine so protected PDFs can be handled before
      // pdfx (Android's native PdfRenderer) attempts to open them.
      while (true) {
        final pdf = Pdf();
        PdfDoc? doc;
        try {
          doc = await pdf.open(FileSource(source));
          _pages = doc.pageCount;
          break;
        } on PdfPasswordRequired {
          if (!mounted) return;
          var wrong = false;
          while (true) {
            final password = await _askPassword(wrong: wrong);
            if (password == null) {
              if (mounted) Navigator.of(context).pop();
              return;
            }
            try {
              final decrypted =
                  await _service.decryptToTemporary(source, password);
              _temporaryDecrypted = decrypted;
              source = decrypted;
              break;
            } on PdfWrongPassword {
              wrong = true;
              continue;
            }
          }
          continue;
        } finally {
          await doc?.dispose();
          await pdf.dispose();
        }
      }

      final thumbs = await _service.renderThumbnails(source, width: 130);
      if (!mounted) return;

      final controller = PdfControllerPinch(
        document: PdfDocument.openFile(source.path),
      );

      setState(() {
        _workingPath = source.path;
        _thumbs = thumbs;
        _controller = controller;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not open PDF: $e';
        });
      }
    }
  }

  Future<void> _jumpToPage() async {
    if (_pages <= 0) return;
    final input = TextEditingController(text: '$_page');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to page'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            helperText: '1 – $_pages',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(input.text.trim());
              if (page != null && page >= 1 && page <= _pages) {
                Navigator.pop(context, page);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null) return;
    _controller?.jumpToPage(value);
  }

  Future<void> _search() async {
    final path = _workingPath;
    if (path == null) return;

    final input = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search PDF text'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter text',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = input.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
    input.dispose();
    if (query == null || query.isEmpty) return;

    setState(() => _busy = true);
    final matches = <int>[];
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(File(path)));
      final needle = query.toLowerCase();
      for (var i = 0; i < doc.pageCount; i++) {
        final text = await doc.extract(pages: PdfPages.single(i));
        if (text.toLowerCase().contains(needle)) matches.add(i + 1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      await doc?.dispose();
      await pdf.dispose();
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text match found.')),
      );
      return;
    }

    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('${matches.length} matching page(s)'),
              subtitle: Text('“$query”'),
            ),
            for (final page in matches)
              ListTile(
                leading: const Icon(Icons.find_in_page_outlined),
                title: Text('Page $page'),
                onTap: () => Navigator.pop(context, page),
              ),
          ],
        ),
      ),
    );

    if (page != null) _controller?.jumpToPage(page);
  }

  @override
  void dispose() {
    _controller?.dispose();
    unawaited(_service.secureDeleteTemporary(_temporaryDecrypted));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pages > 0)
            TextButton(
              onPressed: _jumpToPage,
              child: Text('$_page / $_pages'),
            ),
          IconButton(
            tooltip: 'Search',
            onPressed: (_busy || controller == null) ? null : _search,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Page thumbnails',
            onPressed: _thumbs.isEmpty
                ? null
                : () => setState(() => _showThumbs = !_showThumbs),
            icon: Icon(
              _showThumbs
                  ? Icons.view_sidebar_rounded
                  : Icons.view_module_outlined,
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _busy && controller == null
              ? const Center(child: CircularProgressIndicator())
              : controller == null
                  ? const SizedBox.shrink()
                  : Stack(
                      children: [
                        Row(
                          children: [
                            if (_showThumbs)
                              SizedBox(
                                width: 92,
                                child: Material(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    itemCount: _thumbs.length,
                                    itemBuilder: (context, index) {
                                      final selected = index + 1 == _page;
                                      return GestureDetector(
                                        onTap: () =>
                                            controller.jumpToPage(index + 1),
                                        child: Container(
                                          margin: const EdgeInsets.fromLTRB(
                                            8,
                                            4,
                                            8,
                                            4,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: selected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Column(
                                            children: [
                                              Image.memory(
                                                _thumbs[index],
                                                fit: BoxFit.contain,
                                              ),
                                              Text(
                                                '${index + 1}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            Expanded(
                              child: PdfViewPinch(
                                controller: controller,
                                onPageChanged: (page) {
                                  if (mounted) {
                                    setState(() => _page = page);
                                  }
                                },
                                onDocumentLoaded: (document) {
                                  if (mounted) {
                                    setState(
                                      () => _pages = document.pagesCount,
                                    );
                                  }
                                },
                                onDocumentError: (error) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not render PDF: $error',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        if (_busy)
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
    );
  }
}
