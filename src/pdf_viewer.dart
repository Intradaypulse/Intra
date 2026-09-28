import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

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
  late final PdfControllerPinch _controller;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.path),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pages > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('$_page / $_pages')),
            ),
        ],
      ),
      body: PdfViewPinch(
        controller: _controller,
        onPageChanged: (page) => setState(() => _page = page),
        onDocumentLoaded: (document) =>
            setState(() => _pages = document.pagesCount),
        onDocumentError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open PDF: $error')),
          );
        },
      ),
    );
  }
}
