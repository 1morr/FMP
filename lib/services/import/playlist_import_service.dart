import 'dart:async';
import 'dart:math' as math;

import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/playlist_import/playlist_import_source.dart';
import '../../data/sources/playlist_import/netease_playlist_source.dart';
import '../../data/sources/playlist_import/qq_music_playlist_source.dart';
import '../../data/sources/playlist_import/spotify_playlist_source.dart';
import '../../data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 搜索来源配置
enum SearchSourceConfig {
  all,
  bilibiliOnly,
  youtubeOnly;

  String get displayName {
    switch (this) {
      case SearchSourceConfig.all: return t.searchPage.all;
      case SearchSourceConfig.bilibiliOnly: return t.searchPage.bilibiliOnly;
      case SearchSourceConfig.youtubeOnly: return t.searchPage.youtubeOnly;
    }
  }
}


/// 导入进度
class ImportProgress {
  final int current;
  final int total;
  final String? currentItem;
  final ImportPhase phase;

  const ImportProgress({
    this.current = 0,
    this.total = 0,
    this.currentItem,
    this.phase = ImportPhase.idle,
  });

  double get percentage => total > 0 ? current / total : 0;
}

enum ImportPhase {
  idle,
  fetching,    // 获取歌单
  matching,    // 搜索匹配
  completed,
  error,
}

/// 导入结果
class PlaylistImportResult {
  final ImportedPlaylist playlist;
  final List<MatchedTrack> matchedTracks;
  final int matchedCount;
  final int unmatchedCount;

  PlaylistImportResult({
    required this.playlist,
    required this.matchedTracks,
  }) : matchedCount = matchedTracks.where((t) => t.status == MatchStatus.matched).length,
       unmatchedCount = matchedTracks.where((t) => t.status == MatchStatus.noResult).length;

  /// 获取已匹配的歌曲（用于创建歌单）
  List<Track> get selectedTracks => matchedTracks
      .where((t) => t.isIncluded && t.selectedTrack != null)
      .map((t) {
        final track = t.selectedTrack!;
        if (t.original.sourceId != null) {
          track.originalSongId = t.original.sourceId;
          track.originalSource = _mapSourceToString(t.original.source);
        }
        return track;
      })
      .toList();

  /// 获取未匹配的歌曲
  List<ImportedTrack> get unmatchedTracks => matchedTracks
      .where((t) => t.status == MatchStatus.noResult)
      .map((t) => t.original)
      .toList();

  /// PlaylistSource → 歌词系统兼容的字符串
  static String? _mapSourceToString(PlaylistSource? source) {
    switch (source) {
      case PlaylistSource.netease:
        return 'netease';
      case PlaylistSource.qqMusic:
        return 'qqmusic';
      case PlaylistSource.spotify:
        return 'spotify';
      case null:
        return null;
    }
  }
}

/// 歌单导入服务
/// 导入被用户取消
class ImportCancelledException implements Exception {
  @override
  String toString() => t.importSource.cancelled;
}

class PlaylistImportService {
  final SourceManager _sourceManager;
  final List<PlaylistImportSource> _importSources;

  final _progressController = StreamController<ImportProgress>.broadcast();
  Stream<ImportProgress> get progressStream => _progressController.stream;

  /// 取消标记
  bool _isCancelled = false;

  /// 取消当前导入
  void cancelImport() {
    _isCancelled = true;
  }

  PlaylistImportService({
    required SourceManager sourceManager,
  }) : _sourceManager = sourceManager,
       _importSources = [
         NeteasePlaylistSource(),
         QQMusicPlaylistSource(),
         SpotifyPlaylistSource(),
       ];

  /// 检测链接对应的平台
  PlaylistSource? detectSource(String url) {
    for (final source in _importSources) {
      if (source.canHandle(url)) {
        return source.source;
      }
    }
    return null;
  }

