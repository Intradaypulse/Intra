import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'scan_temp_session.dart';

/// Captures live outside the OS cache until explicitly saved or discarded.
class ScanDraftStore {
  ScanDraftStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directoryProvider;
  Directory? _session;
  static final Set<String> _writing = {};

  Future<File> append(Uint8List bytes) async {
    final root = await _directoryProvider();
    final session = _session ??= Directory('${root.path}/scan_drafts/${DateTime.now().microsecondsSinceEpoch}');
    await session.create(recursive: true);
    final file = File('${session.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
    final pending = File('${file.path}.pending');
    _writing.add(pending.path);
    try {
      await pending.writeAsBytes(bytes, flush: true);
      return await pending.rename(file.path);
    } catch (_) {
      await ScanTempSession().deletePath(pending.path);
      rethrow;
    } finally { _writing.remove(pending.path); }
  }

  Future<List<List<String>>> recover() async {
    final root = Directory('${(await _directoryProvider()).path}/scan_drafts');
    if (!await root.exists()) return [];
    final result = <List<String>>[];
    await for (final session in root.list(followLinks: false)) {
      if (session is! Directory) continue;
      await for (final file in session.list(followLinks: false)) {
        if (file is File && file.path.endsWith('.pending') && !_writing.contains(file.path)) {
          await ScanTempSession().deletePath(file.path);
        }
      }
      final pages = [await for (final file in session.list(followLinks: false))
        if (file is File && file.path.endsWith('.jpg')) file.path]..sort();
      if (pages.isNotEmpty) result.add(pages);
    }
    return result;
  }

  Future<void> discard(List<String> pages) async {
    for (final path in pages) { await ScanTempSession().deletePath(path); }
    if (pages.isNotEmpty) {
      final receipt = File('${File(pages.first).parent.path}/output.txt');
      if (await receipt.exists()) await receipt.delete();
    }
  }

  Future<File?> completedOutput(List<String> pages) async {
    final receipt = File('${File(pages.first).parent.path}/output.txt');
    if (!await receipt.exists()) return null;
    final output = File(await receipt.readAsString());
    return await output.exists() ? output : null;
  }

  Future<void> rememberOutput(List<String> pages, File output) async {
    final receipt = File('${File(pages.first).parent.path}/output.txt');
    final pending = File('${receipt.path}.pending');
    await pending.writeAsString(output.path, flush: true);
    await pending.rename(receipt.path);
  }
}
