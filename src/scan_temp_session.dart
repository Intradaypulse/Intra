import 'dart:io';

class ScanTempSession {
  ScanTempSession({Future<void> Function(File file)? deleteFile})
      : _deleteFile = deleteFile ?? _defaultDelete;

  final Future<void> Function(File file) _deleteFile;
  final Set<String> _ownedPaths = <String>{};
  bool _handedOff = false;

  static Future<void> _defaultDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
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
