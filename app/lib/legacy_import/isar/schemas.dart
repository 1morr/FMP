import 'package:isar_community/isar.dart';

import 'account.dart';
import 'download_task.dart';
import 'lyrics_match.dart';
import 'lyrics_title_parse_cache.dart';
import 'play_history.dart';
import 'play_queue.dart';
import 'playlist.dart';
import 'radio_station.dart';
import 'search_history.dart';
import 'settings.dart';
import 'track.dart';

export 'account.dart';
export 'download_task.dart';
export 'lyrics_match.dart';
export 'lyrics_title_parse_cache.dart';
export 'play_history.dart';
export 'play_queue.dart';
export 'playlist.dart';
export 'radio_station.dart';
export 'search_history.dart';
export 'settings.dart';
export 'track.dart';

/// 舊版資料庫的完整 11 個 collection schema。
///
/// 開庫一律傳全部：只傳一部分的話，Isar 可能把沒傳的 collection 當成已移除而
/// 刪掉它的資料（design §0.3）。
final List<CollectionSchema<dynamic>> legacyIsarSchemas = [
  TrackSchema,
  PlaylistSchema,
  PlayQueueSchema,
  PlayHistorySchema,
  SettingsSchema,
  SearchHistorySchema,
  DownloadTaskSchema,
  RadioStationSchema,
  LyricsMatchSchema,
  LyricsTitleParseCacheSchema,
  AccountSchema,
];
