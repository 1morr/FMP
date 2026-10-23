import 'dart:math' as math;

import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/mix_identity.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/legacy_import/legacy_source_ids.dart';
import 'package:fmp/legacy_import/legacy_track_catalog.dart';
import 'package:fmp/legacy_import/play_history_limit.dart';
import 'package:fmp/legacy_import/remote_playlist_url.dart';
import 'package:fmp/legacy_import/skip_reason.dart';

/// 舊版（Isar）的內容 → 新版的匯入包（M5 design §5）。
///
/// 純 Dart、沒有 I/O，不改 [LegacySnapshot]。每一筆略過都帶理由並計數，進
/// `ImportRecord.summary`。
///
/// 結構：[convert] 依序跑各段（曲目鍵的對照、歌單、佇列、歷史、電台、曲目、外部來源），每段
/// 是 [_Conversion] 的一個方法，結果放進匯入包的對應欄位。之後的帳號（PR 4）與設定（PR 5）
/// 各加一段，不改既有的段落。
final class LegacyConverter {
  const LegacyConverter();

  /// [source] 與 [backupVersion] 只寫進 `ImportRecord`；[now] 給之後需要「匯入時間」的段落
  /// （帳號的 `logged_in_at` 預設，PR 4）。
  ImportBundle convert(
    LegacySnapshot snapshot, {
    required LegacyImportSource source,
    int? backupVersion,
    required DateTime now,
  }) => _Conversion(snapshot, source, backupVersion, now).run();
}

/// `ImportSummary.collections` 的鍵。
abstract final class SummaryCollection {
  static const tracks = 'tracks';
  static const playlists = 'playlists';
  static const playlistEntries = 'playlistEntries';
  static const queue = 'queue';
  static const history = 'history';
  static const radioStations = 'radioStations';
  static const trackOrigins = 'trackOrigins';
}

final class _Conversion {
  _Conversion(this.snapshot, this.source, this.backupVersion, this.now);

  final LegacySnapshot snapshot;
  final LegacyImportSource source;
  final int? backupVersion;
  final DateTime now;

  final _tallies = <String, Tally>{};
  Tally _tally(String name) => _tallies.putIfAbsent(name, Tally.new);

  /// 被歌單、佇列、歷史參照到的曲目鍵；沒被參照的曲目不寫。
  final _referenced = <TrackKeyParts>{};

  /// 歷史裡出現而 `Track` 裡沒有的曲目，用歷史列自己的快照補。
  final _snapshotTracks = <TrackKeyParts, TrackInfo>{};

  late final LegacyTrackCatalog _catalog;

  ImportBundle run() {
    _catalog = LegacyTrackCatalog.build(
      snapshot.tracks,
      _tally(SummaryCollection.tracks),
    );
    final playlists = _playlists();
    final queue = _queue();
    final history = _history();
    final radioStations = _radioStations();
    final tracks = _tracks();
    final origins = _trackOrigins();
    return ImportBundle(
      record: ImportRecord(
        source: source,
        legacySchemaVersion: source == LegacyImportSource.database
            ? snapshot.storedSchemaVersion
            : null,
        backupVersion: backupVersion,
        summary: ImportSummary(
          collections: {
            for (final entry in _tallies.entries)
              entry.key: entry.value.toSummary(),
          },
        ),
      ),
      tracks: tracks,
      playlists: playlists,
      queue: queue.entries,
      playerState: queue.state,
      history: history,
      radioStations: radioStations,
      trackOrigins: origins,
    );
  }

  // ------------------------------------------------------------ 歌單（§5.3）