  /// 从URL导入歌单并匹配
  Future<PlaylistImportResult> importAndMatch(
    String url, {
    SearchSourceConfig searchSource = SearchSourceConfig.all,
    int maxSearchResults = 5,
  }) async {
    _isCancelled = false;

    // 1. 获取歌单
    _progressController.add(ImportProgress(
      phase: ImportPhase.fetching,
      currentItem: t.importSource.fetchingPlaylistInfo,
    ));

    final playlist = await _fetchPlaylist(url);

    if (_isCancelled) throw ImportCancelledException();

    // 2. 搜索匹配
    final matchedTracks = await _matchTracks(
      playlist.tracks,
      searchSource: searchSource,
      maxSearchResults: maxSearchResults,
    );

    _progressController.add(ImportProgress(
      phase: ImportPhase.completed,
      current: playlist.tracks.length,
      total: playlist.tracks.length,
    ));

    return PlaylistImportResult(
      playlist: playlist,
      matchedTracks: matchedTracks,
    );
  }

  /// 仅获取歌单（不匹配）
  Future<ImportedPlaylist> fetchPlaylist(String url) async {
    _progressController.add(ImportProgress(
      phase: ImportPhase.fetching,
      currentItem: t.importSource.fetchingPlaylistInfo,
    ));

    final playlist = await _fetchPlaylist(url);

    _progressController.add(ImportProgress(
      phase: ImportPhase.completed,
      current: playlist.tracks.length,
      total: playlist.tracks.length,
    ));

    return playlist;
  }

  Future<ImportedPlaylist> _fetchPlaylist(String url) async {
    for (final source in _importSources) {
      if (source.canHandle(url)) {
        return await source.fetchPlaylist(url);
      }
    }
    throw Exception(t.importSource.unsupportedLinkFormat);
  }

  Future<List<MatchedTrack>> _matchTracks(
    List<ImportedTrack> tracks, {
    required SearchSourceConfig searchSource,
    required int maxSearchResults,
  }) async {
    final results = <MatchedTrack>[];
    final total = tracks.length;

    for (var i = 0; i < tracks.length; i++) {
      if (_isCancelled) throw ImportCancelledException();

      final track = tracks[i];

      _progressController.add(ImportProgress(
        phase: ImportPhase.matching,
        current: i + 1,
        total: total,
        currentItem: track.toString(),
      ));

      try {
        final searchResults = await _searchTrack(
          track,
          searchSource: searchSource,
          maxResults: maxSearchResults,
        );

        if (searchResults.isNotEmpty) {
          results.add(MatchedTrack(
            original: track,
            searchResults: searchResults,
            selectedTrack: searchResults.first,
            status: MatchStatus.matched,
          ));
        } else {
          results.add(MatchedTrack(
            original: track,
            status: MatchStatus.noResult,
          ));
        }
      } catch (e) {
        results.add(MatchedTrack(
          original: track,
          status: MatchStatus.noResult,
        ));
      }

      // 添加延迟避免请求过快触发限流
      // Bilibili 对请求频率限制较严格，需要较长间隔
      if (i < tracks.length - 1) {
        final delay = switch (searchSource) {
          SearchSourceConfig.all => 1000,        // 搜索两个源，需要更长间隔
          SearchSourceConfig.bilibiliOnly => 800,  // Bilibili 限制较严
          SearchSourceConfig.youtubeOnly => 800,   // YouTube 相对宽松
        };
        await Future.delayed(Duration(milliseconds: delay));
      }
    }

    return results;
  }

  Future<List<Track>> _searchTrack(
    ImportedTrack track, {
    required SearchSourceConfig searchSource,
    required int maxResults,
  }) async {
    final query = track.searchQuery;
    final allResults = <Track>[];
    // 搜索时获取更多结果，排序后再截取
    final searchPageSize = maxResults * 8;

    switch (searchSource) {
      case SearchSourceConfig.all:
        // 并行搜索 YouTube 和 Bilibili
        final results = await Future.wait([
          _sourceManager
              .searchFrom(SourceType.youtube, query, pageSize: searchPageSize)
              .catchError((_) => SearchResult.empty()),
          _sourceManager
              .searchFrom(SourceType.bilibili, query, pageSize: searchPageSize)
              .catchError((_) => SearchResult.empty()),
        ]);

        for (final result in results) {
          allResults.addAll(result.tracks);
        }

        // 按相似度排序（综合标题、艺术家相似度和播放量）
        _sortByRelevance(allResults, track);
        break;

      case SearchSourceConfig.bilibiliOnly:
        final result = await _sourceManager.searchFrom(
          SourceType.bilibili,
          query,
          pageSize: searchPageSize,
        );
        allResults.addAll(result.tracks);
        _sortByRelevance(allResults, track);
        break;

      case SearchSourceConfig.youtubeOnly:
        final result = await _sourceManager.searchFrom(
          SourceType.youtube,
          query,
          pageSize: searchPageSize,
        );
        allResults.addAll(result.tracks);
        _sortByRelevance(allResults, track);
        break;
    }

    // 过滤掉负分结果（如超过15分钟的视频）
    final originalTitle = _normalize(track.title);
    final originalArtist = _normalize(track.artists.join(' '));
    final originalDuration = track.duration;
    final filtered = allResults
        .where((t) => _calculateRelevanceScore(
              t, originalTitle, originalArtist,
              originalDuration: originalDuration,
            ) >= 0)
        .take(maxResults)
        .toList();

    return filtered;
  }

