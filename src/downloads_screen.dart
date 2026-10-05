import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shared exports are separate from the app's private working PDFs.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('pdfmate/downloads');
  List<Map<Object?, Object?>> _files = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      List<dynamic>? rows;
      try {
        rows = await _channel.invokeListMethod<dynamic>('list');
      } on PlatformException catch (e) {
        if (!(e.message ?? '').toLowerCase().contains('permission')) rethrow;
        // Scoped-storage Android can read this app's own exports without access
        // to all files. Only older devices need the legacy storage grant.
        if (!(await Permission.storage.request()).isGranted) rethrow;
        rows = await _channel.invokeListMethod<dynamic>('list');
      }
      if (mounted)
        setState(
          () => _files = [
            for (final row in rows ?? [])
              Map<Object?, Object?>.from(row as Map),
          ],
        );
    } catch (e) {
      if (mounted)
        setState(
          () => _error =
              'Could not list exported PDFs. Use Open folder or retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String method, [String? uri]) async {
    try {
      await _channel.invokeMethod<void>(
        method,
        uri == null ? null : {'uri': uri},
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              method == 'browse'
                  ? 'Open Files → Downloads → PDFMate on this device.'
                  : 'Install a PDF viewer or use Open folder.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Downloads/PDFMate'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Exported PDFs, newest first. Save a Downloads copy after editing to update your exported version.',
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _open('browse'),
          icon: const Icon(Icons.folder_open),
          label: const Text('Open folder'),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : _files.isEmpty
              ? const Center(
                  child: Text(
                    'No exported PDFs found. Use Save copy to Downloads in My PDFs.',
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      (file['modified'] as int) * 1000,
                    ).toLocal();
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf),
                      title: Text(file['name'] as String),
                      subtitle: Text('$date'),
                      onTap: () => _open('open', file['uri'] as String),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
