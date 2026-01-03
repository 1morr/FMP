import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import 'base_source.dart';
import 'bilibili_source.dart';

/// 音源管理器
/// 统一管理所有音源，根据URL自动选择正确的音源
class SourceManager {
  final List<BaseSource> _sources = [];

  SourceManager() {
    // 注册所有可用音源
    _sources.add(BilibiliSource());
    // TODO: 添加 YouTube 音源
    // _sources.add(YouTubeSource());
  }

  /// 所有可用音源
  List<BaseSource> get sources => List.unmodifiable(_sources);

  /// 根据类型获取音源
  BaseSource? getSource(SourceType type) {
    try {
      return _sources.firstWhere((s) => s.sourceType == type);
    } catch (_) {
      return null;
    }
  }

  /// 根据 URL 自动选择音源
  BaseSource? getSourceForUrl(String url) {
    for (final source in _sources) {
      if (source.canHandle(url)) {
        return source;
      }
    }
    return null;
  }

  /// 解析 URL 获取歌曲信息
  Future<Track?> parseUrl(String url) async {
    final source = getSourceForUrl(url);
    if (source == null) return null;

    final id = source.parseId(url);
    if (id == null) return null;

    return await source.getTrackInfo(id);
  }

  /// 判断 URL 是否是播放列表
  bool isPlaylistUrl(String url) {
    final source = getSourceForUrl(url);
    return source?.isPlaylistUrl(url) ?? false;
  }

  /// 解析播放列表
  Future<PlaylistParseResult?> parsePlaylist(
    String url, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final source = getSourceForUrl(url);
    if (source == null || !source.isPlaylistUrl(url)) {
      return null;
    }

    return await source.parsePlaylist(url, page: page, pageSize: pageSize);
  }

  /// 刷新歌曲的音频 URL
  Future<Track> refreshAudioUrl(Track track) async {
    final source = getSource(track.sourceType);
    if (source == null) {
      throw Exception('Source not found for ${track.sourceType}');
    }

    return await source.refreshAudioUrl(track);
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

    await Future.wait(_sources.map((source) async {
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
    final source = getSource(type);
    if (source == null) {
      throw Exception('Source not found: $type');
    }

    return await source.search(query, page: page, pageSize: pageSize);
  }
}

// ========== Providers ==========

/// SourceManager Provider
final sourceManagerProvider = Provider<SourceManager>((ref) {
  return SourceManager();
});

/// Bilibili 音源 Provider
final bilibiliSourceProvider = Provider<BilibiliSource>((ref) {
  final manager = ref.watch(sourceManagerProvider);
  return manager.getSource(SourceType.bilibili) as BilibiliSource;
});

/// URL 解析 Provider
final parseUrlProvider =
    FutureProvider.family<Track?, String>((ref, url) async {
  final manager = ref.watch(sourceManagerProvider);
  return await manager.parseUrl(url);
});

/// 播放列表解析 Provider
final parsePlaylistProvider =
    FutureProvider.family<PlaylistParseResult?, String>((ref, url) async {
  final manager = ref.watch(sourceManagerProvider);
  return await manager.parsePlaylist(url);
});