  /// 按相似度排序搜索结果
  void _sortByRelevance(List<Track> results, ImportedTrack original) {
    if (results.isEmpty) return;

    final originalTitle = _normalize(original.title);
    final originalArtist = _normalize(original.artists.join(' '));
    final originalDuration = original.duration;

    // 计算所有结果的播放量，用于差异加权
    final maxViewCount = results
        .map((t) => t.viewCount ?? 0)
        .reduce((a, b) => a > b ? a : b);

    results.sort((a, b) {
      var scoreA = _calculateRelevanceScore(
        a, originalTitle, originalArtist,
        originalDuration: originalDuration,
      );
      var scoreB = _calculateRelevanceScore(
        b, originalTitle, originalArtist,
        originalDuration: originalDuration,
      );

      // 播放量差异加权：如果播放量差距超过 100 倍，给高播放量额外加分
      final viewA = a.viewCount ?? 0;
      final viewB = b.viewCount ?? 0;

      if (maxViewCount > 0) {
        // 播放量占最高播放量的比例加分（最多 +8，降低权重）
        scoreA += (viewA / maxViewCount) * 8;
        scoreB += (viewB / maxViewCount) * 8;

        // 如果播放量差距超过 100 倍，额外加分（降低加分幅度）
        if (viewA > 0 && viewB > 0) {
          if (viewA > viewB * 100) {
            scoreA += 10;
          } else if (viewB > viewA * 100) {
            scoreB += 10;
          } else if (viewA > viewB * 10) {
            scoreA += 4;
          } else if (viewB > viewA * 10) {
            scoreB += 4;
          }
        }
      }

      return scoreB.compareTo(scoreA); // 降序
    });
  }

