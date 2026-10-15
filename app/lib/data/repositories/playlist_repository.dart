import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';

/// 歌單的一列（`playlists`，ADR 0033 §決定 1）。Mix 三欄與遠端資料等用到它的 PR 再加。
@immutable
final class Playlist {
  const Playlist({
    required this.id,
    required this.kind,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.artwork = const [],
  });

  final int id;
  final PlaylistKind kind;
  final String name;
  final String? description;
  final List<TrackArtwork> artwork;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is Playlist &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.description == description &&
      listEquals(other.artwork, artwork) &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    description,
    Object.hashAll(artwork),
    sortOrder,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Playlist(id: $id, $kind, $name)';
}

/// 歌單裡的一首（`playlist_entries` join `tracks`）。[id] 是項目的身分，同一首曲目可以在
/// 同一份歌單出現多次。
@immutable
final class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.position,
    required this.track,
  });

  final int id;
  final int position;
  final TrackInfo track;

  @override
  bool operator ==(Object other) =>
      other is PlaylistEntry &&
      other.id == id &&
      other.position == position &&
      other.track == track;

  @override
  int get hashCode => Object.hash(id, position, track);

  @override
  String toString() => 'PlaylistEntry(id: $id, position: $position, $track)';
}

/// `playlists` 與 `playlist_entries` 的存取（M4 design §3.1）。
final class PlaylistRepository {
  PlaylistRepository(this._database);

  final AppDatabase _database;

