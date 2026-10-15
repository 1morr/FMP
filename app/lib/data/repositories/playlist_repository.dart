import 'dart:collection';

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

/// 匯入歌單的遠端資料（`playlist_remote`，ADR 0033 §決定 1）。
@immutable
final class PlaylistRemote {
  const PlaylistRemote({
    required this.playlistId,
    required this.pluginId,
    required this.remoteId,
    required this.writable,
    required this.nameOverridden,
    required this.descriptionOverridden,
    required this.artworkOverridden,
    required this.status,
    required this.refreshGeneration,
    this.ownerName,
    this.refreshIntervalHours,
    this.lastRefreshedAt,
    this.lastResult,
  });

  final int playlistId;
  final String pluginId;
  final String remoteId;
  final String? ownerName;

  /// 登入的帳號可以寫這張遠端歌單（ADR 0032 §決定 2）。
  final bool writable;
  final bool nameOverridden;
  final bool descriptionOverridden;
  final bool artworkOverridden;

  /// 空＝不啟用自動刷新。
  final int? refreshIntervalHours;

  /// 只在 `complete` 或 `partial` 時寫。
  final DateTime? lastRefreshedAt;

  /// 空＝還沒刷新完過。
  final PlaylistRefreshResult? lastResult;
  final PlaylistRemoteStatus status;
  final int refreshGeneration;

  @override
  bool operator ==(Object other) =>
      other is PlaylistRemote &&
      other.playlistId == playlistId &&
      other.pluginId == pluginId &&
      other.remoteId == remoteId &&
      other.ownerName == ownerName &&
      other.writable == writable &&
      other.nameOverridden == nameOverridden &&
      other.descriptionOverridden == descriptionOverridden &&
      other.artworkOverridden == artworkOverridden &&
      other.refreshIntervalHours == refreshIntervalHours &&
      other.lastRefreshedAt == lastRefreshedAt &&
      other.lastResult == lastResult &&
      other.status == status &&
      other.refreshGeneration == refreshGeneration;

  @override
  int get hashCode => Object.hash(
    playlistId,
    pluginId,
    remoteId,
    ownerName,
    writable,
    nameOverridden,
    descriptionOverridden,
    artworkOverridden,
    refreshIntervalHours,
    lastRefreshedAt,
    lastResult,
    status,
    refreshGeneration,
  );

  @override
  String toString() =>
      'PlaylistRemote($playlistId, $pluginId/$remoteId, $status)';
}