  /// 计算相关性得分（0-100+）
  ///
  /// 评分组成：
  /// - 标题相似度 × 0.35 (35%)
  /// - 艺术家相似度 × 0.25 (25%) - 对标题中的艺术家匹配设置更高阈值
  /// - 播放量得分 × 0.15 (15%)
  /// - 组合匹配得分 × 0.15 (15%)
  /// - 精确匹配加分 (+0~25)
  /// - 频道-艺术家匹配加分 (+0~15)
  /// - 官方频道加分 (+0~15)
  /// - 标题关键词加分 (-15~+10)
  /// - 时长匹配加分 (-100~+20) - 绝对值+百分比结合
  /// - 版本匹配加分 (-5~+10)
  /// - 括号内容匹配加分 (+0~15)
  double _calculateRelevanceScore(
    Track track,
    String originalTitle,
    String originalArtist, {
    Duration? originalDuration,
  }) {
    final trackTitle = _normalize(track.title);
    final trackArtist = _normalize(track.artist ?? '');
    final durationSeconds = (track.durationMs ?? 0) ~/ 1000;

    // 时长匹配检查（与原曲时长对比）- 提前过滤
    if (originalDuration != null && originalDuration.inSeconds > 0) {
      final durationScore = _calculateDurationMatchScore(durationSeconds, originalDuration.inSeconds);
      if (durationScore < -50) {
        // 时长差异过大，直接过滤
        return -100;
      }
    }

    // 标题相似度（权重 35%）- 提高权重
    // 同时尝试括号内容匹配，取较高分
    final directTitleSimilarity = _calculateSimilarity(originalTitle, trackTitle);
    final bracketTitleSimilarity = _calculateBracketContentSimilarity(
      track.title, originalTitle,
    );
    final titleSimilarity = math.max(directTitleSimilarity, bracketTitleSimilarity);

    // 艺术家相似度（权重 25%）- 改进：对标题中的艺术家匹配设置更高阈值
    final artistInChannel = _calculateSimilarity(originalArtist, trackArtist);
    final artistInTitle = _calculateSimilarity(originalArtist, trackTitle);
    // 频道名匹配优先；标题中的艺术家匹配需要更高阈值（>70）才采用，且打折
    final artistSimilarity = artistInChannel > 50
        ? artistInChannel
        : (artistInTitle > 70 ? artistInTitle * 0.8 : artistInChannel);

    // 播放量得分（权重 15%）
    final viewScore = _normalizeViewCount(track.viewCount ?? 0);

    // 标题中同时包含歌名和艺术家的额外加分（权重 15%）
    final combinedScore = _calculateCombinedScore(trackTitle, originalTitle, originalArtist);

    // 基础分数
    double score = titleSimilarity * 0.35 +
                   artistSimilarity * 0.25 +
                   viewScore * 0.15 +
                   combinedScore * 0.15;

    // 精确匹配加分（最多 +25）
    score += _calculateExactMatchBonus(trackTitle, originalTitle);

    // 频道名与艺术家匹配加分（最多 +15）
    score += _calculateArtistChannelBonus(trackArtist, originalArtist);

    // 官方频道加分（最多 +15）
    score += _calculateChannelBonus(track.artist ?? '');

    // 标题关键词加分（-15~+10）
    score += _calculateTitleBonus(track.title);

    // 时长匹配加分/减分 - 绝对值+百分比结合
    if (originalDuration != null && originalDuration.inSeconds > 0) {
      score += _calculateDurationMatchScore(durationSeconds, originalDuration.inSeconds);
    }

    // 版本匹配加分（-5~+10）
    score += _calculateVersionMatchBonus(track.title, originalTitle);

    // 括号内容精确匹配加分（+0~15）
    if (bracketTitleSimilarity > directTitleSimilarity && bracketTitleSimilarity > 80) {
      score += 15; // 括号内歌名精确匹配，强烈暗示是目标歌曲
    }

    return score;
  }

  /// 计算精确匹配加分（最多 +25）
  double _calculateExactMatchBonus(String trackTitle, String originalTitle) {
    // 完全匹配（归一化后）
    if (trackTitle == originalTitle) return 25;

    // 标题以原标题开头（如 "歌名 - Official MV"）
    if (trackTitle.startsWith(originalTitle)) {
      // 根据额外内容长度调整加分
      final extraLength = trackTitle.length - originalTitle.length;
      if (extraLength < 20) return 20;
      if (extraLength < 40) return 15;
      return 10;
    }

    // 原标题以搜索结果开头（搜索结果是原标题的缩写）
    if (originalTitle.startsWith(trackTitle) && trackTitle.length > 3) {
      final ratio = trackTitle.length / originalTitle.length;
      return ratio * 15; // 最多 +15
    }

    return 0;
  }

  /// 计算版本匹配加分（-5~+10）
  double _calculateVersionMatchBonus(String trackTitle, String originalTitle) {
    final trackLower = trackTitle.toLowerCase();
    final originalLower = originalTitle.toLowerCase();

    // 版本关键词
    const versionKeywords = [
      'remaster', 'remastered',
      'deluxe',
      'anniversary',
      'edition',
      'version',
      '2024', '2023', '2022', '2021', '2020',
      'bonus',
      'extended',
    ];

    final trackVersions = <String>[];
    final originalVersions = <String>[];

    for (final keyword in versionKeywords) {
      if (trackLower.contains(keyword)) trackVersions.add(keyword);
      if (originalLower.contains(keyword)) originalVersions.add(keyword);
    }

    // 如果原曲指定了版本
    if (originalVersions.isNotEmpty) {
      // 检查是否有相同版本关键词
      final matchedVersions = trackVersions.where((v) => originalVersions.contains(v)).length;
      if (matchedVersions > 0) {
        return 10; // 版本匹配，加分
      } else if (trackVersions.isNotEmpty) {
        return -5; // 都有版本但不匹配，减分
      }
      // 原曲有版本但搜索结果没有，不加不减
      return 0;
    }

    // 原曲没有指定版本，但搜索结果有版本标记
    if (trackVersions.isNotEmpty) {
      // 轻微减分，优先选择无版本标记的（更可能是原版）
      return -2;
    }

    return 0;
  }

