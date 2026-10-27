import 'dart:ui' show Color;

import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/mix_identity.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/domain/track_info.dart';

// 匯入包的測試資料。時間都是遠早於「現在」的固定值：寫入若偷偷換成現在的時間，比對就紅。

/// 匯入時間，與下面的原始時間錯開。
final importedAt = DateTime.utc(2026, 10, 23, 8, 30);

DateTime at(int minutes) =>
    DateTime.utc(2020, 1, 1).add(Duration(minutes: minutes));

TrackInfo track(
  String sourceId, {
  String source = 'bilibili',
  int? cid,
  int? partIndex,
  String? parentTitle,
}) => TrackInfo(
  sourceTypeId: source,
  sourceId: sourceId,
  cid: cid,
  title: 'Song $sourceId',
  uploader: 'Uploader $sourceId',
  duration: Duration(seconds: 200 + sourceId.length),
  artwork: [
    TrackArtwork(url: Uri.parse('https://example.test/$sourceId.jpg')),
    TrackArtwork(
      url: Uri.parse('https://example.test/$sourceId-s.jpg'),
      width: 120,
    ),
  ],
  partIndex: partIndex,
  parentTitle: parentTitle,
);

ImportRecord record({
  LegacyImportSource source = LegacyImportSource.database,
}) => ImportRecord(
  source: source,
  legacySchemaVersion: source == LegacyImportSource.database ? 4 : null,
  backupVersion: source == LegacyImportSource.backup ? 5 : null,
  summary: const ImportSummary(
    collections: {
      'tracks': CollectionSummary(
        read: 10,
        written: 8,
        skipped: {'duplicateTrack': 1, 'unreferenced': 1},
      ),
    },
    unimportedSettings: ['themeColor'],
    reloginPlatforms: ['netease'],
  ),
);

/// 每張表都有資料的匯入包：三首曲目（一首分 P）、三張歌單（本機、匯入、Mix）、佇列、
/// 播放狀態（Mix）、歷史、電台、來源、帳號與四組設定。
ImportBundle fullBundle() {
  final a = track('BV1a', cid: 11, partIndex: 1, parentTitle: 'Video a');
  final b = track('BV1b');
  final c = track('dQw4w9WgXcQ', source: 'youtube');
  return ImportBundle(
    record: record(),
    tracks: [a, b, c],
    playlists: [
      ImportPlaylist(
        legacyPlaylistId: 7,
        kind: PlaylistKind.local,
        name: 'Local list',
        description: 'About it',
        artwork: [TrackArtwork(url: Uri.parse('https://example.test/p.jpg'))],
        createdAt: at(1),
        updatedAt: at(2),
        entries: [
          ImportPlaylistEntry(track: b.key),
          ImportPlaylistEntry(track: a.key),
          ImportPlaylistEntry(track: b.key),
        ],
      ),
      ImportPlaylist(
        legacyPlaylistId: 3,
        kind: PlaylistKind.imported,
        name: 'Imported list',
        createdAt: at(3),
        updatedAt: at(4),
        remote: ImportPlaylistRemote(
          pluginId: 'bilibili',
          remoteId: '12345',
          ownerName: 'Owner',
          writable: true,
          artworkOverridden: true,
          refreshIntervalHours: 48,
          lastRefreshedAt: at(5),
        ),
        entries: [
          ImportPlaylistEntry(track: a.key),
          ImportPlaylistEntry(track: c.key, unavailable: true),
        ],
      ),
      ImportPlaylist(
        legacyPlaylistId: 9,
        kind: PlaylistKind.mix,
        name: 'Mix list',
        createdAt: at(6),
        updatedAt: at(6),
        mixPluginId: 'youtube',
        mixSeedSourceId: 'dQw4w9WgXcQ',
      ),
    ],
    queue: [
      ImportQueueEntry(track: c.key, shuffleRank: 1),
      ImportQueueEntry(track: a.key, shuffleRank: 0),
    ],
    playerState: const PlayerState(
      currentPosition: 1,
      position: Duration(seconds: 42),
      loopMode: LoopMode.all,
      shuffleEnabled: true,
      volume: 0.5,
      muted: false,
      mix: MixIdentity(pluginId: 'youtube', mixId: 'RDx', title: 'My mix'),
    ),
    history: [
      ImportHistoryEntry(track: a.key, playedAt: at(10)),
      ImportHistoryEntry(track: b.key, playedAt: at(12)),
      ImportHistoryEntry(track: a.key, playedAt: at(11)),
    ],
    searchHistory: [
      ImportSearchHistoryEntry(query: 'lofi', searchedAt: at(20)),
      ImportSearchHistoryEntry(query: 'jazz', searchedAt: at(21)),
    ],
    radioStations: [
      ImportRadioStation(
        pluginId: 'bilibili',
        roomId: '99',
        title: 'Room',
        hostName: 'Host',
        artwork: [TrackArtwork(url: Uri.parse('https://example.test/r.jpg'))],
        addedAt: at(20),
      ),
      ImportRadioStation(
        pluginId: 'youtube',
        roomId: 'live1',
        title: 'Other room',
        addedAt: at(21),
      ),
    ],
    trackOrigins: [
      ImportTrackOrigin(
        track: b.key,
        originPluginId: 'qqmusic',
        originId: '0039xyz',
      ),
    ],
    accounts: [
      Account(
        pluginId: 'bilibili',
        userId: '42',
        displayName: 'Fake User',
        avatarJson: '[{"url":"https://example.test/u.jpg"}]',
        status: AccountStatus.active,
        loggedInAt: at(30),
        lastRefreshAt: at(31),
      ),
    ],
    appearance: const AppearanceSettings(
      themeMode: ThemeModeSetting.dark,
      locale: LocaleSetting.zhTw,
      seedColor: Color(0xFF336699),
      fontFamily: 'serif',
    ),
    network: const NetworkSettings(radioStatusIntervalMinutes: 10),
    playback: const PlaybackSettings(
      audioQuality: AudioQuality.medium,
      playHistoryLimit: 5000,
      rememberPosition: false,
    ),
    browseAsLoggedIn: const {'bilibili': true, 'youtube': false},
    layout: const LayoutState(panelExpanded: false, panelWidth: 420),
  );
}