  /// 全部歌單，依 `sort_order`（再依 `id`）；之後每次改變再發一次。
  Stream<List<Playlist>> watchAll() =>
      (_database.select(_database.playlistsTable)..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.id),
          ]))
          .watch()
          .map((rows) => [for (final row in rows) _fromRow(row)]);

  /// 建一張本機（`local`）歌單，加在清單最後，回傳新歌單的 id。匯入與 Mix 歌單要連同
  /// 自己的欄位一起寫（`playlist_remote`、Mix 三欄的 CHECK），由建它們的 PR 另加寫入口。
  Future<int> create({required String name, String? description}) =>
      _database.transaction(() async {
        final table = _database.playlistsTable;
        final last = await (_database.selectOnly(
          table,
        )..addColumns([table.sortOrder.max()])).getSingle();
        final next = (last.read(table.sortOrder.max()) ?? -1) + 1;
        final now = clock.now().toUtc();
        return _database
            .into(table)
            .insert(
              PlaylistsTableCompanion.insert(
                kind: PlaylistKind.local,
                name: name,
                description: Value(description),
                sortOrder: next,
                createdAt: now,
                updatedAt: now,
              ),
            );
      });

  /// 覆寫名稱、描述與封面（[description] 為空＝清掉描述，[artwork] 為空＝沒有封面）。
  /// 沒有這一列時什麼都不做。
  Future<void> update(
    int id, {
    required String name,
    String? description,
    List<TrackArtwork> artwork = const [],
  }) =>
      (_database.update(
        _database.playlistsTable,
      )..where((t) => t.id.equals(id))).write(
        PlaylistsTableCompanion(
          name: Value(name),
          description: Value(description),
          artworkJson: Value(TracksRepository.encodeArtwork(artwork)),
          updatedAt: Value(clock.now().toUtc()),
        ),
      );

  /// 刪歌單，項目連帶刪除；曲目的顯示資料留給孤兒清理。
  Future<void> delete(int id) => (_database.delete(
    _database.playlistsTable,
  )..where((t) => t.id.equals(id))).go();

  /// 依 [ids] 的順序整批重寫 `sort_order`（0, 1, 2…）。不在 [ids] 裡的列不動。
  Future<void> reorder(List<int> ids) => _database.transaction(() async {
    for (final (index, id) in ids.indexed) {
      await (_database.update(_database.playlistsTable)
            ..where((t) => t.id.equals(id)))
          .write(PlaylistsTableCompanion(sortOrder: Value(index)));
    }
  });

  /// 歌單的項目，依（`position`, `id`）。
  Future<List<PlaylistEntry>> entries(int playlistId) async {
    final entries = _database.playlistEntriesTable;
    final tracks = _database.tracksTable;
    final query =
        _database.select(entries).join([
            innerJoin(tracks, tracks.trackKey.equalsExp(entries.trackKey)),
          ])
          ..where(entries.playlistId.equals(playlistId))
          ..orderBy([
            OrderingTerm.asc(entries.position),
            OrderingTerm.asc(entries.id),
          ]);
    return [
      for (final row in await query.get())
        PlaylistEntry(
          id: row.readTable(entries).id,
          position: row.readTable(entries).position,
          track: TracksRepository.toTrackInfo(row.readTable(tracks)),
        ),
    ];
  }

  /// 把 [tracks] 接在歌單尾端（同一首可重複加入）。曲目的顯示資料以
  /// `TracksRepository.upsert` 寫入。
  Future<void> addTracks(int playlistId, List<TrackInfo> tracks) {
    if (tracks.isEmpty) return Future.value();
    return _database.transaction(() async {
      await TracksRepository(_database).upsert(tracks);
      final table = _database.playlistEntriesTable;
      final last =
          await (_database.selectOnly(table)
                ..addColumns([table.position.max()])
                ..where(table.playlistId.equals(playlistId)))
              .getSingle();
      final first = (last.read(table.position.max()) ?? -1) + 1;
      await _database.batch((batch) {
        batch.insertAll(table, [
          for (final (index, track) in tracks.indexed)
            PlaylistEntriesTableCompanion.insert(
              playlistId: playlistId,
              position: first + index,
              trackKey: '${track.key}',
            ),
        ]);
      });
      await _touch([playlistId]);
    });
  }

  /// 刪掉 [entryIds] 的項目；剩下的 `position` 會有空洞，無妨（只比大小）。
  Future<void> removeEntries(List<int> entryIds) async {
    if (entryIds.isEmpty) return;
    await _database.transaction(() async {
      final table = _database.playlistEntriesTable;
      final playlistIds = <int>{};
      for (var i = 0; i < entryIds.length; i += _chunk) {
        final ids = entryIds.skip(i).take(_chunk).toList();
        final owners = _database.selectOnly(table, distinct: true)
          ..addColumns([table.playlistId])
          ..where(table.id.isIn(ids));
        playlistIds.addAll([
          for (final row in await owners.get()) row.read(table.playlistId)!,
        ]);
        await (_database.delete(table)..where((t) => t.id.isIn(ids))).go();
      }
      await _touch(playlistIds);
    });
  }

  /// 依 [entryIds] 的順序整批重寫歌單的 `position`（0, 1, 2…）。不在 [entryIds]
  /// 裡的項目不動，別張歌單的 id 不生效：以讀出後才過時的清單拖曳時，之後才加入的
  /// 項目（位置不小於讀出時的項目數）仍留在尾端。
  Future<void> moveEntries(int playlistId, List<int> entryIds) =>
      _database.transaction(() async {
        final table = _database.playlistEntriesTable;
        await _database.batch((batch) {
          for (final (index, id) in entryIds.indexed) {
            batch.update(
              table,
              PlaylistEntriesTableCompanion(position: Value(index)),
              where: (t) => t.id.equals(id) & t.playlistId.equals(playlistId),
            );
          }
        });
        await _touch([playlistId]);
      });

  /// 項目有增刪或重排時更新歌單的 `updated_at`（舊版與刷新的完整套用都這樣記）。
  Future<void> _touch(Iterable<int> playlistIds) async {
    if (playlistIds.isEmpty) return;
    await (_database.update(_database.playlistsTable)
          ..where((t) => t.id.isIn(playlistIds)))
        .write(PlaylistsTableCompanion(updatedAt: Value(clock.now().toUtc())));
  }

  /// 歌單或項目有任何變動時發出，給畫面重讀。聽的是 drift 的 `tableUpdates`，理由同
  /// `PlayHistoryRepository.changes`。
  Stream<void> changes() => _database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _database.playlistsTable,
          _database.playlistEntriesTable,
        ]),
      )
      .map((_) {});

  /// 一次刪的列數上限，在 SQLite 的變數上限（舊版 999）以下。
  static const _chunk = 500;

  static Playlist _fromRow(PlaylistRow row) => Playlist(
    id: row.id,
    kind: row.kind,
    name: row.name,
    description: row.description,
    artwork: TracksRepository.decodeArtwork(row.artworkJson),
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
