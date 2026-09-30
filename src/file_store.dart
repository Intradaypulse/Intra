import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'serial_executor.dart';

class PdfRecord {
  const PdfRecord({
    required this.path,
    required this.name,
    required this.createdAt,
    this.favorite = false,
  });

  final String path;
  final String name;
  final DateTime createdAt;
  final bool favorite;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'favorite': favorite,
  };

  factory PdfRecord.fromJson(Map<String, dynamic> json) => PdfRecord(
    path: json['path'] as String,
    name: json['name'] as String,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    favorite: json['favorite'] as bool? ?? false,
  );

  PdfRecord copyWith({
    String? path,
    String? name,
    DateTime? createdAt,
    bool? favorite,
  }) => PdfRecord(
    path: path ?? this.path,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    favorite: favorite ?? this.favorite,
  );
}

class PdfFileStore {
  static final _mutations = SerialExecutor();

  static const _key = 'pdfmate_recent_files_v1';
  static const _renameKey = 'pdfmate_pending_rename_v1';

  Future<List<PdfRecord>> load() => _mutations.run(_load);

  Future<List<PdfRecord>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _recoverRename(prefs);
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final records = <PdfRecord>[];
    for (final item in raw) {
      try {
        final record = PdfRecord.fromJson(
          jsonDecode(item) as Map<String, dynamic>,
        );
        if (await File(record.path).exists()) records.add(record);
      } catch (_) {}
    }
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (records.length != raw.length) await _save(records);
    return records;
  }

  Future<void> _recoverRename(SharedPreferences prefs) async {
    final pending = prefs.getString(_renameKey);
    if (pending == null) return;
    try {
      final entry = jsonDecode(pending) as Map<String, dynamic>;
      final old = entry['old'] as String;
      final replacement = PdfRecord.fromJson(
        entry['record'] as Map<String, dynamic>,
      );
      final records = prefs.getStringList(_key) ?? <String>[];
      final destinationExists = await File(replacement.path).exists();
      final sourceExists = await File(old).exists();
      if (destinationExists && !sourceExists) {
        final recovered = <String>[
          jsonEncode(replacement.toJson()),
          for (final raw in records)
            if ((jsonDecode(raw) as Map<String, dynamic>)['path'] != old &&
                (jsonDecode(raw) as Map<String, dynamic>)['path'] !=
                    replacement.path)
              raw,
        ];
        await _persist(prefs, () => prefs.setStringList(_key, recovered));
      }
      await _persist(prefs, () => prefs.remove(_renameKey));
    } catch (_) {
      // Do not filter missing old paths or overwrite a pending journal when
      // recovery cannot persist the replacement record.
      rethrow;
    }
  }

  Future<PdfRecord> renameRecord(
    PdfRecord record,
    String destinationPath,
    Future<File> Function() rename,
  ) => _mutations.run(() async {
    final records = await _load();
    final prefs = await SharedPreferences.getInstance();
    final destination = File(destinationPath);
    final replacement = record.copyWith(
      path: destination.path,
      name: destination.uri.pathSegments.last,
    );
    await _persist(prefs, () => prefs.setString(
      _renameKey,
      jsonEncode({'old': record.path, 'record': replacement.toJson()}),
    ));
    File renamed;
    try {
      renamed = await rename();
    } catch (_) {
      await _persist(prefs, () => prefs.remove(_renameKey));
      rethrow;
    }
    final actual = replacement.copyWith(
      path: renamed.path,
      name: renamed.uri.pathSegments.last,
    );
    records.removeWhere((e) => e.path == record.path || e.path == renamed.path);
    records.insert(0, actual);
    await _save(records);
    await _persist(prefs, () => prefs.remove(_renameKey));
    return actual;
  });

  Future<void> save(List<PdfRecord> records) =>
      _mutations.run(() => _save(records));

  Future<void> _save(List<PdfRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs, () => prefs.setStringList(
      _key,
      records.map((e) => jsonEncode(e.toJson())).toList(),
    ));
  }

  Future<void> _persist(SharedPreferences prefs, Future<bool> Function() write) async {
    try {
      if (!await write()) throw const FileSystemException('Could not save library changes');
    } catch (_) {
      // SharedPreferences updates its memory cache before the platform write.
      // Reload persisted state so a failed write cannot appear committed.
      await prefs.reload();
      rethrow;
    }
  }

  Future<void> add(PdfRecord record) => _mutations.run(() async {
    final items = await _load();
    PdfRecord? existing;
    for (final item in items) {
      if (item.path == record.path) {
        existing = item;
        break;
      }
    }
    items.removeWhere((e) => e.path == record.path);
    items.insert(
      0,
      existing == null ? record : record.copyWith(favorite: existing.favorite),
    );
    await _save(items);
  });

  Future<void> addMany(List<PdfRecord> records) => _mutations.run(() async {
    if (records.isEmpty) return;
    final items = await _load();
    final paths = records.map((e) => e.path).toSet();
    final favorites = {for (final item in items) item.path: item.favorite};
    items.removeWhere((e) => paths.contains(e.path));
    items.insertAll(0, [
      for (final record in records)
        record.copyWith(favorite: favorites[record.path] ?? record.favorite),
    ]);
    await _save(items);
  });

  Future<void> remove(String path) => _mutations.run(() async {
    final items = await _load();
    items.removeWhere((e) => e.path == path);
    await _save(items);
  });

  Future<void> replace(String oldPath, PdfRecord replacement) =>
      _mutations.run(() async {
        final items = await _load();
        final index = items.indexWhere((e) => e.path == oldPath);
        if (index >= 0) {
          items[index] = replacement;
        } else {
          items.insert(0, replacement);
        }
        await _save(items);
      });

  Future<void> setFavorite(String path, bool favorite) =>
      _mutations.run(() async {
        final items = await _load();
        final index = items.indexWhere((e) => e.path == path);
        if (index < 0) return;
        items[index] = items[index].copyWith(favorite: favorite);
        await _save(items);
      });
}
