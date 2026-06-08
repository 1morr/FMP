import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import 'base_source.dart';
import 'bilibili_source.dart';
import 'netease_source.dart';
import 'source_capabilities.dart';
import 'youtube_source.dart';

/// 音源管理器
/// 统一注册具体适配器，但调用端只按所需能力取用。
class SourceManager {
  SourceManager({List<SourceCapability>? sources})
      : _sources = List<SourceCapability>.of(
          sources ??
              [
                BilibiliSource(),
                YouTubeSource(),
                NeteaseSource(),
              ],
        );

  final List<SourceCapability> _sources;

  /// 所有已注册能力对象。调用端应优先使用下方 narrow lookup。
  List<SourceCapability> get sources => List.unmodifiable(_sources);

  /// 已注册的音源类型列表
  List<SourceType> get registeredSourceTypes {
    final seen = <SourceType>{};
    return [
      for (final source in _sources)
        if (seen.add(source.sourceType)) source.sourceType,
    ];
  }

  T? _capability<T extends SourceCapability>(SourceType type) {
    for (final source in _sources) {
      if (source.sourceType == type && source is T) {
        return source;
      }
    }
    return null;
  }

  AudioStreamSource? audioStreamSource(SourceType type) =>
      _capability<AudioStreamSource>(type);

  TrackInfoSource? trackInfoSource(SourceType type) =>
      _capability<TrackInfoSource>(type);

  SearchSource? searchSource(SourceType type) =>
      _capability<SearchSource>(type);

  PlaylistParsingSource? playlistParsingSource(SourceType type) =>
      _capability<PlaylistParsingSource>(type);

  AvailabilitySource? availabilitySource(SourceType type) =>
      _capability<AvailabilitySource>(type);

  TrackDetailSource? trackDetailSource(SourceType type) =>
      _capability<TrackDetailSource>(type);

  PagedVideoSource? pagedVideoSource(SourceType type) =>
      _capability<PagedVideoSource>(type);

  DynamicPlaylistSource? dynamicPlaylistSource(SourceType type) =>
      _capability<DynamicPlaylistSource>(type);

  DynamicPlaylistSource? dynamicPlaylistSourceForUrl(String url) {
    for (final source in _sources.whereType<DynamicPlaylistSource>()) {
      if (source.isDynamicPlaylistUrl(url)) return source;
    }
    return null;
  }

  RankingSource? rankingSource(SourceType type) =>
      _capability<RankingSource>(type);

  LiveSource? liveSource(SourceType type) => _capability<LiveSource>(type);

  TrackInfoSource? trackInfoSourceForUrl(String url) {
    for (final source in _sources.whereType<TrackInfoSource>()) {
      if (source.canHandle(url)) return source;
    }
    return null;
  }

  PlaylistParsingSource? playlistParsingSourceForUrl(String url) {
    for (final source in _sources.whereType<PlaylistParsingSource>()) {
      if (source.isPlaylistUrl(url)) return source;
    }
    return null;
  }

  SourceType? sourceTypeForUrl(String url) {
    return playlistParsingSourceForUrl(url)?.sourceType ??
        trackInfoSourceForUrl(url)?.sourceType;
  }

  /// 解析 URL 获取歌曲信息
  Future<Track?> parseUrl(String url) async {
    final source = trackInfoSourceForUrl(url);
    if (source == null) return null;

    final id = source.parseId(url);
    if (id == null) return null;

    return source.getTrackInfo(id);
  }

  /// 判断 URL 是否是播放列表
  bool isPlaylistUrl(String url) {
    return playlistParsingSourceForUrl(url) != null;
  }

  /// 解析播放列表
  Future<PlaylistParseResult?> parsePlaylist(
    String url, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final source = playlistParsingSourceForUrl(url);
    if (source == null) return null;
    return source.parsePlaylist(url, page: page, pageSize: pageSize);
  }

  /// 刷新歌曲的音频 URL
  Future<Track> refreshAudioUrl(Track track) async {
    final source = trackInfoSource(track.sourceType);
    if (source == null) {
      throw Exception('Source not found for ${track.sourceType}');
    }

    return source.refreshAudioUrl(track);
  }

  /// 检查歌曲是否需要刷新 URL
  bool needsRefresh(Track track) {
    if (track.audioUrl == null) return true;
    if (track.audioUrlExpiry == null) return false;
    // 提前5分钟刷新
    return DateTime.now()
        .isAfter(track.audioUrlExpiry!.subtract(const Duration(minutes: 5)));
  }

  /// 搜索
  Future<Map<SourceType, SearchResult>> searchAll(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final results = <SourceType, SearchResult>{};

    await Future.wait(_sources.whereType<SearchSource>().map((source) async {
      try {
        final result =
            await source.search(query, page: page, pageSize: pageSize);
        results[source.sourceType] = result;
      } catch (_) {
        // 忽略单个源的错误
      }
    }));

    return results;
  }

  /// 从单个源搜索
  Future<SearchResult> searchFrom(
    SourceType type,
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final source = searchSource(type);
    if (source == null) {
      throw Exception('Source not found: $type');
    }

    return source.search(query, page: page, pageSize: pageSize);
  }

  /// 释放所有音源资源（关闭 HTTP 客户端等）
  void dispose() {
    for (final source in _sources) {
      if (source is BilibiliSource) source.dispose();
      if (source is YouTubeSource) source.dispose();
      if (source is NeteaseSource) source.dispose();
    }
    _sources.clear();
  }
}

// ========== Providers ==========

/// SourceManager Provider
final sourceManagerProvider = Provider<SourceManager>((ref) {
  final manager = SourceManager();
  ref.onDispose(manager.dispose);
  return manager;
});

/// URL 解析 Provider
final parseUrlProvider =
    FutureProvider.family<Track?, String>((ref, url) async {
  final manager = ref.watch(sourceManagerProvider);
  return manager.parseUrl(url);
});

/// 播放列表解析 Provider
final parsePlaylistProvider =
    FutureProvider.family<PlaylistParseResult?, String>((ref, url) async {
  final manager = ref.watch(sourceManagerProvider);
  return manager.parsePlaylist(url);
});
