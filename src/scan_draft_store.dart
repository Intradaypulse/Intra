import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'scan_temp_session.dart';
import 'serial_executor.dart';

/// Captures live outside the OS cache until explicitly saved or discarded.
class ScanDraftStore {
  ScanDraftStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directoryProvider;
  Directory? _session;
  static final Set<String> _writing = {};
  static final _mutations = SerialExecutor();

  Future<File> append(Uint8List bytes) => _mutations.run(() async {
    final root = await _directoryProvider();
    final session = _session ??= Directory('${root.path}/scan_drafts/${DateTime.now().microsecondsSinceEpoch}');
    await session.create(recursive: true);
    final file = File('${session.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
    final pending = File('${file.path}.pending');
    _writing.add(pending.path);
    try {
      await pending.writeAsBytes(bytes, flush: true);
      final saved = await pending.rename(file.path);
      final pages = await _orderedPages(session);
      await _writeOrder(session, pages);
      return saved;
    } catch (_) {
      await ScanTempSession().deletePath(pending.path);
      rethrow;
    } finally { _writing.remove(pending.path); }
  });

  Future<List<String>> _orderedPages(Directory session) async {
    final available = [await for (final file in session.list(followLinks: false))
      if (file is File && file.path.endsWith('.jpg')) file.path]..sort();
    final manifest = File('${session.path}/order.json');
    if (!await manifest.exists()) return available; // Legacy drafts.
    final names = (jsonDecode(await manifest.readAsString()) as List).cast<String>();
    final ordered = <String>[];
    for (final name in names) {
      final path = '${session.path}/$name';
      if (available.contains(path) && !ordered.contains(path)) ordered.add(path);
    }
    // A capture can be published just before its order manifest is committed.
    return [...ordered, ...available.where((path) => !ordered.contains(path))];
  }

  Future<void> _writeOrder(Directory session, List<String> pages) async {
    final pending = File('${session.path}/order.json.pending');
    _writing.add(pending.path);
    try {
      await pending.writeAsString(jsonEncode([
        for (final path in pages) File(path).uri.pathSegments.last,
      ]), flush: true);
      await pending.rename('${session.path}/order.json');
    } finally { _writing.remove(pending.path); }
  }

  Future<void> persistOrder(List<String> pages) => _mutations.run(() async {
    final session = pages.isEmpty ? _session : File(pages.first).parent;
    if (session == null) return;
    if (pages.any((path) => File(path).parent.path != session.path)) {
      throw ArgumentError('Pages must belong to one scan session');
    }
    await _writeOrder(session, pages);
  });

  Future<void> removePage(List<String> remaining, String removed) => _mutations.run(() async {
    // Delete before committing order, so a killed deletion cannot resurrect a
    // supposedly removed page via the unpublished-capture fallback.
    await ScanTempSession().deletePath(removed);
    if (await File(removed).exists()) throw FileSystemException('Could not remove scan page', removed);
    await _writeOrder(File(removed).parent, remaining);
  });

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
      final pages = await _orderedPages(session);
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

  /// Commit the destination before writing any PDF bytes. The stable session ID
  /// also covers a process kill while the receipt itself is being published.
  Future<File> reserveOutput(List<String> pages) async {
    if (pages.isEmpty) throw ArgumentError('No scan pages');
    final receipt = File('${File(pages.first).parent.path}/output.txt');
    if (await receipt.exists()) return File(await receipt.readAsString());
    final sessionId = File(pages.first).parent.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final output = File('${(await _directoryProvider()).path}/Scan_$sessionId.pdf');
    await rememberOutput(pages, output);
    return output;
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
    _writing.add(pending.path);
    try {
      await pending.writeAsString(output.path, flush: true);
      await pending.rename(receipt.path);
    } finally { _writing.remove(pending.path); }
  }
}
