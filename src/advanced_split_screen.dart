import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

import 'pdf_service.dart';

enum SplitMode { everyPage, everyN, custom, selected }

class AdvancedSplitScreen extends StatefulWidget {
  const AdvancedSplitScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<AdvancedSplitScreen> createState() => _AdvancedSplitScreenState();
}

class _AdvancedSplitScreenState extends State<AdvancedSplitScreen> {
  File? _source;
  String? _password;
  int _pageCount = 0;
  SplitMode _mode = SplitMode.selected;
  final Set<int> _selectedPages = {};
  final _everyController = TextEditingController(text: '5');
  final _rangeController = TextEditingController(text: '1-3;4-6');
  bool _busy = false;
  String _status = 'Choose a PDF, then define how it should be split.';

  @override
  void dispose() {
    unawaited(widget.service.secureDeleteTemporary(_source));
    _everyController.dispose();
    _rangeController.dispose();
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

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? file;
    try {
      file = await widget.service.pickPdfFile();
      if (file == null) return;
      if (!mounted) return;
      setState(() => _status = 'Reading PDF…');
      String? password;
      while (true) {
        try {
          final count = await widget.service.pageCount(
            file,
            password: password,
          );
          if (!mounted) return;
          final previous = _source;
          setState(() {
            _source = file;
            _password = password;
            _pageCount = count;
            _selectedPages.clear();
            _status = '$count pages ready to split.';
          });
          if (previous?.path != file.path) {
            await widget.service.secureDeleteTemporary(previous);
          }
          break;
        } on PdfPasswordRequired {
          if (!mounted) return;
          final entered = await _askPassword();
          if (entered == null) return;
          password = entered;
        } on PdfWrongPassword {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wrong password.')),
          );
          final entered = await _askPassword();
          if (entered == null) return;
          password = entered;
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
      if (file != null && (_source?.path != file.path || !mounted)) {
        await widget.service.secureDeleteTemporary(file);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  List<List<int>> _parseCustomRanges(String raw) {
    if (_pageCount <= 0) {
      throw const FormatException('Choose a PDF first.');
    }

    final groups = <List<int>>[];
    final outputGroups = raw
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    for (final groupText in outputGroups) {
      final pages = <int>{};
      final parts = groupText
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);

      for (final part in parts) {
        if (part.contains('-')) {
          final pieces = part.split('-');
          if (pieces.length != 2) {
            throw FormatException('Invalid range: $part');
          }
          final start = int.tryParse(pieces[0].trim());
          final end = int.tryParse(pieces[1].trim());
          if (start == null || end == null || start < 1 || end < start) {
            throw FormatException('Invalid range: $part');
          }
          if (end > _pageCount) {
            throw FormatException(
              'Page $end is outside this $_pageCount-page PDF.',
            );
          }
          for (var p = start; p <= end; p++) {
            pages.add(p - 1);
          }
        } else {
          final page = int.tryParse(part);
          if (page == null || page < 1 || page > _pageCount) {
            throw FormatException('Invalid page: $part');
          }
          pages.add(page - 1);
        }
      }

      if (pages.isEmpty) {
        throw const FormatException('Each output group needs at least one page.');
      }
      final sorted = pages.toList()..sort();
      groups.add(sorted);
    }

    if (groups.isEmpty) {
      throw const FormatException('Enter at least one page range.');
    }
    return groups;
  }

  Future<void> _run() async {
    if (_busy) return;
    final source = _source;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a PDF first.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Splitting PDF…';
    });

    try {
      late final List<File> outputs;
      switch (_mode) {
        case SplitMode.everyPage:
          outputs = await widget.service.splitEveryN(
            source,
            1,
            password: _password,
          );
        case SplitMode.everyN:
          final every = int.tryParse(_everyController.text.trim());
          if (every == null || every < 1 || every > _pageCount) {
            throw FormatException(
              'Pages per file must be between 1 and $_pageCount.',
            );
          }
          outputs = await widget.service.splitEveryN(
            source,
            every,
            password: _password,
          );
        case SplitMode.selected:
          if (_selectedPages.isEmpty) throw const FormatException('Select at least one page.');
          outputs = await widget.service.splitRanges(source,
            [_selectedPages.toList()..sort()], password: _password);
        case SplitMode.custom:
          final ranges = _parseCustomRanges(_rangeController.text);
          outputs = await widget.service.splitRanges(
            source,
            ranges,
            password: _password,
          );
      }

      if (!mounted) {
        for (final output in outputs) {
          try { await output.delete(); } catch (_) {}
        }
        return;
      }
      Navigator.of(context).pop<List<File>>(outputs);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Split failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Split failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Advanced split')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(
                    (_source == null ? null : widget.service.displayName(_source!)) ?? 'No PDF selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _pageCount == 0 ? _status : '$_pageCount pages',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _busy ? null : _pick,
                    child: const Text('Choose'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SplitMode>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'Split mode'),
                items: const [
                  DropdownMenuItem(value: SplitMode.selected, child: Text('Select page numbers')),
                  DropdownMenuItem(value: SplitMode.everyPage, child: Text('Each page')),
                  DropdownMenuItem(value: SplitMode.everyN, child: Text('Every N pages')),
                  DropdownMenuItem(value: SplitMode.custom, child: Text('Custom output groups')),
                ],
                onChanged: _busy ? null : (value) => setState(() => _mode = value!),
              ),
              const SizedBox(height: 20),
              if (_mode == SplitMode.selected) ...[
                Text('${_selectedPages.length} pages selected • one output PDF'),
                if (_pageCount > 0) SizedBox(height: 280, child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130, mainAxisExtent: 56),
                  itemCount: _pageCount,
                  itemBuilder: (context, index) => CheckboxListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    title: Text('${index + 1}'), value: _selectedPages.contains(index),
                    onChanged: _busy ? null : (checked) => setState(() {
                      if (checked == true) { _selectedPages.add(index); }
                      else { _selectedPages.remove(index); }
                    }),
                  ),
                )),
              ],
              if (_mode == SplitMode.everyPage)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('One PDF file will be created for every page.'),
                ),
              if (_mode == SplitMode.everyN)
                TextField(
                  controller: _everyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Pages per output file',
                    hintText: 'Example: 5',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_mode == SplitMode.custom) ...[
                TextField(
                  controller: _rangeController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Custom output groups',
                    hintText: '1-3;4-6;7,9,11',
                    helperText:
                        'Use semicolon between output files. Use commas/ranges inside each file.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Example: 1-3;4-6;7,9 creates 3 PDFs: pages 1–3, pages 4–6, and pages 7 + 9.',
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed:
                    (_busy || _source == null || _pageCount == 0) ? null : _run,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.content_cut_rounded),
                label: const Text('Split PDF'),
              ),
              const SizedBox(height: 12),
              Text(_status),
            ],
          ),
        ),
      ),
    );
  }
}
