import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:pdfx/pdfx.dart';

import 'lru_future_cache.dart';
import 'pdf_service.dart';
import 'ocr_page_preview_screen.dart';

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
  final LruFutureCache<int, Uint8List?> _thumbCache =
      LruFutureCache<int, Uint8List?>(capacity: 24);

  int _page = 1;
  int _pages = 0;
  bool _busy = true;
  bool _preparing = false;
  bool _showThumbs = false;
  bool _searchCancelled = false;
  bool _searching = false;
  int _searchProgress = 0;
  final Map<int, String> _searchText = {};
  int _searchTextCharacters = 0;
  static const _searchCacheLimit = 2 * 1024 * 1024;
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
    if (!mounted || _preparing) return;
    _preparing = true;
    final oldController = _controller;
    final oldTemporary = _temporaryDecrypted;
    setState(() {
      _busy = true;
      _error = null;
      _controller = null;
      _temporaryDecrypted = null;
      _workingPath = null;
      _pages = 0;
      _page = 1;
      _thumbCache.clear();
      _searchText.clear();
      _searchTextCharacters = 0;
    });
    oldController?.dispose();
    var source = File(widget.path);

    try {
      if (oldTemporary != null) await _service.secureDeleteTemporary(oldTemporary);
      if (!mounted) return;
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
              if (!mounted) {
                await _service.secureDeleteTemporary(decrypted);
                return;
              }
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

      if (!mounted) return;

      final controller = PdfControllerPinch(
        document: PdfDocument.openFile(source.path),
      );

      setState(() {
        _workingPath = source.path;
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
    } finally {
      _preparing = false;
    }
  }

  Future<Uint8List?> _thumbnailFor(int index) {
    final path = _workingPath;
    if (path == null) return Future<Uint8List?>.value(null);
    final control = PdfOperationControl();
    return _thumbCache.getOrCreate(
      index,
      () => _service.renderPage(
        File(path),
        index,
        width: 130,
        control: control,
      ),
      onDiscard: control.cancel,
    );
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
    if (!mounted || query == null || query.isEmpty) return;

    setState(() {
      _busy = true;
      _searchCancelled = false;
      _searching = true;
      _searchProgress = 0;
    });
    final matches = <(int, String)>[];
    var failed = false;
    final pdf = Pdf();
    PdfDoc? doc;
    try {
      doc = await pdf.open(FileSource(File(path)));
      final needle = query.toLowerCase();
      for (var i = 0; i < doc.pageCount; i++) {
        if (_searchCancelled) break;
        var text = _searchText[i];
        if (text == null) {
          text = await doc.extract(pages: PdfPages.single(i));
          if (_searchCancelled) break;
          if (mounted && _searchTextCharacters + text.length <= _searchCacheLimit) {
            _searchText[i] = text;
            _searchTextCharacters += text.length;
          }
        }
        final index = text.toLowerCase().indexOf(needle);
        if (index >= 0) {
          final start = index > 48 ? index - 48 : 0;
          final end = index + query.length + 48 < text.length
              ? index + query.length + 48 : text.length;
          matches.add((i + 1, text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ')));
        }
        if (mounted && i % 5 == 0) setState(() => _searchProgress = i + 1);
      }
    } catch (e) {
      failed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      await doc?.dispose();
      await pdf.dispose();
      if (mounted) setState(() { _busy = false; _searching = false; });
    }

    if (!mounted) return;
    if (failed) return;
    if (_searchCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search cancelled.')),
      );
      return;
    }
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
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: matches.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) { return ListTile(
              title: Text('${matches.length} matching page(s)'),
              subtitle: Text('“$query”'),
            );
            }
            final match = matches[index - 1];
            return ListTile(
              leading: const Icon(Icons.find_in_page_outlined),
              title: Text('Page ${match.$1}'),
              subtitle: _highlightMatch(match.$2, query),
              onTap: () => Navigator.pop(context, match.$1),
            );
          },
        ),
      ),
    );

    if (page != null) _controller?.jumpToPage(page);
  }

  Widget _highlightMatch(String snippet, String query) {
    final index = snippet.toLowerCase().indexOf(query.toLowerCase());
    if (index < 0) {
      return Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: snippet.substring(0, index)),
        TextSpan(
          text: snippet.substring(index, index + query.length),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
          ),
        ),
        TextSpan(text: snippet.substring(index + query.length)),
      ]),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  void dispose() {
    _searchCancelled = true;
    _searchText.clear();
    _controller?.dispose();
    _thumbCache.clear();
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
          IconButton(tooltip: 'Scan and copy text on this page',
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: _busy || _workingPath == null || _searching ? null : () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => OcrPagePreviewScreen(
                service: _service, source: File(_workingPath!), initialPage: _page - 1, pageCount: _pages)));
            }),
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
            onPressed: _pages <= 0
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _prepare, child: const Text('Retry')),
                ]),
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
                                    itemCount: _pages,
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
                                              FutureBuilder<Uint8List?>(
                                                future: _thumbnailFor(index),
                                                builder: (context, snapshot) {
                                                  final bytes = snapshot.data;
                                                  if (bytes == null) {
                                                    if (snapshot.hasError ||
                                                        snapshot.connectionState == ConnectionState.done) {
                                                      return IconButton(
                                                        tooltip: 'Retry thumbnail',
                                                        onPressed: () => setState(() => _thumbCache.remove(index)),
                                                        icon: const Icon(Icons.refresh),
                                                      );
                                                    }
                                                    return const SizedBox(
                                                      height: 96,
                                                      child: Center(
                                                        child: SizedBox(
                                                          width: 18,
                                                          height: 18,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return Image.memory(
                                                    bytes,
                                                    fit: BoxFit.contain,
                                                    gaplessPlayback: true,
                                                  );
                                                },
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
                                key: const ValueKey('pdf_native_viewer'),
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
                                    setState(() {
                                      _busy = false;
                                      _error = 'Could not render PDF: $error';
                                    });
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
                        if (_searching)
                          Positioned(
                            left: 8, right: 8, top: 8,
                            child: Material(
                              child: ListTile(
                                title: Text(_searchCancelled ? 'Cancelling search…' : _searchProgress == 0 ? 'Preparing search…' : 'Searching page $_searchProgress / $_pages'),
                                trailing: TextButton(
                                  onPressed: _searchCancelled ? null : () => setState(() => _searchCancelled = true),
                                  child: const Text('Cancel'),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
