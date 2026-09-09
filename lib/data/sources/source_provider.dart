import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/netease_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/youtube_source.dart';

/// 音源管理器
/// 统一注册具体适配器，但调用端只按所需能力取用。
class SourceManager with Logging {
  SourceManager({List<SourceCapability>? sources})
    : _sources = List<SourceCapability>.of(
        sources ?? [BilibiliSource(), YouTubeSource(), NeteaseSource()],
      );

  final List<SourceCapability> _sources;

  /// 所有已注册能力对象。调用端应优先使用下方 narrow lookup。
  List<SourceCapability> get sources => List.unmodifiable(_sources);

  /// 已注册的音源类型列表
  List<String> get registeredSourceTypes {
    final seen = <String>{};
    return [
      for (final source in _sources)
        if (seen.add(source.sourceType)) source.sourceType,
    ];
  }

  T? _capability<T extends SourceCapability>(String type) {
    for (final source in _sources) {
      if (source.sourceType == type && source is T) {
        return source;
      }
    }
    return null;
  }

  AudioStreamSource? audioStreamSource(String type) =>
      _capability<AudioStreamSource>(type);

  TrackInfoSource? trackInfoSource(String type) =>
      _capability<TrackInfoSource>(type);

  SearchSource? searchSource(String type) => _capability<SearchSource>(type);

  PlaylistParsingSource? playlistParsingSource(String type) =>
      _capability<PlaylistParsingSource>(type);

  TrackDetailSource? trackDetailSource(String type) =>
      _capability<TrackDetailSource>(type);

  PagedVideoSource? pagedVideoSource(String type) =>
      _capability<PagedVideoSource>(type);

  DynamicPlaylistSource? dynamicPlaylistSource(String type) =>
      _capability<DynamicPlaylistSource>(type);

  DynamicPlaylistSource? dynamicPlaylistSourceForUrl(String url) {
    for (final source in _sources.whereType<DynamicPlaylistSource>()) {
      if (source.isDynamicPlaylistUrl(url)) return source;
    }
    return null;
  }

  RankingSource? rankingSource(String type) => _capability<RankingSource>(type);

  LiveSource? liveSource(String type) => _capability<LiveSource>(type);

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

  String? sourceTypeForUrl(String url) {
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

  /// 搜索
  Future<Map<String, SearchResult>> searchAll(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final results = <String, SearchResult>{};

    await Future.wait(
      _sources.whereType<SearchSource>().map((source) async {
        try {
          final result = await source.search(
            query,
            page: page,
            pageSize: pageSize,
          );
          results[source.sourceType] = result;
        } catch (e) {
          // 单源失败不应中断整体搜索（保留「部分结果」语义），但补上日志
          // 避免限流/网络/程式错误被完全静默吞掉而无法排查。
          logWarning(
            '${source.sourceType} search failed; returning partial results: '
            '$e',
          );
        }
      }),
    );

    return results;
  }

  /// 从单个源搜索
  Future<SearchResult> searchFrom(
    String type,
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
  ///
  /// 通过 `DisposableSource` 能力介面释放，避免对具体 source 型别做列举；
  /// 新音源只要 `implements DisposableSource` 即自动被释放。
  void dispose() {
    for (final source in _sources.whereType<DisposableSource>()) {
      source.dispose();
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
