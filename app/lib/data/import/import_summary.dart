import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一個 collection（曲目、歌單、歷史……）的匯入結果：讀到幾筆、寫了幾筆、略過幾筆與理由。
@immutable
final class CollectionSummary {
  const CollectionSummary({
    required this.read,
    required this.written,
    this.skipped = const {},
    this.notes = const {},
  });

  factory CollectionSummary.fromJson(Map<String, Object?> json) =>
      CollectionSummary(
        read: json['read']! as int,
        written: json['written']! as int,
        skipped: {
          for (final entry
              in (json['skipped']! as Map<String, Object?>).entries)
            entry.key: entry.value! as int,
        },
        // 早期的 summary 沒有 `notes`。
        notes: {
          for (final entry
              in (json['notes'] as Map<String, Object?>? ?? const {}).entries)
            entry.key: entry.value! as int,
        },
      );

  final int read;
  final int written;

  /// 真正略過的理由 → 筆數（`read = written + skipped 的總和`）。理由是轉換器寫死的英文識別字
  /// （例如 `danglingTrackId`），結果對話框依它查翻譯。
  final Map<String, int> skipped;

  /// 資料有寫出、但值得提一下的註記 → 筆數（例如歌單的網址認不出而轉成本機歌單）；不計入
  /// [skipped]，也不影響 `read = written + skipped`。
  final Map<String, int> notes;

  Map<String, Object?> toJson() => {
    'read': read,
    'written': written,
    'skipped': skipped,
    'notes': notes,
  };

  @override
  bool operator ==(Object other) =>
      other is CollectionSummary &&
      other.read == read &&
      other.written == written &&
      mapEquals(other.skipped, skipped) &&
      mapEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(
    read,
    written,
    // == 不看 map 的順序，hash 也不能看。
    Object.hashAllUnordered(skipped.entries.map((e) => (e.key, e.value))),
    Object.hashAllUnordered(notes.entries.map((e) => (e.key, e.value))),
  );

  @override
  String toString() =>
      'CollectionSummary(read: $read, written: $written, skipped: $skipped, notes: $notes)';
}

/// 一次匯入的結果摘要，存成 `legacy_imports.summary_json`（M5 design §6.4）。
///
/// 裡面只有筆數與識別字，沒有使用者的資料（曲名、歌單名）。
@immutable
final class ImportSummary {
  const ImportSummary({
    this.collections = const {},
    this.unimportedSettings = const [],
    this.reloginPlatforms = const [],
  });

  factory ImportSummary.fromJson(Map<String, Object?> json) => ImportSummary(
    collections: {
      for (final entry
          in (json['collections']! as Map<String, Object?>).entries)
        entry.key: CollectionSummary.fromJson(
          entry.value! as Map<String, Object?>,
        ),
    },
    unimportedSettings: [
      for (final name in json['unimportedSettings']! as List<Object?>)
        name! as String,
    ],
    reloginPlatforms: [
      for (final id in json['reloginPlatforms']! as List<Object?>)
        id! as String,
    ],
  );

  factory ImportSummary.decode(String json) =>
      ImportSummary.fromJson(jsonDecode(json) as Map<String, Object?>);

  /// collection 名（轉換器寫死的識別字，例如 `tracks`、`playlists`）→ 結果。
  final Map<String, CollectionSummary> collections;

  /// 舊版有、新版沒有落腳處而不匯入的設定（識別字）。
  final List<String> unimportedSettings;

  /// 憑證讀不出來、要使用者重新登入的平台（插件 id）。
  final List<String> reloginPlatforms;

  Map<String, Object?> toJson() => {
    'collections': {
      for (final entry in collections.entries) entry.key: entry.value.toJson(),
    },
    'unimportedSettings': unimportedSettings,
    'reloginPlatforms': reloginPlatforms,
  };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is ImportSummary &&
      mapEquals(other.collections, collections) &&
      listEquals(other.unimportedSettings, unimportedSettings) &&
      listEquals(other.reloginPlatforms, reloginPlatforms);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(collections.entries.map((e) => (e.key, e.value))),
    Object.hashAll(unimportedSettings),
    Object.hashAll(reloginPlatforms),
  );
}
