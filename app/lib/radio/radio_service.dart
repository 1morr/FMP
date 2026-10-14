import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/radio/radio_status_jobs.dart';

/// 電台頁一列的四種顯示狀態（ADR 0031 §決定 4）。「查詢失敗」不是未開播。
enum RadioStatus { live, offline, queryFailed, unchecked }

/// 電台清單的一列加上記憶體裡的「查詢失敗」。
@immutable
final class RadioEntry {
  const RadioEntry({required this.station, required this.queryFailed});

  final RadioStation station;

  /// 最近一次查詢失敗（只在記憶體，D10）。
  final bool queryFailed;

  RadioStatus get status => queryFailed
      ? RadioStatus.queryFailed
      : switch (station.liveStatus) {
          RadioLiveStatus.live => RadioStatus.live,
          RadioLiveStatus.offline => RadioStatus.offline,
          null => RadioStatus.unchecked,
        };

  @override
  bool operator ==(Object other) =>
      other is RadioEntry &&
      other.station == station &&
      other.queryFailed == queryFailed;

  @override
  int get hashCode => Object.hash(station, queryFailed);
}

/// 電台清單與每列的狀態；資料庫或失敗標記一變就更新。
final radioEntriesProvider = Provider<AsyncValue<List<RadioEntry>>>((ref) {
  final failed = ref.watch(radioQueryFailuresProvider);
  return ref
      .watch(radioStationsProvider)
      .whenData(
        (stations) => [
          for (final station in stations)
            RadioEntry(
              station: station,
              queryFailed: failed.contains(station.id),
            ),
        ],
      );
});

/// 新增電台的結果，電台頁依它顯示提示。
enum AddRadioResult {
  /// 沒有插件認得這個網址。
  unrecognizedUrl,

  /// 已在電台清單。
  alreadyAdded,

  /// 已加入。
  added,
}

final radioServiceProvider = Provider<RadioService>(RadioService.new);

/// 電台清單的操作（ADR 0031 §決定 1、2、M3 design §9.1）。
final class RadioService {
  RadioService(this._ref);

  final Ref _ref;

  /// 以網址新增：依序問每個已啟用、宣告 `live` 的插件 `liveRoomFromUrl`，第一個回
  /// `roomId` 的插件勝出，再以 `liveStatus` 取標題、主播、封面與狀態。寫入與判斷重複
  /// 用 `liveStatus` 回傳的 `roomId`，它可能和網址裡的不同（B 站短號回長號）。
  ///
  /// 失敗一律丟 `AppError`，由呼叫端提示：插件的錯誤（網路、查不到）原樣丟出，其他的
  /// （插件清單、資料庫）包成 `UnexpectedError`。插件拋錯就停在那裡，不再問下一個。
  Future<AddRadioResult> addFromUrl(String url) =>
      _asAppError(() => _addFromUrl(url));

  Future<AddRadioResult> _addFromUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return AddRadioResult.unrecognizedUrl;
    final plugins = await _ref.read(pluginRegistryProvider.future);
    for (final plugin in plugins.values) {
      if (!plugin.manifest.capabilities.contains(PluginCapability.live)) {
        continue;
      }
      final found = await plugin.liveRoomFromUrl(LiveUrlQuery(url: trimmed));
      if (found == null) continue;
      final room = await plugin.liveStatus(LiveRoomQuery(roomId: found.roomId));
      return _addRoom(plugin.manifest.id, room);
    }
    return AddRadioResult.unrecognizedUrl;
  }

  /// 加為電台（搜尋頁直播間結果的選單）：直接以 [room] 寫入。已在清單回
  /// [AddRadioResult.alreadyAdded]。失敗丟 `AppError`（同 [addFromUrl]）。
  Future<AddRadioResult> addRoom(String pluginId, LiveRoom room) =>
      _asAppError(() => _addRoom(pluginId, room));

  Future<AddRadioResult> _addRoom(String pluginId, LiveRoom room) async {
    final added = await _ref
        .read(radioRepositoryProvider)
        .add(
          pluginId: pluginId,
          roomId: room.roomId,
          title: room.title,
          hostName: room.hostName,
          artwork: [
            for (final image in room.artwork)
              TrackArtwork(url: image.url, width: image.width),
          ],
          addedAt: clock.now(),
          liveStatus: switch (room.status) {
            LiveRoomStatus.live => RadioLiveStatus.live,
            LiveRoomStatus.offline => RadioLiveStatus.offline,
          },
          liveTitle: room.title,
          statusCheckedAt: clock.now(),
        );
    return added ? AddRadioResult.added : AddRadioResult.alreadyAdded;
  }

  Future<void> remove(int id) => _ref.read(radioRepositoryProvider).remove(id);

  /// 拖曳後的新順序（電台 id 由上到下）：整批重寫 `sort_order`。
  Future<void> reorder(List<int> ids) =>
      _ref.read(radioRepositoryProvider).reorder(ids);

  /// 手動刷新每個插件的狀態（不看間隔）；見 [RadioStatusJobs.refreshAll]。
  /// 失敗丟的是狀態工作的 `AppError`。
  Future<RadioRefreshResult> refresh() =>
      _ref.read(radioStatusJobsProvider.notifier).refreshAll();
}

/// 電台頁以 `AppError` 顯示提示（ADR 0013）：不是 `AppError` 的失敗包成
/// `UnexpectedError`，堆疊不變。
Future<T> _asAppError<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(AppError.wrap(error, stackTrace), stackTrace);
  }
}