/// `playlists`、`playlist_entries` 與 `playlist_remote` 的存取（M4 design §3.1）。
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
        final now = clock.now().toUtc();
        return _database
            .into(_database.playlistsTable)
            .insert(
              PlaylistsTableCompanion.insert(
                kind: PlaylistKind.local,
                name: name,
                description: Value(description),
                sortOrder: await _nextSortOrder(),
                createdAt: now,
                updatedAt: now,
              ),
            );
      });

  /// 建一張匯入（`imported`）歌單，加在清單最後，回傳新歌單的 id：`playlists` 一列加
  /// `playlist_remote` 一列，同一個 transaction。名稱等取 [info]（名稱不唯一，不自動改名）；
  /// 刷新間隔預設 24 小時。（[pluginId], [remoteId]）已經有列時什麼都不寫、回 `null`。
  Future<int?> createImported({
    required String pluginId,
    required String remoteId,
    required RemotePlaylistInfo info,
    int refreshIntervalHours = 24,
  }) => _database.transaction(() async {
    if (await findRemote(pluginId, remoteId) != null) return null;
    final now = clock.now().toUtc();
    final id = await _database
        .into(_database.playlistsTable)
        .insert(
          PlaylistsTableCompanion.insert(
            kind: PlaylistKind.imported,
            name: info.name,
            description: Value(info.description),
            artworkJson: Value(TracksRepository.encodeArtwork(info.artwork)),
            sortOrder: await _nextSortOrder(),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _database
        .into(_database.playlistRemoteTable)
        .insert(
          PlaylistRemoteTableCompanion.insert(
            playlistId: Value(id),
            pluginId: pluginId,
            remoteId: remoteId,
            ownerName: Value(info.ownerName),
            writable: Value(info.writable ?? false),
            refreshIntervalHours: Value(refreshIntervalHours),
          ),
        );
    return id;
  });

  /// 匯入歌單的遠端資料；不是匯入歌單（或沒有這張歌單）為 `null`。
  Future<PlaylistRemote?> remote(int playlistId) async {
    final row = await (_database.select(
      _database.playlistRemoteTable,
    )..where((t) => t.playlistId.equals(playlistId))).getSingleOrNull();
    return row == null ? null : _remoteFromRow(row);
  }

  /// 以（插件, 遠端 id）找匯入歌單，重新匯入同一張時用。
  Future<PlaylistRemote?> findRemote(String pluginId, String remoteId) async {
    final row =
        await (_database.select(_database.playlistRemoteTable)..where(
              (t) => t.pluginId.equals(pluginId) & t.remoteId.equals(remoteId),
            ))
            .getSingleOrNull();
    return row == null ? null : _remoteFromRow(row);
  }

  /// 開始一次刷新（M4 design §5.2）：`refresh_generation` 加一得到這次的代際，並讀出現有項目
  /// 建立比對用的記憶體狀態。不是匯入歌單（或沒有這張歌單）回 `null`。
  ///
  /// 之後 [PlaylistRefreshSession] 的每個寫入都先檢查代際仍是這一次的、[isCurrent]（觸發者
  /// 是否仍有效）仍為真，不是就什麼都不寫。
  Future<PlaylistRefreshSession?> beginRefresh(
    int playlistId, {
    required bool Function() isCurrent,
  }) => _database.transaction(() async {
    final remotes = _database.playlistRemoteTable;
    final row = await (_database.select(
      remotes,
    )..where((t) => t.playlistId.equals(playlistId))).getSingleOrNull();
    if (row == null) return null;
    final generation = row.refreshGeneration + 1;
    await (_database.update(
      remotes,
    )..where((t) => t.playlistId.equals(playlistId))).write(
      PlaylistRemoteTableCompanion(refreshGeneration: Value(generation)),
    );
    final entries =
        await (_database.select(_database.playlistEntriesTable)
              ..where((t) => t.playlistId.equals(playlistId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.position),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return PlaylistRefreshSession._(
      _database,
      playlistId,
      generation,
      isCurrent,
      entries,
    );
  });

  /// 清單最後一張的 `sort_order` 加一。
  Future<int> _nextSortOrder() async {
    final table = _database.playlistsTable;
    final last = await (_database.selectOnly(
      table,
    )..addColumns([table.sortOrder.max()])).getSingle();
    return (last.read(table.sortOrder.max()) ?? -1) + 1;
  }

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

  /// 歌單、項目或遠端資料有任何變動時發出，給畫面重讀。聽的是 drift 的 `tableUpdates`，理由同
  /// `PlayHistoryRepository.changes`。
  Stream<void> changes() => _database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _database.playlistsTable,
          _database.playlistEntriesTable,
          _database.playlistRemoteTable,
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

PlaylistRemote _remoteFromRow(PlaylistRemoteRow row) => PlaylistRemote(
  playlistId: row.playlistId,
  pluginId: row.pluginId,
  remoteId: row.remoteId,
  ownerName: row.ownerName,
  writable: row.writable,
  nameOverridden: row.nameOverridden,
  descriptionOverridden: row.descriptionOverridden,
  artworkOverridden: row.artworkOverridden,
  refreshIntervalHours: row.refreshIntervalHours,
  lastRefreshedAt: row.lastRefreshedAt,
  lastResult: row.lastResult,
  status: row.status,
  refreshGeneration: row.refreshGeneration,
);

/// 一次刷新的寫入（ADR 0033 §決定 2、M4 design §5.2），由 [PlaylistRepository.beginRefresh]
/// 建立。記憶體裡維護這次刷新的狀態：現有項目依比對鍵分成佇列、依遠端順序已見過的項目、
/// 每個項目的目前位置。
///
/// 比對鍵有兩種：遠端項目有 `remote_item_id` 就用它；沒有就用曲目鍵。同一個鍵的現有項目
/// 依目前 `position`（再依 `id`）排成佇列，遠端第 k 次出現這個鍵就取佇列的第 k 個，所以重複
/// 的影片不合併（多重集合比對）。
///
/// 每個寫入方法是一個 transaction，寫之前先確認代際仍是這一次的、觸發者仍有效；過期就什麼
/// 都不寫、回傳 `false`（[apply] 回 `null`）。寫入中丟例外時該 transaction 回滾，資料庫仍一致，
/// 但這個 session 的記憶體狀態已經取用過佇列，不要再用。
final class PlaylistRefreshSession {
  PlaylistRefreshSession._(
    this._database,
    this._playlistId,
    this.generation,
    this._isCurrent,
    List<PlaylistEntryRow> entries,
  ) {
    for (final entry in entries) {
      (entry.remoteItemId == null
              ? _byTrackKey.putIfAbsent(entry.trackKey, Queue<int>.new)
              : _byRemoteId.putIfAbsent(entry.remoteItemId!, Queue<int>.new))
          .add(entry.id);
      _positions[entry.id] = entry.position;
      if (entry.position >= _nextPosition) _nextPosition = entry.position + 1;
    }
  }

  final AppDatabase _database;
  final int _playlistId;
  final bool Function() _isCurrent;

  /// 這次刷新的代際。
  final int generation;

  final _byRemoteId = <String, Queue<int>>{};
  final _byTrackKey = <String, Queue<int>>{};
  final _positions = <int, int>{};

  /// 依遠端順序、這次見過的項目 id。
  final _order = <int>[];
  var _nextPosition = 0;
  var _added = 0;

  /// 到目前為止新增了幾個項目。
  int get added => _added;

  /// 寫一頁（一個 transaction）：upsert 曲目，與現有項目比對，比到的寫
  /// `seen_generation`、`unavailable`、`remote_item_id`，比不到的接在尾端。過期回 `false`。
  Future<bool> writePage(List<RemoteEntry> items) =>
      _database.transaction(() async {
        if (!await _stillCurrent()) return false;
        if (items.isEmpty) return true;
        await TracksRepository(_database)
            .upsert([for (final item in items) item.track]);
        final table = _database.playlistEntriesTable;
        final firstNew = _nextPosition;
        // null＝新項目，寫入後再依位置補上 id。
        final page = <int?>[];
        final fresh = <PlaylistEntriesTableCompanion>[];
        await _database.batch((batch) {
          for (final item in items) {
            final key = '${item.track.key}';
            final remoteId = item.remoteItemId;
            final matched = _take(
              remoteId == null ? _byTrackKey : _byRemoteId,
              remoteId ?? key,
            );
            page.add(matched);
            if (matched == null) {
              fresh.add(
                PlaylistEntriesTableCompanion.insert(
                  playlistId: _playlistId,
                  position: _nextPosition++,
                  trackKey: key,
                  remoteItemId: Value(remoteId),
                  unavailable: Value(item.unavailable),
                  seenGeneration: Value(generation),
                ),
              );
            } else {
              batch.update(
                table,
                PlaylistEntriesTableCompanion(
                  trackKey: Value(key),
                  remoteItemId: Value(remoteId),
                  unavailable: Value(item.unavailable),
                  seenGeneration: Value(generation),
                ),
                where: (t) => t.id.equals(matched),
              );
            }
          }
          batch.insertAll(table, fresh);
        });
        final created = fresh.isEmpty
            ? const <TypedResult>[]
            : await (_database.selectOnly(table)
                    ..addColumns([table.id, table.position])
                    ..where(
                      table.playlistId.equals(_playlistId) &
                          table.position.isBiggerOrEqualValue(firstNew),
                    )
                    ..orderBy([
                      OrderingTerm.asc(table.position),
                      OrderingTerm.asc(table.id),
                    ]))
                  .get();
        var next = 0;
        for (final matched in page) {
          if (matched != null) {
            _order.add(matched);
            continue;
          }
          final row = created[next++];
          final id = row.read(table.id)!;
          _positions[id] = row.read(table.position)!;
          _order.add(id);
          _added++;
        }
        return true;
      });

  /// 完整套用（一個 transaction）：刪 `seen_generation` 落後的項目，依遠端順序重寫
  /// `position`（0 起），名稱、描述、封面在沒有本地覆寫時跟 [info]，並寫 `owner_name`、
  /// `writable`（[info] 給了才寫）、`last_result = complete`、`last_refreshed_at`、
  /// `status = active`。回傳移除了幾個項目；過期回 `null`。
  Future<int?> apply(RemotePlaylistInfo info) => _database.transaction(
    () async {
      if (!await _stillCurrent()) return null;
      final entries = _database.playlistEntriesTable;
      final removed =
          await (_database.delete(entries)..where(
                (t) =>
                    t.playlistId.equals(_playlistId) &
                    t.seenGeneration.isSmallerThanValue(generation),
              ))
              .go();
      await _database.batch((batch) {
        for (final (index, id) in _order.indexed) {
          if (_positions[id] == index) continue;
          batch.update(
            entries,
            PlaylistEntriesTableCompanion(position: Value(index)),
            where: (t) => t.id.equals(id),
          );
        }
      });
      final remotes = _database.playlistRemoteTable;
      final flags = await (_database.select(
        remotes,
      )..where((t) => t.playlistId.equals(_playlistId))).getSingle();
      final now = clock.now().toUtc();
      await (_database.update(
        _database.playlistsTable,
      )..where((t) => t.id.equals(_playlistId))).write(
        PlaylistsTableCompanion(
          name: flags.nameOverridden ? const Value.absent() : Value(info.name),
          description: flags.descriptionOverridden
              ? const Value.absent()
              : Value(info.description),
          artworkJson: flags.artworkOverridden
              ? const Value.absent()
              : Value(TracksRepository.encodeArtwork(info.artwork)),
          updatedAt: Value(now),
        ),
      );
      await (_database.update(
        remotes,
      )..where((t) => t.playlistId.equals(_playlistId))).write(
        PlaylistRemoteTableCompanion(
          ownerName: Value(info.ownerName),
          writable: info.writable == null
              ? const Value.absent()
              : Value(info.writable!),
          lastResult: const Value(PlaylistRefreshResult.complete),
          lastRefreshedAt: Value(now),
          status: const Value(PlaylistRemoteStatus.active),
        ),
      );
      return removed;
    },
  );

  /// 不完整：只寫 `last_result = partial`、`last_refreshed_at`、`status = active`。
  Future<bool> markPartial() => _write(
    PlaylistRemoteTableCompanion(
      lastResult: const Value(PlaylistRefreshResult.partial),
      lastRefreshedAt: Value(clock.now().toUtc()),
      status: const Value(PlaylistRemoteStatus.active),
    ),
  );

  /// 這次沒讀到任何東西：只寫 `last_result = failed`（`status` 與 `last_refreshed_at` 不動）。
  Future<bool> markFailed() => _write(
    const PlaylistRemoteTableCompanion(
      lastResult: Value(PlaylistRefreshResult.failed),
    ),
  );

  /// 遠端歌單不在了或要登入：只寫 `status`，`last_result` 不動。
  Future<bool> markStatus(PlaylistRemoteStatus status) =>
      _write(PlaylistRemoteTableCompanion(status: Value(status)));

  Future<bool> _write(PlaylistRemoteTableCompanion values) =>
      _database.transaction(() async {
        if (!await _stillCurrent()) return false;
        await (_database.update(
          _database.playlistRemoteTable,
        )..where((t) => t.playlistId.equals(_playlistId))).write(values);
        return true;
      });

  /// 代際仍是這一次的（歌單被刪也算過期）、觸發者仍有效。
  Future<bool> _stillCurrent() async {
    if (!_isCurrent()) return false;
    final remotes = _database.playlistRemoteTable;
    final row =
        await (_database.selectOnly(remotes)
              ..addColumns([remotes.refreshGeneration])
              ..where(remotes.playlistId.equals(_playlistId)))
            .getSingleOrNull();
    return row?.read(remotes.refreshGeneration) == generation;
  }

  static int? _take(Map<String, Queue<int>> queues, String key) {
    final queue = queues[key];
    return queue == null || queue.isEmpty ? null : queue.removeFirst();
  }
}