  /// 计算时长匹配得分（与原曲时长对比）- 改进版
  /// 
  /// 使用绝对值和百分比结合的方式：
  /// - 短歌曲（<3分钟）：允许更大的绝对误差
  /// - 长歌曲（>5分钟）：主要看百分比
  double _calculateDurationMatchScore(int trackDuration, int originalDuration) {
    if (trackDuration <= 0 || originalDuration <= 0) return 0;

    final diff = (trackDuration - originalDuration).abs();
    final diffPercent = diff / originalDuration * 100;

    // 绝对值优先判断（解决短歌曲百分比过于严格的问题）
    // 允许至少 10 秒的绝对误差
    if (diff <= 10) {
      return 20; // 差异 ≤10秒，非常匹配
    }

    // 对于短歌曲（<3分钟），放宽绝对值要求
    if (originalDuration < 180) {
      if (diff <= 15) return 18;
      if (diff <= 20) return 15;
      if (diff <= 30) return 10;
    }

    // 百分比判断
    if (diffPercent <= 5) {
      return 18; // 差异 ≤5%
    } else if (diffPercent <= 10) {
      return 15; // 差异 ≤10%
    } else if (diffPercent <= 15) {
      return 12; // 差异 ≤15%
    } else if (diffPercent <= 20) {
      return 8; // 差异 ≤20%
    } else if (diffPercent <= 30) {
      return 4; // 差异 ≤30%
    } else if (diffPercent <= 50) {
      return 0; // 差异 ≤50%，不加不减
    } else if (diffPercent <= 80) {
      return -10; // 差异 50-80%，轻微减分
    } else if (diffPercent <= 100) {
      return -20; // 差异 80-100%，减分
    } else if (diffPercent <= 200) {
      return -35; // 差异 100-200%，大幅减分
    } else {
      return -100; // 差异 >200%，直接过滤（如合集、串烧）
    }
  }

  /// A. 计算频道名与艺术家匹配加分
  double _calculateArtistChannelBonus(String channelName, String originalArtist) {
    if (channelName.isEmpty || originalArtist.isEmpty) return 0;

    // 使用 N-gram 相似度检查频道名是否包含艺术家名
    final similarity = _calculateNGramSimilarity(originalArtist, channelName);

    // 如果频道名包含艺术家名（子串匹配）
    if (channelName.contains(originalArtist) || originalArtist.contains(channelName)) {
      return 15; // 最高加分
    }

    // 基于 N-gram 相似度加分
    if (similarity > 70) return 12;
    if (similarity > 50) return 8;
    if (similarity > 30) return 4;

    return 0;
  }

