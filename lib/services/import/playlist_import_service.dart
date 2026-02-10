import 'dart:async';
import 'dart:math' as math;

import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/playlist_import/playlist_import_source.dart';
import '../../data/sources/playlist_import/netease_playlist_source.dart';
import '../../data/sources/playlist_import/qq_music_playlist_source.dart';
import '../../data/sources/source_provider.dart';

/// 搜索来源配置
enum SearchSourceConfig {
  all('全部'),
  bilibiliOnly('仅 Bilibili'),
  youtubeOnly('仅 YouTube');

  final String displayName;
  const SearchSourceConfig(this.displayName);
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
      .map((t) => t.selectedTrack!)
      .toList();

  /// 获取未匹配的歌曲
  List<ImportedTrack> get unmatchedTracks => matchedTracks
      .where((t) => t.status == MatchStatus.noResult)
      .map((t) => t.original)
      .toList();
}

/// 歌单导入服务
class PlaylistImportService {
  final SourceManager _sourceManager;
  final List<PlaylistImportSource> _importSources;

  final _progressController = StreamController<ImportProgress>.broadcast();
  Stream<ImportProgress> get progressStream => _progressController.stream;

  PlaylistImportService({
    required SourceManager sourceManager,
  }) : _sourceManager = sourceManager,
       _importSources = [
         NeteasePlaylistSource(),
         QQMusicPlaylistSource(),
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
    int maxSearchResults = 10,
  }) async {
    // 1. 获取歌单
    _progressController.add(const ImportProgress(
      phase: ImportPhase.fetching,
      currentItem: '正在获取歌单信息...',
    ));

    final playlist = await _fetchPlaylist(url);

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
    _progressController.add(const ImportProgress(
      phase: ImportPhase.fetching,
      currentItem: '正在获取歌单信息...',
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
    throw Exception('不支持的链接格式');
  }

  Future<List<MatchedTrack>> _matchTracks(
    List<ImportedTrack> tracks, {
    required SearchSourceConfig searchSource,
    required int maxSearchResults,
  }) async {
    final results = <MatchedTrack>[];
    final total = tracks.length;

    for (var i = 0; i < tracks.length; i++) {
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
    final searchPageSize = maxResults * 3;

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

    // 过滤掉负分结果（如超过10分钟的视频）
    final originalTitle = _normalize(track.title);
    final originalArtist = _normalize(track.artists.join(' '));
    final filtered = allResults
        .where((t) => _calculateRelevanceScore(t, originalTitle, originalArtist) >= 0)
        .take(maxResults)
        .toList();

    return filtered;
  }

  /// 按相似度排序搜索结果
  void _sortByRelevance(List<Track> results, ImportedTrack original) {
    if (results.isEmpty) return;

    final originalTitle = _normalize(original.title);
    final originalArtist = _normalize(original.artists.join(' '));

    results.sort((a, b) {
      final scoreA = _calculateRelevanceScore(a, originalTitle, originalArtist);
      final scoreB = _calculateRelevanceScore(b, originalTitle, originalArtist);
      return scoreB.compareTo(scoreA); // 降序
    });
  }

  /// 计算相关性得分（0-100+）
  double _calculateRelevanceScore(
    Track track,
    String originalTitle,
    String originalArtist,
  ) {
    final trackTitle = _normalize(track.title);
    final trackArtist = _normalize(track.artist ?? '');

    // 时长检查：超过 10 分钟的视频大幅减分
    final durationSeconds = (track.durationMs ?? 0) ~/ 1000;
    if (durationSeconds > 600) {
      // 超过 10 分钟，返回负分（会被过滤或排到最后）
      return -100;
    }

    // 标题相似度（权重 35%）
    final titleSimilarity = _calculateSimilarity(originalTitle, trackTitle);

    // 艺术家相似度 - 同时与频道名和视频标题比较，取较高值（权重 30%）
    final artistInChannel = _calculateSimilarity(originalArtist, trackArtist);
    final artistInTitle = _calculateSimilarity(originalArtist, trackTitle);
    final artistSimilarity = math.max(artistInChannel, artistInTitle);

    // 播放量得分（权重 20%）- 对数归一化，提高权重让高播放量更有优势
    final viewScore = _normalizeViewCount(track.viewCount ?? 0);

    // 标题中同时包含歌名和艺术家的额外加分（权重 15%）
    final combinedScore = _calculateCombinedScore(trackTitle, originalTitle, originalArtist);

    // 基础分数
    double score = titleSimilarity * 0.35 +
                   artistSimilarity * 0.30 +
                   viewScore * 0.20 +
                   combinedScore * 0.15;

    // 官方频道加分（最多 +10）
    score += _calculateChannelBonus(track.artist ?? '');

    // 标题关键词加分（最多 +10）
    score += _calculateTitleBonus(track.title);

    return score;
  }

  /// 计算标题中同时包含歌名和艺术家的得分
  double _calculateCombinedScore(
    String trackTitle,
    String originalTitle,
    String originalArtist,
  ) {
    // 检查视频标题是否同时包含原曲名和艺术家名的关键词
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

  /// 计算频道名称加分
  double _calculateChannelBonus(String channelName) {
    final lower = channelName.toLowerCase();
    double bonus = 0;

    // 官方频道关键词
    const officialKeywords = [
      'official',
      'オフィシャル',
      '官方',
      'channel',
      'チャンネル',
      'music',
      'ミュージック',
      'records',
      'レコード',
      'vevo',
      'topic',
    ];

    for (final keyword in officialKeywords) {
      if (lower.contains(keyword)) {
        bonus += 3;
        break; // 只加一次
      }
    }

    // 特殊标识加分
    if (lower.contains('official') || lower.contains('オフィシャル') || lower.contains('官方')) {
      bonus += 5;
    }
    if (lower.contains('vevo')) {
      bonus += 5;
    }

    return bonus.clamp(0, 10);
  }

  /// 计算标题关键词加分
  double _calculateTitleBonus(String title) {
    final lower = title.toLowerCase();
    double bonus = 0;

    // 官方/MV 关键词
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
      'acoustic',
      'アコースティック',
      'piano',
      'ピアノ',
      'instrumental',
      'inst',
      'karaoke',
      'カラオケ',
      '伴奏',
    ];

    for (final keyword in negativeKeywords) {
      if (lower.contains(keyword)) {
        bonus -= 3;
      }
    }

    return bonus.clamp(-10, 10);
  }

  /// 归一化字符串（小写、去除特殊字符）
  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[【】\[\]()（）「」『』\-_·・]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 计算两个字符串的相似度（0-100）
  /// 使用改进的算法：结合包含关系和编辑距离
  double _calculateSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;

    // 检查完全包含关系 - 如果原标题完全包含在搜索结果中，给予高分
    if (b.contains(a)) {
      // 原标题是搜索结果的子串，给予高分（90-100）
      // 搜索结果越短（越精确匹配），分数越高
      final ratio = a.length / b.length;
      return 90 + ratio * 10;
    }
    if (a.contains(b)) {
      final ratio = b.length / a.length;
      return 70 + ratio * 20;
    }

    // 检查关键词匹配
    final wordsA = a.split(' ').where((w) => w.isNotEmpty).toSet();
    final wordsB = b.split(' ').where((w) => w.isNotEmpty).toSet();
    if (wordsA.isNotEmpty && wordsB.isNotEmpty) {
      final intersection = wordsA.intersection(wordsB).length;
      final union = wordsA.union(wordsB).length;
      final jaccardSimilarity = intersection / union * 100;
      if (jaccardSimilarity > 0) {
        return jaccardSimilarity;
      }
    }

    // 使用编辑距离计算相似度
    final distance = _levenshteinDistance(a, b);
    final maxLen = math.max(a.length, b.length);
    return (1 - distance / maxLen) * 100;
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
    int maxResults = 10,
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
