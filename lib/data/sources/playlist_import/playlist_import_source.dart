import 'package:fmp/i18n/strings.g.dart';

import '../../models/track.dart';

/// 导入的歌曲信息（来自外部平台）
class ImportedTrack {
  final String title;
  final List<String> artists;
  final String? album;
  final Duration? duration;

  /// 原平台歌曲 ID（网易云: song ID, QQ音乐: songmid, Spotify: track ID）
  final String? sourceId;

  /// 来源平台
  final PlaylistSource? source;

  const ImportedTrack({
    required this.title,
    required this.artists,
    this.album,
    this.duration,
    this.sourceId,
    this.source,
  });

  /// 生成搜索查询字符串
  String get searchQuery => '$title ${artists.join(" ")}';

  @override
  String toString() => '$title - ${artists.join(" / ")}';
}

/// 导入的歌单信息
class ImportedPlaylist {
  final String name;
  final String sourceUrl;
  final PlaylistSource source;
  final List<ImportedTrack> tracks;
  final int totalCount;

  const ImportedPlaylist({
    required this.name,
    required this.sourceUrl,
    required this.source,
    required this.tracks,
    required this.totalCount,
  });
}

/// 匹配状态
enum MatchStatus {
  pending,
  searching,
  matched,
  noResult,
  userSelected,
  excluded,
}

/// 匹配结果
class MatchedTrack {
  final ImportedTrack original;
  final List<Track> searchResults;
  final Track? selectedTrack;
  final bool isIncluded;
  final MatchStatus status;

  const MatchedTrack({
    required this.original,
    this.searchResults = const [],
    this.selectedTrack,
    this.isIncluded = true,
    this.status = MatchStatus.pending,
  });

  MatchedTrack copyWith({
    ImportedTrack? original,
    List<Track>? searchResults,
    Track? selectedTrack,
    bool? isIncluded,
    MatchStatus? status,
  }) {
    return MatchedTrack(
      original: original ?? this.original,
      searchResults: searchResults ?? this.searchResults,
      selectedTrack: selectedTrack ?? this.selectedTrack,
      isIncluded: isIncluded ?? this.isIncluded,
      status: status ?? this.status,
    );
  }
}

/// 歌单来源平台
enum PlaylistSource {
  netease,
  qqMusic,
  spotify;

  String get displayName {
    switch (this) {
      case PlaylistSource.netease: return t.importPlatform.neteaseMusic;
      case PlaylistSource.qqMusic: return t.importPlatform.qqMusic;
      case PlaylistSource.spotify: return t.importPlatform.spotify;
    }
  }
}

/// 歌单导入源抽象接口
abstract class PlaylistImportSource {
  /// 支持的平台
  PlaylistSource get source;

  /// 检查链接是否匹配此平台
  bool canHandle(String url);

  /// 从链接解析歌单ID
  String? extractPlaylistId(String url);

  /// 获取歌单信息
  Future<ImportedPlaylist> fetchPlaylist(String url);
}
