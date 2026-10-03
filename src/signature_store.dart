import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'serial_executor.dart';

class SavedSignature {
  const SavedSignature(this.name, this.file);
  final String name;
  final File file;
}

/// Each PNG contains its name in the filename, so there is no separate index
/// that can lose a signature during process death. Writes publish via rename.
class SignatureStore {
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
}