  /// 计算标题中同时包含歌名和艺术家的得分
  double _calculateCombinedScore(
    String trackTitle,
    String originalTitle,
    String originalArtist,
  ) {
    // 检查视频标题是否同时包含原曲名和艺术家名的关键词
    // 对 CJK 语言：直接检查子串包含关系（不依赖空格分词）
    final hasCJK = RegExp(r'[\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff\uac00-\ud7af]')
        .hasMatch(originalTitle + originalArtist);

    if (hasCJK) {
      // CJK 模式：直接检查子串
      final titleFound = originalTitle.length > 1 && trackTitle.contains(originalTitle);
      final artistFound = originalArtist.length > 1 && trackTitle.contains(originalArtist);

      if (titleFound && artistFound) {
        return 100; // 标题和艺术家都完整出现在视频标题中
      }
      if (titleFound) {
        return 50; // 只有标题出现
      }
      if (artistFound) {
        return 30; // 只有艺术家出现
      }

      // 对于 CJK，尝试部分匹配（至少2个字符的子串）
      int titleCharMatches = 0;
      if (originalTitle.length >= 2) {
        for (var i = 0; i <= originalTitle.length - 2; i++) {
          if (trackTitle.contains(originalTitle.substring(i, i + 2))) {
            titleCharMatches++;
          }
        }
      }
      int artistCharMatches = 0;
      if (originalArtist.length >= 2) {
        for (var i = 0; i <= originalArtist.length - 2; i++) {
          if (trackTitle.contains(originalArtist.substring(i, i + 2))) {
            artistCharMatches++;
          }
        }
      }

      final titleBigrams = originalTitle.length >= 2 ? originalTitle.length - 1 : 1;
      final artistBigrams = originalArtist.length >= 2 ? originalArtist.length - 1 : 1;

      if (titleCharMatches > 0 && artistCharMatches > 0) {
        final titleRatio = titleCharMatches / titleBigrams;
        final artistRatio = artistCharMatches / artistBigrams;
        return (titleRatio + artistRatio) / 2 * 100;
      }

      return 0;
    }

    // 非 CJK 模式：基于空格分词的关键词匹配
    final titleWords = originalTitle.split(' ').where((w) => w.length > 1).toSet();
    final artistWords = originalArtist.split(' ').where((w) => w.length > 1).toSet();

    int titleMatches = 0;
    int artistMatches = 0;

    for (final word in titleWords) {
      if (trackTitle.contains(word)) titleMatches++;
    }
    for (final word in artistWords) {
      if (trackTitle.contains(word)) artistMatches++;
    }

    // 如果标题和艺术家都有匹配，给予高分
    if (titleMatches > 0 && artistMatches > 0) {
      final titleRatio = titleWords.isNotEmpty ? titleMatches / titleWords.length : 0;
      final artistRatio = artistWords.isNotEmpty ? artistMatches / artistWords.length : 0;
      return (titleRatio + artistRatio) / 2 * 100;
    }

    return 0;
  }

  /// 计算频道名称加分（最多 +15）- 增强版
  double _calculateChannelBonus(String channelName) {
    final lower = channelName.toLowerCase();
    double bonus = 0;

    // 高权重官方标识（+8）
    const highPriorityKeywords = [
      'vevo',           // YouTube 官方音乐合作伙伴
      'official',       // 官方
      'オフィシャル',    // 日文官方
      '官方',           // 中文官方
    ];

    for (final keyword in highPriorityKeywords) {
      if (lower.contains(keyword)) {
        bonus += 8;
        break; // 只加一次最高分
      }
    }

    // 中权重音乐相关标识（+4）
    const mediumPriorityKeywords = [
      'music',          // 音乐
      'ミュージック',    // 日文音乐
      'records',        // 唱片公司
      'レコード',       // 日文唱片
      'entertainment',  // 娱乐公司
      'エンタテインメント',
      'label',          // 厂牌
      'レーベル',
    ];

    for (final keyword in mediumPriorityKeywords) {
      if (lower.contains(keyword)) {
        bonus += 4;
        break;
      }
    }

    // YouTube Topic 频道（自动生成的艺术家频道）（+5）
    if (lower.contains(' - topic') || lower.endsWith(' topic')) {
      bonus += 5;
    }

    // 知名唱片公司/厂牌名称（+3）
    const majorLabels = [
      'sony', 'universal', 'warner', 'emi', 'bmg',
      'avex', 'エイベックス',
      'jvckenwood', 'ビクター',
      'king records', 'キングレコード',
      'columbia', 'コロムビア',
      'pony canyon', 'ポニーキャニオン',
      'lantis', 'ランティス',
      'aniplex', 'アニプレックス',
      'sacra music',
      'being',
      'sm entertainment', 'jyp', 'yg entertainment', 'hybe', 'bighit',
    ];

    for (final label in majorLabels) {
      if (lower.contains(label)) {
        bonus += 3;
        break;
      }
    }

    return bonus.clamp(0, 15);
  }