  List<ImportPlaylist> _playlists() {
    final tally = _tally(SummaryCollection.playlists);
    final entryTally = _tally(SummaryCollection.playlistEntries);
    final sorted = [...snapshot.playlists]
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
    final accountUserIds = {
      for (final account in snapshot.accounts)
        if (blankToNull(account.userId) != null)
          account.platform: account.userId!,
    };
    final usedRemotes = <RecognizedRemote>{};
    final result = <ImportPlaylist>[];
    for (final playlist in sorted) {
      tally.read++;
      final legacyId = source == LegacyImportSource.database
          ? playlist.id
          : null;
      final updatedAt = (playlist.updatedAt ?? playlist.createdAt).toUtc();
      final description = blankToNull(playlist.description);
      final artwork = artworkOf(playlist.coverUrl);

      if (playlist.isMix) {
        final seed = blankToNull(playlist.mixSeedVideoId)?.trim();
        if (seed == null) {
          tally.skip(SkipReason.mixWithoutSeed);
          continue;
        }
        tally.written++;
        result.add(
          ImportPlaylist(
            legacyPlaylistId: legacyId,
            kind: PlaylistKind.mix,
            name: playlist.name,
            description: description,
            artwork: artwork,
            createdAt: playlist.createdAt.toUtc(),
            updatedAt: updatedAt,
            mixPluginId: legacyYoutube,
            mixSeedSourceId: seed,
          ),
        );
        continue;
      }

      RecognizedRemote? recognized;
      final url = blankToNull(playlist.sourceUrl);
      if (url != null) {
        recognized = recognizeRemotePlaylistUrl(url);
        if (recognized == null) {
          tally.note(SkipReason.remoteNotRecognized);
        } else if (!usedRemotes.add(recognized)) {
          tally.note(SkipReason.duplicateRemote);
          recognized = null;
        } else {
          final declared = blankToNull(playlist.importSourceType);
          if (declared != null && declared != recognized.pluginId) {
            tally.note(SkipReason.importSourceMismatch);
          }
        }
      }

      final entries = <ImportPlaylistEntry>[];
      for (final id in playlist.trackIds) {
        entryTally.read++;
        final key = _catalog.keyOfId(id);
        if (key == null) {
          entryTally.skip(
            _catalog.isUnknownSource(id)
                ? SkipReason.unknownSource
                : SkipReason.danglingTrackId,
          );
          continue;
        }
        entryTally.written++;
        _referenced.add(key);
        entries.add(
          ImportPlaylistEntry(
            track: key,
            // 失效標記只有匯入歌單有（遠端說這一項失效）。
            unavailable:
                recognized != null && !_catalog.rowOfId(id)!.isAvailable,
          ),
        );
      }

      final ownerUserId = blankToNull(playlist.ownerUserId);
      tally.written++;
      result.add(
        ImportPlaylist(
          legacyPlaylistId: legacyId,
          kind: recognized == null ? PlaylistKind.local : PlaylistKind.imported,
          name: playlist.name,
          description: description,
          artwork: artwork,
          createdAt: playlist.createdAt.toUtc(),
          updatedAt: updatedAt,
          remote: recognized == null
              ? null
              : ImportPlaylistRemote(
                  pluginId: recognized.pluginId,
                  remoteId: recognized.remoteId,
                  ownerName: blankToNull(playlist.ownerName),
                  writable:
                      ownerUserId != null &&
                      accountUserIds[recognized.pluginId] == ownerUserId,
                  artworkOverridden: playlist.hasCustomCover,
                  refreshIntervalHours: playlist.refreshIntervalHours,
                  lastRefreshedAt: playlist.lastRefreshed?.toUtc(),
                ),
          entries: entries,
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------ 佇列（§5.4）

  ({List<ImportQueueEntry> entries, PlayerState? state}) _queue() {
    final tally = _tally(SummaryCollection.queue);
    final queue = snapshot.playQueues.firstOrNull;
    // 沒有這一列、或整列都是型別預設：沒有值得匯入的狀態，新版的預設生效。
    if (queue == null || _isTypeDefault(queue)) {
      return (entries: const [], state: null);
    }

    // 自然順序：開著隨機時 trackIds 是洗過的，originalOrder 才是原本的順序。
    final original = queue.originalOrder;
    final natural =
        queue.isShuffleEnabled && original != null && original.isNotEmpty
        ? original
        : queue.trackIds;
    final entries = <ImportQueueEntry>[];
    // 自然順序的第 i 項在 entries 裡的位置；略過的沒有。
    final positionOf = <int, int>{};
    for (var i = 0; i < natural.length; i++) {
      final id = natural[i];
      tally.read++;
      final key = _catalog.keyOfId(id);
      if (key == null) {
        tally.skip(
          _catalog.isUnknownSource(id)
              ? SkipReason.unknownSource
              : SkipReason.danglingTrackId,
        );
        continue;
      }
      tally.written++;
      _referenced.add(key);
      positionOf[i] = entries.length;
      entries.add(ImportQueueEntry(track: key));
    }
    // 佇列是空的（或全被略過）也寫播放狀態：舊版空佇列也會恢復音量與循環模式。
    return (
      entries: entries,
      state: PlayerState(
        currentPosition: _currentPosition(queue, natural, positionOf),
        position: Duration(milliseconds: math.max(0, queue.lastPositionMs)),
        loopMode: switch (queue.loopMode) {
          LegacyLoopMode.none => LoopMode.off,
          LegacyLoopMode.all => LoopMode.all,
          LegacyLoopMode.one => LoopMode.one,
        },
        shuffleEnabled: queue.isShuffleEnabled,
        volume: queue.lastVolume.isNaN
            ? 1.0
            : queue.lastVolume.clamp(0.0, 1.0).toDouble(),
        muted: false,
        mix: _mixIdentity(queue),
      ),
    );
  }

  bool _isTypeDefault(LegacyPlayQueue queue) =>
      queue.trackIds.isEmpty &&
      queue.currentIndex == _legacyNullLong &&
      queue.lastPositionMs == _legacyNullLong &&
      queue.lastVolume.isNaN &&
      !queue.isShuffleEnabled &&
      !queue.isMixMode &&
      queue.loopMode == LegacyLoopMode.none;

  /// `trackIds[currentIndex]` 在自然順序裡的位置；同一首出現多次時第 k 次對第 k 次。
  int? _currentPosition(
    LegacyPlayQueue queue,
    List<int> natural,
    Map<int, int> positionOf,
  ) {
    final index = queue.currentIndex;
    if (index < 0 || index >= queue.trackIds.length) return null;
    final id = queue.trackIds[index];
    final occurrence = queue.trackIds.take(index).where((e) => e == id).length;
    var seen = 0;
    for (var i = 0; i < natural.length; i++) {
      if (natural[i] != id) continue;
      if (seen == occurrence) return positionOf[i];
      seen++;
    }
    return null;
  }

  MixIdentity? _mixIdentity(LegacyPlayQueue queue) {
    final mixId = blankToNull(queue.mixPlaylistId);
    final title = blankToNull(queue.mixTitle);
    if (!queue.isMixMode || mixId == null || title == null) return null;
    return MixIdentity(pluginId: legacyYoutube, mixId: mixId, title: title);
  }

  // ------------------------------------------------------------ 播放歷史（§5.5）

  /// 依 `played_at` 由舊到新（相同時間後面的算新）；匯入包的順序就是寫入順序。
  List<ImportHistoryEntry> _history() {
    final tally = _tally(SummaryCollection.history);
    final candidates = <LegacyPlayHistory>[];
    for (final row in snapshot.playHistory) {
      tally.read++;
      if (legacySourceIds.contains(row.sourceType)) {
        candidates.add(row);
      } else {
        tally.skip(SkipReason.unknownSource);
      }
    }
    candidates.sort((a, b) {
      final byTime = b.playedAt.compareTo(a.playedAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });

    final limit = effectivePlayHistoryLimit(
      snapshot.settings.firstOrNull?.playHistoryLimit ??
          legacyDefaultPlayHistoryLimit,
    );
    final kept = candidates.take(limit).toList();
    if (kept.length < candidates.length) {
      tally.skip(SkipReason.overHistoryLimit, candidates.length - kept.length);
    }

    final entries = <ImportHistoryEntry>[];
    // 由新到舊走：同一個鍵缺 `Track` 時，用最新那筆的快照。
    for (final row in kept) {
      final legacyKey = TrackKeyParts(
        sourceTypeId: row.sourceType,
        sourceId: row.sourceId,
        cid: row.cid,
      );
      var key = _catalog.keyOfLegacyKey(legacyKey);
      if (key == null && row.sourceType == legacyBilibili && row.cid != null) {
        // `Track` 判定這支影片是單 P：歷史裡舊版補的三段鍵併進兩段鍵。
        key = _catalog.singlePartKeyOf(row.sourceId);
        // `Track` 裡完全沒有這支影片：沒有 `pageCount` 可看，不知道是不是單 P，照原樣。
        if (key == null && !_catalog.knowsBilibiliVideo(row.sourceId)) {
          tally.note(SkipReason.unverifiedPart);
        }
      }
      if (key == null) {
        final unmatched = legacyKey;
        key = unmatched;
        if (!_catalog.containsKey(unmatched)) {
          _snapshotTracks.putIfAbsent(
            unmatched,
            () => _trackOfHistory(row, unmatched),
          );
        }
      }
      tally.written++;
      _referenced.add(key);
      entries.add(
        ImportHistoryEntry(track: key, playedAt: row.playedAt.toUtc()),
      );
    }
    return entries.reversed.toList();
  }

  TrackInfo _trackOfHistory(LegacyPlayHistory row, TrackKeyParts key) =>
      TrackInfo(
        sourceTypeId: key.sourceTypeId,
        sourceId: key.sourceId,
        cid: key.cid,
        title: row.title,
        uploader: blankToNull(row.artist),
        duration: durationOf(row.durationMs),
        artwork: artworkOf(row.thumbnailUrl),
      );

  // ------------------------------------------------------------ 電台（§5.6）

  List<ImportRadioStation> _radioStations() {
    final tally = _tally(SummaryCollection.radioStations);
    final sorted = [...snapshot.radioStations]
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
      });
    final seen = <(String, String)>{};
    final result = <ImportRadioStation>[];
    for (final station in sorted) {
      tally.read++;
      if (!legacySourceIds.contains(station.sourceType)) {
        tally.skip(SkipReason.unknownSource);
        continue;
      }
      if (!seen.add((station.sourceType, station.sourceId))) {
        tally.skip(SkipReason.duplicateStation);
        continue;
      }
      tally.written++;
      result.add(
        ImportRadioStation(
          pluginId: station.sourceType,
          roomId: station.sourceId,
          title: station.title,
          hostName: blankToNull(station.hostName),
          artwork: artworkOf(station.thumbnailUrl),
          addedAt: station.createdAt.toUtc(),
        ),
      );
    }
    return result;
  }

  // ------------------------------------------------------------ 曲目（§5.2）

  List<TrackInfo> _tracks() {
    final tally = _tally(SummaryCollection.tracks);
    tally.read += snapshot.tracks.length;
    final result = <TrackInfo>[];
    for (final MapEntry(:key, value: row) in _catalog.winners.entries) {
      if (_referenced.contains(key)) {
        tally.written++;
        result.add(trackInfoOf(row, key));
      } else {
        tally.skip(SkipReason.unreferenced);
      }
    }
    // 歷史快照補的曲目也算讀到、寫出的曲目。
    for (final info in _snapshotTracks.values) {
      tally.read++;
      tally.written++;
      result.add(info);
    }
    return result;
  }

  // ------------------------------------------------------------ 外部來源（§5.7）

  List<ImportTrackOrigin> _trackOrigins() {
    final tally = _tally(SummaryCollection.trackOrigins);
    final result = <ImportTrackOrigin>[];
    for (final MapEntry(:key, value: row) in _catalog.winners.entries) {
      final origin = blankToNull(row.originalSource);
      if (origin == null || !_referenced.contains(key)) continue;
      tally.read++;
      final id = row.originalSongId;
      if (id == null || !isExternalOriginId(origin, id)) {
        tally.skip(SkipReason.originIdFormat);
        continue;
      }
      tally.written++;
      result.add(
        ImportTrackOrigin(track: key, originPluginId: origin, originId: id),
      );
    }
    return result;
  }
}

/// 舊 `originalSongId` 的格式是否與新插件的 `sourceId` 相同（M5 design §5.7）。
///
/// - `qqmusic` 1.0.0：歌曲的 `mid`，去掉前後空白後不為空、不含 `:`
///   （`qqmusic/src/plugin.js` 的 `trackOfSong`）；舊 id 要原樣就是這個形狀，否則新插件給的
///   `sourceId` 與它不同；
/// - `netease` 1.7.0：整串數字、是安全整數（`netease/src/plugin.js` 的 `trackDetail`：
///   `/^\d+$/` 與 `Number.isSafeInteger`）；
/// - 其他（`spotify` 等）：沒有對應的曲目 id，不匯入。
bool isExternalOriginId(String originPluginId, String id) {
  switch (originPluginId) {
    case legacyQqmusic:
      return id.isNotEmpty && id == id.trim() && !id.contains(':');
    case legacyNetease:
      if (!_digits.hasMatch(id)) return false;
      final value = int.tryParse(id);
      return value != null && value <= _maxSafeInteger;
    default:
      return false;
  }
}

const _legacyNullLong = -9223372036854775808;
final _digits = RegExp(r'^\d+$');
const _maxSafeInteger = 9007199254740991;
