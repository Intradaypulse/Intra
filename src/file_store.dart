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

  Future<List<PdfRecord>> load() => _mutations.run(_load);

  Future<List<PdfRecord>> _load() async {
    final prefs = await SharedPreferences.getInstance();
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

  Future<void> save(List<PdfRecord> records) =>
      _mutations.run(() => _save(records));

  Future<void> _save(List<PdfRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      records.map((e) => jsonEncode(e.toJson())).toList(),
    );
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
