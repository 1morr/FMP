import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/domain/track_info.dart';

/// 電台清單的一列（`radio_stations`，ADR 0031 §決定 1）。
///
/// [liveStatus]、[liveTitle]、[statusCheckedAt] 是最後一次查到的狀態，還沒查過為
/// `null`。「查詢失敗」不存在資料庫（D10），由 `RadioService` 在記憶體標。
@immutable
final class RadioStation {
  const RadioStation({
    required this.id,
    required this.pluginId,
    required this.roomId,
    required this.title,
    required this.sortOrder,
    required this.addedAt,
    this.hostName,
    this.artwork = const [],
    this.liveStatus,
    this.liveTitle,
    this.statusCheckedAt,
  });

  final int id;
  final String pluginId;
  final String roomId;
  final String title;
  final String? hostName;
  final List<TrackArtwork> artwork;
  final int sortOrder;
  final DateTime addedAt;
  final RadioLiveStatus? liveStatus;
  final String? liveTitle;
  final DateTime? statusCheckedAt;

  @override
  bool operator ==(Object other) =>
      other is RadioStation &&
      other.id == id &&
      other.pluginId == pluginId &&
      other.roomId == roomId &&
      other.title == title &&
      other.hostName == hostName &&
      listEquals(other.artwork, artwork) &&
      other.sortOrder == sortOrder &&
      other.addedAt == addedAt &&
      other.liveStatus == liveStatus &&
      other.liveTitle == liveTitle &&
      other.statusCheckedAt == statusCheckedAt;

  @override
  int get hashCode => Object.hash(
    id,
    pluginId,
    roomId,
    title,
    hostName,
    Object.hashAll(artwork),
    sortOrder,
    addedAt,
    liveStatus,
    liveTitle,
    statusCheckedAt,
  );

  @override
  String toString() =>
      'RadioStation(id: $id, $pluginId:$roomId, sortOrder: $sortOrder)';
}

/// `radio_stations` 的存取。
final class RadioRepository {
  RadioRepository(this._database);

  final AppDatabase _database;

  SimpleSelectStatement<$RadioStationsTableTable, RadioStationRow>
  get _ordered => _database.select(_database.radioStationsTable)
    ..orderBy([
      (t) => OrderingTerm.asc(t.sortOrder),
      (t) => OrderingTerm.asc(t.id),
    ]);

  /// 目前的清單，依 `sort_order`；之後每次改變再發一次。
  Stream<List<RadioStation>> watch() =>
      _ordered.watch().map((rows) => [for (final row in rows) _fromRow(row)]);

  Future<List<RadioStation>> list() async => [
    for (final row in await _ordered.get()) _fromRow(row),
  ];

  /// 加在清單最後。同（插件, 房間）已經在清單裡就什麼都不寫、回傳 `false`。
  Future<bool> add({
    required String pluginId,
    required String roomId,
    required String title,
    String? hostName,
    List<TrackArtwork> artwork = const [],
    required DateTime addedAt,
    RadioLiveStatus? liveStatus,
    String? liveTitle,
    DateTime? statusCheckedAt,
  }) => _database.transaction(() async {
    final existing =
        await (_database.select(_database.radioStationsTable)..where(
              (t) => t.pluginId.equals(pluginId) & t.roomId.equals(roomId),
            ))
            .getSingleOrNull();
    if (existing != null) return false;
    final last = await (_database.selectOnly(
      _database.radioStationsTable,
    )..addColumns([_database.radioStationsTable.sortOrder.max()])).getSingle();
    final next =
        (last.read(_database.radioStationsTable.sortOrder.max()) ?? -1) + 1;
    await _database
        .into(_database.radioStationsTable)
        .insert(
          RadioStationsTableCompanion.insert(
            pluginId: pluginId,
            roomId: roomId,
            title: title,
            hostName: Value(hostName),
            artworkJson: Value(TracksRepository.encodeArtwork(artwork)),
            sortOrder: next,
            addedAt: addedAt.toUtc(),
            liveStatus: Value(liveStatus),
            liveTitle: Value(liveTitle),
            statusCheckedAt: Value(statusCheckedAt?.toUtc()),
          ),
        );
    return true;
  });

  /// 沒有這一列時什麼都不做。
  Future<void> remove(int id) => (_database.delete(
    _database.radioStationsTable,
  )..where((t) => t.id.equals(id))).go();

  /// 依 [ids] 的順序整批重寫 `sort_order`（0, 1, 2…）。不在 [ids] 裡的列不動。
  Future<void> reorder(List<int> ids) => _database.transaction(() async {
    for (final (index, id) in ids.indexed) {
      await (_database.update(_database.radioStationsTable)
            ..where((t) => t.id.equals(id)))
          .write(RadioStationsTableCompanion(sortOrder: Value(index)));
    }
  });

  /// 記下查到的狀態。沒有這一列（查詢期間被刪了）時什麼都不做。
  Future<void> updateStatus(
    int id, {
    required RadioLiveStatus status,
    required String liveTitle,
    required DateTime checkedAt,
  }) =>
      (_database.update(
        _database.radioStationsTable,
      )..where((t) => t.id.equals(id))).write(
        RadioStationsTableCompanion(
          liveStatus: Value(status),
          liveTitle: Value(liveTitle),
          statusCheckedAt: Value(checkedAt.toUtc()),
        ),
      );

  static RadioStation _fromRow(RadioStationRow row) => RadioStation(
    id: row.id,
    pluginId: row.pluginId,
    roomId: row.roomId,
    title: row.title,
    hostName: row.hostName,
    artwork: TracksRepository.decodeArtwork(row.artworkJson),
    sortOrder: row.sortOrder,
    addedAt: row.addedAt,
    liveStatus: row.liveStatus,
    liveTitle: row.liveTitle,
    statusCheckedAt: row.statusCheckedAt,
  );
}
