import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class ScanTempSession {
  ScanTempSession({Future<void> Function(File file)? deleteFile})
      : _deleteFile = deleteFile ?? _defaultDelete;

  final Future<void> Function(File file) _deleteFile;
  final Set<String> _ownedPaths = <String>{};
  bool _handedOff = false;

  static Future<void> _defaultDelete(File file) async {
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      if (length > 0) {
        final handle = await file.open(mode: FileMode.writeOnly);
        try {
          const chunkSize = 64 * 1024;
          final zeros = Uint8List(chunkSize);
          var remaining = length;
          while (remaining > 0) {
            final count = math.min(chunkSize, remaining).toInt();
            await handle.writeFrom(zeros, 0, count);
            remaining -= count;
          }
          await handle.flush();
        } finally {
          await handle.close();
        }
      }
      await file.delete();
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  bool get handedOff => _handedOff;

  void own(String path) {
    if (path.isNotEmpty) _ownedPaths.add(path);
  }

  void forget(String path) => _ownedPaths.remove(path);

  List<String> handOff(List<String> paths) {
    _handedOff = true;
    for (final path in paths) {
      _ownedPaths.remove(path);
    }
    return List<String>.unmodifiable(paths);
  }

  Future<void> deletePath(String path) async {
    _ownedPaths.remove(path);
    if (path.isEmpty) return;
    await _deleteFile(File(path));
  }

  Future<void> cleanupOwned() async {
    final paths = List<String>.from(_ownedPaths);
    _ownedPaths.clear();
    for (final path in paths) {
      await _deleteFile(File(path));
    }
  }
}
