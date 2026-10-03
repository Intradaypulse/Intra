import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'pdf_service.dart';

enum SecurityMode { protect, unlock }

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({
    super.key,
    required this.service,
    this.initialMode = SecurityMode.protect,
  });

  final PdfService service;
  final SecurityMode initialMode;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late SecurityMode _mode = widget.initialMode;
  File? _source;
  final _ownerController = TextEditingController();
  final _userController = TextEditingController();
  final _unlockController = TextEditingController();
  bool _readOnly = false;
  bool _busy = false;

  @override
  void dispose() {
    unawaited(widget.service.secureDeleteTemporary(_source));
    _ownerController.dispose();
    _userController.dispose();
    _unlockController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? candidate;
    try {
      candidate = await widget.service.pickPdfFile();
      if (candidate == null || !mounted) return;
      final previous = _source;
      setState(() => _source = candidate);
      if (previous?.path != candidate.path) {
        await widget.service.secureDeleteTemporary(previous);
      }
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not choose PDF: $e')));
      }
    } finally {
      if (candidate != null && (_source?.path != candidate.path || !mounted)) {
        await widget.service.secureDeleteTemporary(candidate);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runProtect() async {
    final source = _source;
    final owner = _ownerController.text;
    final user = _userController.text;
    if (_busy || source == null || owner.isEmpty) return;

    setState(() => _busy = true);
    try {
      final output = await widget.service.protectPdfAdvanced(
        source,
        ownerPassword: owner,
        userPassword: user,
        readOnly: _readOnly,
      );
      if (!mounted) {
        try { await output.delete(); } catch (_) {}
        return;
      }
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Protection failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runUnlock() async {
    final source = _source;
    final password = _unlockController.text;
    if (_busy || source == null || password.isEmpty) return;

    setState(() => _busy = true);
    try {
      final output = await widget.service.unlockPdf(source, password);
      if (!mounted) {
        try { await output.delete(); } catch (_) {}
        return;
      }
      Navigator.of(context).pop<File>(output);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unlock failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !_busy, child: Scaffold(
      appBar: AppBar(title: const Text('PDF security')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<SecurityMode>(
              segments: const [
                ButtonSegment(
                  value: SecurityMode.protect,
                  icon: Icon(Icons.lock_rounded),
                  label: Text('Protect'),
                ),
                ButtonSegment(
                  value: SecurityMode.unlock,
                  icon: Icon(Icons.lock_open_rounded),
                  label: Text('Unlock'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _mode = value.first;
                        unawaited(widget.service.secureDeleteTemporary(_source));
                        _source = null;
                      }),
            ),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded),
                title: Text(
                  (_source == null ? null : widget.service.displayName(_source!)) ?? 'Choose a PDF',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _mode == SecurityMode.protect
                      ? 'AES-256 encryption'
                      : 'Remove PDF password encryption',
                ),
                trailing: OutlinedButton(
                  onPressed: _busy ? null : _pick,
                  child: const Text('Choose'),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_mode == SecurityMode.protect) ...[
              TextField(
                controller: _ownerController,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Owner password',
                  helperText:
                      'Required. Gives full control and can change permissions.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _userController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Open password (optional)',
                  helperText:
                      'Users enter this password when opening the PDF.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _readOnly,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _readOnly = value),
                title: const Text('Read-only permissions'),
                subtitle: const Text(
                  'Restrict modification, copying, printing and page assembly for the user password.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_busy ||
                        _source == null ||
                        _ownerController.text.isEmpty)
                    ? null
                    : _runProtect,
                icon: const Icon(Icons.enhanced_encryption_rounded),
                label: const Text('Protect with AES-256'),
              ),
            ] else ...[
              TextField(
                controller: _unlockController,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Current PDF password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_busy ||
                        _source == null ||
                        _unlockController.text.isEmpty)
                    ? null
                    : _runUnlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Create unlocked copy'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    ));
  }
}