  /// 计算标题关键词加分
  double _calculateTitleBonus(String title) {
    final lower = title.toLowerCase();
    double bonus = 0;

    // 官方/MV 关键词（正面）
    const positiveKeywords = [
      'official',
      'オフィシャル',
      '官方',
      'mv',
      'music video',
      'ミュージックビデオ',
      'pv',
      'full',
      'フル',
      '完整版',
      'original',
      'オリジナル',
      'hi-res',
      '无损',
      'flac',
      '純享',
      '纯享',
    ];

    for (final keyword in positiveKeywords) {
      if (lower.contains(keyword)) {
        bonus += 2;
      }
    }

    // 负面关键词减分（cover、翻唱等）
    const negativeKeywords = [
      'cover',
      'カバー',
      '翻唱',
      'remix',
      'リミックス',
      'live',
      'ライブ',
      '现场',
      '演唱会',
      '演唱會',
      'acoustic',
      'アコースティック',
      'piano',
      'ピアノ',
      'instrumental',
      'inst',
      'karaoke',
      'カラオケ',
      '伴奏',
      '歌ってみた',    // 日文"试着唱了"（翻唱）
      'covered by',
      'bass',
      'ベース',
      'guitar',
      'ギター',
      '吉他',
      '弹唱',
      '彈唱',
    ];

    for (final keyword in negativeKeywords) {
      if (lower.contains(keyword)) {
        bonus -= 3;
      }
    }

    // 强负面关键词（合集、串烧、循环等 - 几乎不可能是目标歌曲）
    const strongNegativeKeywords = [
      '合集',
      '串烧',
      '串燒',
      'medley',
      'メドレー',
      '循环',
      '循環',
      'loop',
      '盘点',
      '盤點',
      '精选',
      '精選',
      '歌曲合集',
      '音乐合集',
      '經典',
      '经典',
      '废话版',
      'bgm',
      '作业用',
      '作業用',
      '勉強用',
    ];

    for (final keyword in strongNegativeKeywords) {
      if (lower.contains(keyword)) {
        bonus -= 8;
      }
    }

    // 歌词视频（中性偏正面 - 通常是正确的歌曲，只是带歌词）
    const lyricsKeywords = [
      '歌词',
      '歌詞',
      'lyrics',
      '動態歌詞',
      '动态歌词',
      'lyric video',
    ];

    for (final keyword in lyricsKeywords) {
      if (lower.contains(keyword)) {
        bonus += 1;
        break; // 歌词类只加一次
      }
    }

    return bonus.clamp(-15, 10);
  }

  /// 归一化字符串（小写、去除特殊字符和装饰符号）
  String _normalize(String text) {
    return text
        .toLowerCase()
        // 移除各种括号、分隔符、装饰符号
        .replaceAll(RegExp(r'[【】\[\]()（）「」『』《》〈〉\-_·・｜丨／/\\——\u2014\u2013~～＊✦❖▶►▻➸]'), ' ')
        .replaceAll(RegExp(r'[#＃]'), ' ')  // 移除 hashtag
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 从标题中提取括号内的内容，与原标题进行匹配
  ///
  /// 许多视频标题格式为：
  /// - YOASOBI「夜に駆ける」Official Music Video
  /// - 【4K修复】周杰伦 - 晴天MV
  /// - 【杜比音效】周杰伦《晴天》4K
  /// - (楽譜あり) YOASOBI「夜に駆ける」- Piano Cover
  ///
  /// 提取括号内的歌名与原标题比较，可以获得更精确的匹配
  double _calculateBracketContentSimilarity(String rawTitle, String originalTitle) {
    // 提取各种括号内的内容
    final bracketPatterns = [
      RegExp(r'「([^」]+)」'),   // 日文括号 「」
      RegExp(r'《([^》]+)》'),   // 中文书名号 《》
      RegExp(r'『([^』]+)』'),   // 日文双括号 『』
      RegExp(r'【([^】]+)】'),   // 中文方括号 【】
      RegExp(r'〈([^〉]+)〉'),   // 中文尖括号 〈〉
    ];

    double bestSimilarity = 0;

    for (final pattern in bracketPatterns) {
      final matches = pattern.allMatches(rawTitle);
      for (final match in matches) {
        final content = _normalize(match.group(1) ?? '');
        if (content.isEmpty || content.length < 2) continue;

        final similarity = _calculateSimilarity(originalTitle, content);
        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
        }
      }
    }

    return bestSimilarity;
  }

