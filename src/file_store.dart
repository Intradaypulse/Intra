import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        favorite: json['favorite'] as bool? ?? false,
      );

  PdfRecord copyWith({
    String? path,
    String? name,
    DateTime? createdAt,
    bool? favorite,
  }) =>
      PdfRecord(
        path: path ?? this.path,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        favorite: favorite ?? this.favorite,
      );
}

class PdfFileStore {
  static const _key = 'pdfmate_recent_files_v1';

  Future<List<PdfRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final records = <PdfRecord>[];
    for (final item in raw) {
      try {
        final record =
            PdfRecord.fromJson(jsonDecode(item) as Map<String, dynamic>);
        if (await File(record.path).exists()) records.add(record);
      } catch (_) {}
    }
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (records.length != raw.length) await save(records);
    return records;
  }

  Future<void> save(List<PdfRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      records.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> add(PdfRecord record) async {
    final items = await load();
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
      existing == null
          ? record
          : record.copyWith(favorite: existing.favorite),
    );
    await save(items.take(250).toList());
  }

  Future<void> remove(String path) async {
    final items = await load();
    items.removeWhere((e) => e.path == path);
    await save(items);
  }

  Future<void> replace(String oldPath, PdfRecord replacement) async {
    final items = await load();
    final index = items.indexWhere((e) => e.path == oldPath);
    if (index >= 0) {
      items[index] = replacement;
    } else {
      items.insert(0, replacement);
    }
    await save(items);
  }

  Future<void> setFavorite(String path, bool favorite) async {
    final items = await load();
    final index = items.indexWhere((e) => e.path == path);
    if (index < 0) return;
    items[index] = items[index].copyWith(favorite: favorite);
    await save(items);
  }
}
