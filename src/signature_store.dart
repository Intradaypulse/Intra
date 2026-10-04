import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show listEquals;
import 'serial_executor.dart';

class SavedSignature {
  const SavedSignature(this.name, this.file);
  final String name;
  final File file;
}

/// Each PNG contains its name in the filename, so there is no separate index
/// that can lose a signature during process death. Writes publish via rename.
class SignatureStore {
  static const maxBackupBytes = 12 * 1024 * 1024;
  SignatureStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directoryProvider;
  static final _queue = SerialExecutor();
  Future<Directory> _directory() async {
    final root = await _directoryProvider();
    return Directory('${root.path}/saved_signatures').create(recursive: true);
  }

  Future<List<SavedSignature>> load() => _queue.run(() async {
    final directory = await _directory();
    final values = <SavedSignature>[];
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      if (entry.path.endsWith('.pending')) { await entry.delete(); continue; }
      final parts = entry.uri.pathSegments.last.split('.');
      if (parts.length != 3 || parts.last != 'png') continue;
      try {
        final name = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
        if (name.isNotEmpty && await entry.length() > 0) values.add(SavedSignature(name, entry));
      } catch (_) { /* A malformed unrelated file must not block the list. */ }
    }
    values.sort((a, b) => a.name.compareTo(b.name));
    return values;
  });

  Future<SavedSignature> save(String name, Uint8List bytes) => _queue.run(() async {
    final label = name.trim();
    if (label.isEmpty || label.length > 60) throw const FormatException('Use a name of 1–60 characters.');
    if (utf8.encode(label).length > 120) throw const FormatException('Use a shorter signature name.');
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) throw const FormatException('Invalid signature image.');
    final directory = await _directory();
    final encoded = base64Url.encode(utf8.encode(label)).replaceAll('=', '');
    final output = File('${directory.path}/${DateTime.now().microsecondsSinceEpoch}.$encoded.png');
    final pending = File('${output.path}.pending');
    try {
      await pending.writeAsBytes(bytes, flush: true);
      await pending.rename(output.path);
      return SavedSignature(label, output);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  });

  Future<void> delete(SavedSignature signature) => _queue.run(() async {
    final directory = await _directory();
    if (signature.file.parent.path != directory.path) throw ArgumentError('Signature outside managed storage.');
    if (await signature.file.exists()) await signature.file.delete();
  });

  bool _validBackupPng(Uint8List bytes) {
    if (bytes.length < 33 || bytes.length > 8 * 1024 * 1024 ||
        !listEquals(bytes.sublist(0, 8), const [137, 80, 78, 71, 13, 10, 26, 10]) ||
        String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') { return false; }
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16), height = header.getUint32(20);
    if (header.getUint32(8) != 13 || width < 1 || height < 1 || width > 4096 || height > 4096 ||
        width * height > 4000000) { return false; }
    try { return img.decodePng(bytes) != null; } catch (_) { return false; }
  }

  /// Portable image backup. Import preserves IDs, so retries do not duplicate.
  Future<Uint8List> exportBackup() async {
    final signatures = await load();
    if (signatures.isEmpty) throw const FormatException('No saved signatures to back up.');
    if (signatures.length > 100) throw const FormatException('Back up at most 100 signatures.');
    final entries = <Map<String, String>>[];
    var total = 0;
    for (final signature in signatures) {
      final bytes = await signature.file.readAsBytes();
      total += bytes.length;
      if (total > maxBackupBytes * 3 ~/ 4) throw const FormatException('Signature backup is too large.');
      entries.add({'file': signature.file.uri.pathSegments.last,
        'name': signature.name, 'png': base64Encode(bytes)});
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'pdfmate-signatures', 'version': 1, 'signatures': entries,
    })));
    if (bytes.length > maxBackupBytes) throw const FormatException('Signature backup is too large.');
    return bytes;
  }

  Future<int> restoreBackup(Uint8List backup) => _queue.run(() async {
    if (backup.length > maxBackupBytes) throw const FormatException('Signature backup is too large.');
    final value = jsonDecode(utf8.decode(backup));
    if (value is! Map || value['format'] != 'pdfmate-signatures' || value['version'] != 1 ||
        value['signatures'] is! List) { throw const FormatException('Not a ScanLumo signature backup.'); }
    final entries = value['signatures'] as List;
    if (entries.isEmpty || entries.length > 100) throw const FormatException('Invalid signature count.');
    final directory = await _directory();
    final pending = <(File, Uint8List)>[];
    final names = <String>{};
    // Validate every entry before publishing any file.
    for (final entry in entries) {
      if (entry is! Map || entry['file'] is! String || entry['name'] is! String || entry['png'] is! String) {
        throw const FormatException('Invalid signature entry.');
      }
      final filename = entry['file'] as String, name = entry['name'] as String;
      if (!RegExp(r'^[0-9]{1,20}\.[A-Za-z0-9_-]+\.png$').hasMatch(filename) || !names.add(filename) ||
          name.isEmpty || name.length > 60 || utf8.encode(name).length > 120 ||
          utf8.decode(base64Url.decode(base64Url.normalize(filename.split('.')[1]))) != name) {
        throw const FormatException('Invalid signature name.');
      }
      final bytes = base64Decode(entry['png'] as String);
      if (!_validBackupPng(bytes)) throw const FormatException('Invalid signature image.');
      final output = File('${directory.path}/$filename');
      if (await output.exists()) {
        final existing = await output.readAsBytes();
        if (!listEquals(existing, bytes)) {
          throw const FormatException('Backup conflicts with an existing signature.');
        }
      } else {
        pending.add((output, bytes));
      }
    }
    for (final (output, bytes) in pending) {
      final staging = File('${output.path}.pending');
      try {
        await staging.writeAsBytes(bytes, flush: true);
        await staging.rename(output.path);
      } finally { if (await staging.exists()) await staging.delete(); }
    }
    return pending.length;
  });
}