  /// 计算两个字符串的相似度（0-100）
  /// 使用改进的算法：结合包含关系、N-gram 和编辑距离
  double _calculateSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;

    // B. 增强子串匹配 - 检查完全包含关系
    if (b.contains(a)) {
      // 原标题是搜索结果的子串，给予高分（90-100）
      final ratio = a.length / b.length;
      return 90 + ratio * 10;
    }
    if (a.contains(b)) {
      final ratio = b.length / a.length;
      return 70 + ratio * 20;
    }

    // D. 使用 N-gram 相似度（对日文/中文更有效）
    final ngramSimilarity = _calculateNGramSimilarity(a, b);
    if (ngramSimilarity > 50) {
      return ngramSimilarity;
    }

    // 检查关键词匹配（对有空格的语言）
    final wordsA = a.split(' ').where((w) => w.isNotEmpty).toSet();
    final wordsB = b.split(' ').where((w) => w.isNotEmpty).toSet();
    if (wordsA.length > 1 && wordsB.length > 1) {
      final intersection = wordsA.intersection(wordsB).length;
      final union = wordsA.union(wordsB).length;
      final jaccardSimilarity = intersection / union * 100;
      if (jaccardSimilarity > ngramSimilarity) {
        return jaccardSimilarity;
      }
    }

    // 返回 N-gram 相似度或编辑距离中较高的
    final distance = _levenshteinDistance(a, b);
    final maxLen = math.max(a.length, b.length);
    final editSimilarity = (1 - distance / maxLen) * 100;

    return math.max(ngramSimilarity, editSimilarity);
  }

  /// D. 计算 N-gram 相似度（字符级，适用于日文/中文）
  double _calculateNGramSimilarity(String a, String b, {int n = 2}) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;

    final ngramsA = _generateNGrams(a, n);
    final ngramsB = _generateNGrams(b, n);

    if (ngramsA.isEmpty || ngramsB.isEmpty) return 0;

    final intersection = ngramsA.intersection(ngramsB).length;
    final union = ngramsA.union(ngramsB).length;

    if (union == 0) return 0;
    return (intersection / union) * 100;
  }

  /// 生成字符级 N-gram
  Set<String> _generateNGrams(String text, int n) {
    final ngrams = <String>{};
    if (text.length < n) {
      ngrams.add(text);
      return ngrams;
    }
    for (var i = 0; i <= text.length - n; i++) {
      ngrams.add(text.substring(i, i + n));
    }
    return ngrams;
  }

  /// Levenshtein 编辑距离
  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );

    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce(math.min);
      }
    }

    return matrix[a.length][b.length];
  }

  /// 归一化播放量（对数缩放到 0-100）
  double _normalizeViewCount(int viewCount) {
    if (viewCount <= 0) return 0;
    // 使用对数缩放，假设 1亿播放量为满分
    final logView = math.log(viewCount + 1);
    final logMax = math.log(100000000 + 1); // 1亿
    return (logView / logMax * 100).clamp(0, 100);
  }

  /// 手动搜索单首歌曲
  Future<List<Track>> searchForTrack(
    String query, {
    SearchSourceConfig searchSource = SearchSourceConfig.all,
    int maxResults = 5,
  }) async {
    final allResults = <Track>[];

    switch (searchSource) {
      case SearchSourceConfig.all:
        final results = await _sourceManager.searchAll(query, pageSize: maxResults);
        for (final result in results.values) {
          allResults.addAll(result.tracks);
        }
        allResults.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
        break;

      case SearchSourceConfig.bilibiliOnly:
        final result = await _sourceManager.searchFrom(
          SourceType.bilibili,
          query,
          pageSize: maxResults,
        );
        allResults.addAll(result.tracks);
        break;

      case SearchSourceConfig.youtubeOnly:
        final result = await _sourceManager.searchFrom(
          SourceType.youtube,
          query,
          pageSize: maxResults,
        );
        allResults.addAll(result.tracks);
        break;
    }

    return allResults.take(maxResults).toList();
  }

  void dispose() {
    _progressController.close();
  }
}
