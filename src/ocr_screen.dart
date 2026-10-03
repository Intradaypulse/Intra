import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';
import 'package:share_plus/share_plus.dart';

import 'ads_service.dart';
import 'pdf_service.dart';
import 'pdf_rules.dart';
import 'ocr_languages.dart';
import 'ocr_page_preview_screen.dart';
import 'telemetry_service.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key, required this.service});

  final PdfService service;

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  File? _source;
  PdfOperationControl? _operation;
  TextRecognitionScript _script = TextRecognitionScript.latin;
  OcrLanguage _language = ocrLanguages.first;
  bool _busy = false;
  int _pageCount = 0;
  bool _heavyUnlocked = false;
  bool _hasDigitalSignatures = false;
  String? _password;
  bool _tableRows = false;
  String _status = 'Choose a PDF to OCR.';
  String? _extractedText;
  File? _textFile;

  String _scriptLabel(TextRecognitionScript script) => switch (script) {
    TextRecognitionScript.latin => 'Latin',
    TextRecognitionScript.chinese => 'Chinese',
    TextRecognitionScript.devanagiri => 'Devanagari / Hindi',
    TextRecognitionScript.japanese => 'Japanese',
    TextRecognitionScript.korean => 'Korean',
  };

  Future<String?> _askPassword({bool owner = false, bool wrong = false}) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(owner ? (wrong ? 'Wrong owner password. Try again' : 'Owner password required') : 'PDF password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: owner ? 'Owner password' : 'Password',
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

  Future<void> _pick() async {
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
      final file = picked;
      String? candidatePassword;

      setState(() {
        _busy = true;
        _extractedText = null;
        _status = 'Checking PDF…';
      });

      try {
        while (true) {
          try {
            final count = await widget.service.pageCount(
              file,
              password: candidatePassword,
            );
            if (!mounted) return;
            final signed = await widget.service.hasDigitalSignatures(
              file,
              password: candidatePassword,
            );
            if (!mounted) return;
            setState(() {
              _source = file;
              _password = candidatePassword;
              _pageCount = count;
              _heavyUnlocked =
                  count <= TelemetryService.instance.rewardedOcrThresholdPages;
              _hasDigitalSignatures = signed;
              _status = signed
                  ? '$count page(s) • digitally signed document'
                  : '$count page(s) ready for OCR.';
            });
            break;
          } on PdfPasswordRequired {
            if (!mounted) return;
            candidatePassword = await _askPassword();
            if (candidatePassword == null) return;
          } on PdfWrongPassword {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Wrong password.')));
            candidatePassword = await _askPassword();
            if (candidatePassword == null) return;
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open PDF: $e')));
        }
      } finally {
        if (_source?.path != file.path || !mounted) {
          await widget.service.secureDeleteTemporary(file);
        }
        if (_source?.path != previous?.path) {
          await widget.service.secureDeleteTemporary(previous);
        }
        if (mounted) setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not choose PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _ensureLargeOcrUnlocked() async {
    final threshold = TelemetryService.instance.rewardedOcrThresholdPages;
    if (!needsRewardedOcrGate(
      pageCount: _pageCount,
      threshold: threshold,
      alreadyUnlocked: _heavyUnlocked,
    )) {
      return true;
    }

    final watch = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Large OCR job'),
        content: Text(
          'This PDF has $_pageCount pages. Watch one rewarded ad to unlock '
          'the full OCR/searchable-PDF job. Files with $threshold pages or '
          'fewer remain free.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch ad'),
          ),
        ],
      ),
    );

    if (watch != true) return false;

    final outcome = await AdsService.instance.showRewardedGate();
    switch (outcome) {
      case RewardedAdOutcome.earned:
        _heavyUnlocked = true;
        await TelemetryService.instance.logEvent(
          'rewarded_ocr_unlocked',
          parameters: {'pages': _pageCount},
        );
        return true;
      case RewardedAdOutcome.dismissed:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ad closed before the reward was earned.'),
            ),
          );
        }
        return false;
      case RewardedAdOutcome.failed:
      case RewardedAdOutcome.unavailable:
        if (!mounted) return false;
        final continueOnce = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ad unavailable'),
            content: const Text(
              'The rewarded ad could not be served right now. '
              'You can retry later or continue this job once without an ad. '
              'PDFMate will never silently block your document because the '
              'ad network is unavailable.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue once'),
              ),
            ],
          ),
        );
        if (continueOnce == true) {
          _heavyUnlocked = true;
          await TelemetryService.instance.logEvent(
            'rewarded_ocr_grace_unlock',
            parameters: {'pages': _pageCount},
          );
          return true;
        }
        return false;
    }
  }

  Future<void> _resolveLanguage(File source) async {
    final script = _language.script;
    if (script != null) { _script = script; return; }
    setState(() => _status = 'Detecting the document script…');
    _script = await widget.service.detectOcrScript(source,
      password: _password, control: _operation);
    if (mounted) setState(() => _status = 'Detected ${_scriptLabel(_script)}. Processing…');
  }

  Future<void> _extract() async {
    final source = _source;
    if (source == null || _busy) return;
    setState(() => _busy = true);
    try {
    if (!await _ensureLargeOcrUnlocked() || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Recognizing text on-device…';
      _extractedText = null;
    });

    _operation = PdfOperationControl(
      onProgress: (completed, total) {
        if (mounted) {
          setState(
            () => _status = 'Processing page ${completed + 1} of $total…',
          );
        }
      },
    );
    File? textFile;
    IOSink? writer;
    try {
      await _resolveLanguage(source);
      textFile = await widget.service.newTemporaryTextFile();
      writer = textFile.openWrite();
      final preview = StringBuffer();
      var previewLength = 0;
      var pageCount = 0;
      await widget.service.ocrPdf(
        source,
        script: _script,
        password: _password,
        tableRows: _tableRows,
        control: _operation,
        onPageText: (index, text) async {
          writer!.writeln('--- Page ${index + 1} ---');
          writer.writeln(text);
          await writer.flush();
          pageCount++;
          if (previewLength < 50000) {
            final available = 50000 - previewLength;
            final excerpt = text.substring(
              0, text.length < available ? text.length : available,
            );
            preview.writeln('--- Page ${index + 1} ---\n$excerpt\n');
            previewLength += excerpt.length;
          }
        },
      );
      await writer.close();
      writer = null;

      if (!mounted) return;
      await widget.service.secureDeleteTemporary(_textFile);
      if (!mounted) return;
      _textFile = textFile;
      setState(() {
        _extractedText = preview.toString();
        _status = 'OCR complete for $pageCount page(s). Preview shows up to 50,000 characters.';
      });
      textFile = null;
    } on PdfOperationCancelled {
      if (mounted) setState(() => _status = 'Cancelled.');
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'OCR failed.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('OCR failed: $e')));
      }
    } finally {
      try { await writer?.close(); } catch (_) {}
      await widget.service.secureDeleteTemporary(textFile);
      _operation = null;
      if (mounted) setState(() => _busy = false);
    }
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not start OCR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmSignedPdfModification() async {
    if (!_hasDigitalSignatures) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Digitally signed PDF'),
        content: const Text(
          'Adding an OCR text layer changes the document. Existing digital '
          'signatures may show the file as modified after signing. '
          'PDFMate will not silently claim that the original signature '
          'remains valid. Continue with a new searchable copy?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create copy'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _makeSearchable() async {
    final source = _source;
    if (source == null || _busy) return;
    setState(() => _busy = true);
    try {
    if (!await _ensureLargeOcrUnlocked() || !mounted) return;
    if (!await _confirmSignedPdfModification() || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Building searchable PDF…';
    });

    _operation = PdfOperationControl(
      onProgress: (completed, total) {
        if (mounted) {
          setState(
            () => _status = 'Processing page ${completed + 1} of $total…',
          );
        }
      },
    );
    try {
      var candidatePassword = _password;
      while (true) {
        try {
          await widget.service.checkOcrPermission(source, password: candidatePassword);
          _password = candidatePassword;
          break;
        } on PlatformException catch (error) {
          if (error.code != 'OCR_OWNER_PASSWORD_REQUIRED' && error.code != 'OCR_WRONG_PASSWORD') rethrow;
          if (!mounted) return;
          final password = await _askPassword(owner: true, wrong: error.code == 'OCR_WRONG_PASSWORD');
          if (password == null) {
            if (mounted) setState(() => _status = 'Cancelled.');
            return;
          }
          candidatePassword = password;
        }
      }
      if (!mounted) return;
      await _resolveLanguage(source);
      final output = await widget.service.makeSearchablePdf(
        source,
        script: _script,
        password: _password,
        tableRows: _tableRows,
        control: _operation,
      );
      if (!mounted) {
        await output.delete();
        return;
      }
      setState(() => _busy = false);
      Navigator.of(context).pop<File>(output);
    } on PdfOperationCancelled {
      if (mounted) setState(() => _status = 'Cancelled.');
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Searchable PDF failed.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Searchable PDF failed: $e')));
      }
    } finally {
      _operation = null;
      if (mounted) setState(() => _busy = false);
    }
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not start OCR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _operation?.cancel();
    unawaited(widget.service.secureDeleteTemporary(_source));
    unawaited(widget.service.secureDeleteTemporary(_textFile));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _extractedText;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('OCR & searchable PDF')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: Text(
                    (_source == null ? null : widget.service.displayName(_source!)) ?? 'No PDF selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_status),
                  trailing: OutlinedButton(
                    onPressed: _busy ? null : _pick,
                    child: const Text('Choose'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<OcrLanguage>(
                initialValue: _language, isExpanded: true,
                decoration: const InputDecoration(labelText: 'OCR language'),
                items: [for (final language in ocrLanguages)
                  DropdownMenuItem(value: language, child: Text(language.name))],
                onChanged: _busy ? null : (value) => setState(() {
                  _language = value!;
                  _script = value.script ?? TextRecognitionScript.latin;
                }),
              ),
              const Text('Auto samples the first, middle and last page to select the dominant script. For mixed scripts, choose a language manually. Language names share their script model.'),
              const SizedBox(height: 10),
              DropdownButtonFormField<bool>(
                initialValue: _tableRows,
                decoration: const InputDecoration(
                  labelText: 'Reading order',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: false, child: Text('Text columns')),
                  DropdownMenuItem(value: true, child: Text('Table rows')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => _tableRows = value);
                      },
              ),
              const SizedBox(height: 10),
              Text(
                _script == TextRecognitionScript.latin
                    ? 'Recognition runs on-device. Latin searchable PDFs preserve the original PDF and add a word-level OCR layer.'
                    : 'Recognition runs on-device. Chinese, Japanese and Korean use a verified native text overlay. Hindi embeds a Unicode text layer while preserving the original page objects. Arabic/Hebrew OCR is not supported by this recognizer.',
              ),
              if (_hasDigitalSignatures) ...[
                const SizedBox(height: 8),
                const Text(
                  'This file has digital signatures. Creating a modified OCR copy can change signature validation status.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              OutlinedButton.icon(
                onPressed: _source == null || _busy ? null : () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => OcrPagePreviewScreen(
                    service: widget.service, source: _source!, pageCount: _pageCount,
                    password: _password, script: _language.script)));
                },
                icon: const Icon(Icons.document_scanner_outlined), label: const Text('Preview & copy text'),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_source == null || _busy) ? null : _extract,
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('Extract text'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_source == null || _busy)
                          ? null
                          : _makeSearchable,
                      icon: const Icon(Icons.manage_search_rounded),
                      label: const Text('Make searchable'),
                    ),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(),
                if (_operation != null)
                  TextButton(
                    onPressed: () {
                      _operation?.cancel();
                      setState(() => _status = 'Cancelling…');
                    },
                    child: const Text('Cancel'),
                  ),
              ],
              if (text != null) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Recognized text',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied to clipboard'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy preview'),
                    ),
                    if (_textFile != null)
                      IconButton(
                        tooltip: 'Share full text file',
                        icon: const Icon(Icons.share_outlined),
                        onPressed: () async {
                          try {
                            await SharePlus.instance.share(ShareParams(files: [XFile(_textFile!.path)]));
                          } catch (error) {
                            if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Sharing failed. Please retry: $error'))); }
                          }
                        },
                      ),
                  ],
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 420),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(child: SelectableText(text)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
