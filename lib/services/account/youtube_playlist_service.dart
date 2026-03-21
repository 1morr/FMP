import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/innertube_utils.dart';
import '../../i18n/strings.g.dart';
import 'youtube_account_service.dart';
import 'youtube_auth_interceptor.dart';

/// YouTube 播放列表數據模型
class YouTubePlaylistInfo {
  final String playlistId;
  final String title;
  final int videoCount;
  final String? thumbnailUrl;
  final bool containsVideo; // 單曲模式用

  const YouTubePlaylistInfo({
    required this.playlistId,
    required this.title,
    required this.videoCount,
    this.thumbnailUrl,
    this.containsVideo = false,
  });

  YouTubePlaylistInfo copyWith({bool? containsVideo}) {
    return YouTubePlaylistInfo(
      playlistId: playlistId,
      title: title,
      videoCount: videoCount,
      thumbnailUrl: thumbnailUrl,
      containsVideo: containsVideo ?? this.containsVideo,
    );
  }
}

/// YouTube 播放列表操作服務
class YouTubePlaylistService with Logging {
  final YouTubeAccountService _accountService;
  final Dio _dio;

  YouTubePlaylistService({
    required YouTubeAccountService accountService,
  })  : _accountService = accountService,
        _dio = _createDio(accountService);

  static Dio _createDio(YouTubeAccountService accountService) {
    final dio = Dio(BaseOptions(
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
    dio.interceptors.add(YouTubeAuthInterceptor(accountService));
    return dio;
  }

  String get _apiBase => _accountService.innerTubeApiBase;
  String get _apiKey => _accountService.innerTubeApiKey;

  /// 獲取用戶播放列表列表
  Future<List<YouTubePlaylistInfo>> getPlaylists() async {
    final response = await _dio.post(
      '$_apiBase/browse?key=$_apiKey',
      data: jsonEncode({
        'browseId': 'FEplaylist_aggregation',
        'context': _accountService.buildInnerTubeContext(),
      }),
    );

    final data = response.data;
    return _parsePlaylistsFromBrowse(data);
  }

  /// 檢查視頻是否在播放列表中
  Future<bool> checkVideoInPlaylist(String playlistId, String videoId) async {
    try {
      final setVideoId = await getSetVideoId(playlistId, videoId);
      return setVideoId != null;
    } catch (e) {
      logWarning('Failed to check video in playlist: $e');
      return false;
    }
  }

  /// 添加視頻到播放列表
  Future<void> addToPlaylist(String playlistId, String videoId) async {
    final response = await _dio.post(
      '$_apiBase/browse/edit_playlist?key=$_apiKey',
      data: jsonEncode({
        'playlistId': playlistId,
        'actions': [
          {
            'addedVideoId': videoId,
            'action': 'ACTION_ADD_VIDEO',
          },
        ],
        'context': _accountService.buildInnerTubeContext(),
      }),
    );

    _checkResponse(response.data);
    logInfo('Added video $videoId to playlist $playlistId');
  }

  /// 從播放列表移除視頻
  Future<void> removeFromPlaylist(
    String playlistId,
    String videoId,
    String setVideoId,
  ) async {
    final response = await _dio.post(
      '$_apiBase/browse/edit_playlist?key=$_apiKey',
      data: jsonEncode({
        'playlistId': playlistId,
        'actions': [
          {
            'setVideoId': setVideoId,
            'removedVideoId': videoId,
            'action': 'ACTION_REMOVE_VIDEO',
          },
        ],
        'context': _accountService.buildInnerTubeContext(),
      }),
    );

    _checkResponse(response.data);
    logInfo('Removed video $videoId from playlist $playlistId');
  }

  /// 獲取移除所需的 setVideoId
  ///
  /// 需要瀏覽播放列表內容找到對應的 setVideoId
  Future<String?> getSetVideoId(String playlistId, String videoId) async {
    return _browsePlaylistPages(playlistId, (data) {
      final contents = _getPlaylistVideoContents(data);
      if (contents == null) return null;
      for (final item in contents) {
        final renderer = item['playlistVideoRenderer'];
        if (renderer == null) continue;
        if (renderer['videoId'] == videoId) {
          return renderer['setVideoId'] as String?;
        }
      }
      return null;
    });
  }

  /// 獲取播放列表中匹配目標的視頻 ID（用於批量檢查）
  ///
  /// [targetVideoIds] 如果提供，找到所有目標後提前停止分頁
  Future<Set<String>> getVideoIdsInPlaylist(
    String playlistId, {
    Set<String>? targetVideoIds,
  }) async {
    final found = <String>{};
    await _browsePlaylistPages(playlistId, (data) {
      final contents = _getPlaylistVideoContents(data);
      if (contents == null) return null;
      for (final item in contents) {
        final vid = item['playlistVideoRenderer']?['videoId'] as String?;
        if (vid != null) found.add(vid);
      }
      // 如果已找到所有目標，提前停止分頁
      if (targetVideoIds != null && targetVideoIds.difference(found).isEmpty) {
        return true; // 非 null 值觸發提前返回
      }
      return null;
    });
    return found;
  }

  /// 瀏覽播放列表分頁的通用方法
  ///
  /// [onPage] 處理每頁數據，返回非 null 值時提前停止並返回該值
  /// 分頁請求失敗時返回已處理的結果（不會因單頁失敗丟失全部數據）
  Future<T?> _browsePlaylistPages<T>(
    String playlistId,
    T? Function(Map<String, dynamic> data) onPage,
  ) async {
    String? continuationToken;
    do {
      final requestData = continuationToken != null
          ? {
              'continuation': continuationToken,
              'context': _accountService.buildInnerTubeContext()
            }
          : {
              'browseId': 'VL$playlistId',
              'context': _accountService.buildInnerTubeContext()
            };

      try {
        final response = await _dio.post(
          '$_apiBase/browse?key=$_apiKey',
          data: jsonEncode(requestData),
        );

        final data = response.data as Map<String, dynamic>;
        final result = onPage(data);
        if (result != null) return result;

        continuationToken = _extractContinuationToken(data);
      } catch (e) {
        // 首頁失敗直接拋出，後續頁失敗返回已有結果（可能不完整）
        if (continuationToken == null) rethrow;
        logWarning('Playlist pagination failed on subsequent page '
            '(playlist=$playlistId), results may be incomplete: $e');
        return null;
      }
    } while (continuationToken != null);
    return null;
  }

  /// 創建新播放列表
  ///
  /// [privacyStatus] 可選值: 'PUBLIC', 'UNLISTED', 'PRIVATE'
  Future<String?> createPlaylist({
    required String title,
    String privacyStatus = 'UNLISTED',
  }) async {
    final response = await _dio.post(
      '$_apiBase/playlist/create?key=$_apiKey',
      data: jsonEncode({
        'title': title,
        'privacyStatus': privacyStatus,
        'context': _accountService.buildInnerTubeContext(),
      }),
    );

    final data = response.data;
    final playlistId = data['playlistId'] as String?;
    if (playlistId == null) {
      throw YouTubePlaylistException(
        code: 'CREATE_FAILED',
        message: t.remote.error.unknown(code: 'CREATE_FAILED'),
      );
    }

    logInfo('Created YouTube playlist: $playlistId, title=$title');
    return playlistId;
  }

  // ===== 內部解析方法 =====

  /// 從 FEplaylist_aggregation browse 響應中解析播放列表
  List<YouTubePlaylistInfo> _parsePlaylistsFromBrowse(
      Map<String, dynamic> data) {
    final playlists = <YouTubePlaylistInfo>[];

    try {
      // 取得 tabRenderer.content
      final tabContent = data['contents']?['twoColumnBrowseResultsRenderer']
                  ?['tabs']?[0]?['tabRenderer']?['content']
              as Map<String, dynamic>? ??
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]
              ?['tabRenderer']?['content'] as Map<String, dynamic>?;

      if (tabContent != null) {
        // 路徑 A: tabContent > richGridRenderer > contents（新版 YouTube）
        final richGridItems =
            tabContent['richGridRenderer']?['contents'] as List?;
        if (richGridItems != null) {
          _extractPlaylistsFromRichGrid(richGridItems, playlists);
        }

        // 路徑 B: tabContent > sectionListRenderer > contents（舊版）
        final sectionContents =
            tabContent['sectionListRenderer']?['contents'] as List?;
        if (sectionContents != null && playlists.isEmpty) {
          _extractPlaylistsFromSections(sectionContents, playlists);
        }
      }

      // 兜底：遞歸搜索所有已知的播放列表 renderer
      if (playlists.isEmpty) {
        _findPlaylistsRecursive(data, playlists);
      }

      if (playlists.isEmpty) {
        final renderers = <String>{};
        _collectRendererKeys(data, renderers, 0, 15);
        logWarning('YouTube: no playlists found in response. '
            'All renderers: $renderers');
      }
    } catch (e) {
      logError('Failed to parse YouTube playlists', e);
    }

    return playlists;
  }

  /// 從 richGridRenderer contents 中提取播放列表
  void _extractPlaylistsFromRichGrid(
      List items, List<YouTubePlaylistInfo> playlists) {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;

      // richItemRenderer > content > (gridPlaylistRenderer | lockupViewModel | playlistRenderer)
      final content = item['richItemRenderer']?['content'];
      if (content is Map<String, dynamic>) {
        _tryParsePlaylistItem(content, playlists);
      }

      // 直接的 gridPlaylistRenderer
      _tryParsePlaylistItem(item, playlists);
    }
  }

  /// 從 sectionListRenderer contents 中提取播放列表（舊版結構）
  void _extractPlaylistsFromSections(
      List sections, List<YouTubePlaylistInfo> playlists) {
    for (final section in sections) {
      if (section is! Map<String, dynamic>) continue;
      final items = section['itemSectionRenderer']?['contents'] as List?;
      if (items != null) {
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          _tryParsePlaylistItem(item, playlists);
          // shelfRenderer 嵌套
          final shelfItems = item['shelfRenderer']?['content']
              ?['horizontalListRenderer']?['items'] as List?;
          if (shelfItems != null) {
            for (final si in shelfItems) {
              if (si is Map<String, dynamic>) {
                _tryParsePlaylistItem(si, playlists);
              }
            }
          }
        }
      }
      // gridRenderer
      final gridItems = section['gridRenderer']?['items'] as List?;
      if (gridItems != null) {
        for (final gi in gridItems) {
          if (gi is Map<String, dynamic>) _tryParsePlaylistItem(gi, playlists);
        }
      }
    }
  }

  /// 嘗試從一個 item 中解析播放列表（支持多種 renderer 格式）
  void _tryParsePlaylistItem(
      Map<String, dynamic> item, List<YouTubePlaylistInfo> playlists) {
    // 格式 1: gridPlaylistRenderer / playlistRenderer（經典格式）
    final renderer = item['gridPlaylistRenderer'] ?? item['playlistRenderer'];
    if (renderer is Map<String, dynamic>) {
      final playlistId = renderer['playlistId'] as String?;
      final title = _extractText(renderer['title']);
      final countText = _extractText(renderer['videoCountShortText']) ??
          _extractText(renderer['videoCountText']) ??
          _extractText(renderer['thumbnailText']);
      final thumbnail =
          renderer['thumbnail']?['thumbnails']?[0]?['url'] as String?;

      if (playlistId != null && title != null) {
        playlists.add(YouTubePlaylistInfo(
          playlistId: playlistId,
          title: title,
          videoCount: _parseVideoCount(countText),
          thumbnailUrl: thumbnail,
        ));
        return;
      }
    }

    // 格式 2: lockupViewModel（新版 YouTube 2024+）
    final lockup = item['lockupViewModel'];
    if (lockup is Map<String, dynamic>) {
      final contentId = lockup['contentId'] as String?;
      final contentType = lockup['contentType'] as String?;
      // 只處理 PLAYLIST 類型
      if (contentId != null &&
          (contentType == 'LOCKUP_CONTENT_TYPE_PLAYLIST' ||
              contentType == 'PLAYLIST')) {
        final metadata = lockup['metadata']?['lockupMetadataViewModel'];
        final title = metadata?['title']?['content'] as String?;

        // 縮略圖
        final thumbnail = lockup['contentImage']
                        ?['collectionThumbnailViewModel']?['primaryThumbnail']
                    ?['thumbnailViewModel']?['image']?['sources']?[0]?['url']
                as String? ??
            lockup['contentImage']?['thumbnailViewModel']?['image']?['sources']
                ?[0]?['url'] as String?;

        // 視頻數量：嘗試多種路徑
        final countText = _extractVideoCountFromLockup(lockup, metadata);

        if (title != null) {
          playlists.add(YouTubePlaylistInfo(
            playlistId: contentId,
            title: title,
            videoCount: _parseVideoCount(countText),
            thumbnailUrl: thumbnail,
          ));
        }
      }
    }
  }

  /// 從 lockupViewModel 中提取視頻數量文本
  String? _extractVideoCountFromLockup(
      Map<String, dynamic> lockup, Map<String, dynamic>? metadata) {
    final candidates = <String>[];

    // 路徑 1: metadata > contentMetadataViewModel > metadataRows
    final metadataRows = metadata?['metadata']?['contentMetadataViewModel']
        ?['metadataRows'] as List?;
    if (metadataRows != null) {
      final text = _findDigitTextInRows(metadataRows);
      if (text != null) candidates.add(text);
    }

    // 路徑 2: contentImage > collectionThumbnailViewModel > primaryThumbnail > thumbnailViewModel > overlays
    // 縮略圖上的覆蓋文字（如 "473 videos"）
    final overlays = lockup['contentImage']?['collectionThumbnailViewModel']
        ?['primaryThumbnail']?['thumbnailViewModel']?['overlays'] as List?;
    if (overlays != null) {
      for (final overlay in overlays) {
        if (overlay is! Map<String, dynamic>) continue;
        final text = overlay['thumbnailOverlayBadgeViewModel']
            ?['thumbnailBadges'] as List?;
        if (text != null) {
          for (final badge in text) {
            final content =
                badge?['thumbnailBadgeViewModel']?['text'] as String? ??
                    badge?['thumbnailBadgeViewModel']?['icon']?['sources']?[0]
                        ?['clientResource']?['imageName'] as String?;
            if (content != null && RegExp(r'\d').hasMatch(content)) {
              candidates.add(content);
            }
          }
        }
        // thumbnailOverlayBottomPanelRenderer
        final bottomText =
            overlay['thumbnailOverlayBottomPanelRenderer']?['text'] as Map?;
        if (bottomText != null) {
          final t = bottomText['simpleText'] as String? ??
              (bottomText['runs'] as List?)?.map((r) => r['text']).join();
          if (t != null && RegExp(r'\d').hasMatch(t)) {
            candidates.add(t);
          }
        }
      }
    }

    // 路徑 3: 遞歸搜索 lockup 中包含 "video" 或數字的文本
    final found = _findVideoCountTextRecursive(lockup);
    if (found != null) candidates.add(found);

    return pickBestVideoCountText(candidates);
  }

  /// 在 metadataRows 中查找最像視頻數量的文本
  String? _findDigitTextInRows(List rows) {
    final candidates = <String>[];

    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final parts = row['metadataParts'] as List?;
      if (parts == null) continue;

      final rowTexts = <String>[];
      for (final part in parts) {
        final text = part?['text']?['content'] as String?;
        if (text == null || text.trim().isEmpty) continue;
        candidates.add(text);
        rowTexts.add(text);
      }

      if (rowTexts.length > 1) {
        candidates.add(rowTexts.join(' '));
      }
    }

    return pickBestVideoCountText(candidates);
  }

  /// 遞歸搜索 lockup 中的視頻數量文本（查找 "X videos" 模式）
  String? _findVideoCountTextRecursive(dynamic data, [int depth = 0]) {
    if (depth > 8) return null;
    if (data is String) {
      if (RegExp(r'\d+(?:[\.,]\d+)?\s*[KMBkmb]?\s*(video|videos|影片|部)')
          .hasMatch(data)) {
        return data;
      }
      return null;
    }
    if (data is Map<String, dynamic>) {
      // 優先檢查 content 字段
      final content = data['content'];
      if (content is String &&
          RegExp(r'\d+(?:[\.,]\d+)?\s*[KMBkmb]?\s*(video|videos|影片|部)')
              .hasMatch(content)) {
        return content;
      }
      for (final value in data.values) {
        final result = _findVideoCountTextRecursive(value, depth + 1);
        if (result != null) return result;
      }
    } else if (data is List) {
      for (final item in data) {
        final result = _findVideoCountTextRecursive(item, depth + 1);
        if (result != null) return result;
      }
    }
    return null;
  }

  /// 遞歸搜索 JSON 中的播放列表 renderer
  void _findPlaylistsRecursive(
      dynamic data, List<YouTubePlaylistInfo> playlists,
      [int depth = 0]) {
    if (depth > 15 || playlists.length > 100) return;
    if (data is Map<String, dynamic>) {
      if (data.containsKey('gridPlaylistRenderer') ||
          data.containsKey('playlistRenderer') ||
          data.containsKey('lockupViewModel')) {
        _tryParsePlaylistItem(data, playlists);
        return;
      }
      for (final value in data.values) {
        _findPlaylistsRecursive(value, playlists, depth + 1);
      }
    } else if (data is List) {
      for (final item in data) {
        _findPlaylistsRecursive(item, playlists, depth + 1);
      }
    }
  }

  /// 從 InnerTube Text 對象中提取文本（委託到共用工具）
  String? _extractText(dynamic textObj) => InnerTubeUtils.extractText(textObj);

  /// 收集 JSON 中所有以 Renderer/ViewModel 結尾的 key（用於調試）
  void _collectRendererKeys(dynamic data, Set<String> keys,
      [int depth = 0, int maxDepth = 15]) {
    if (depth > maxDepth) return;
    if (data is Map<String, dynamic>) {
      for (final key in data.keys) {
        if (key.endsWith('Renderer') ||
            key.endsWith('ViewModel') ||
            key.endsWith('Model')) {
          keys.add(key);
        }
      }
      for (final value in data.values) {
        _collectRendererKeys(value, keys, depth + 1, maxDepth);
      }
    } else if (data is List) {
      for (final item in data) {
        _collectRendererKeys(item, keys, depth + 1, maxDepth);
      }
    }
  }

  /// 從播放列表瀏覽響應中提取 contents 列表（共用 JSON 路徑）
  List? _getPlaylistVideoContents(Map<String, dynamic> data) {
    try {
      return data['contents']?['twoColumnBrowseResultsRenderer']?['tabs']?[0]
                      ?['tabRenderer']?['content']?['sectionListRenderer']
                  ?['contents']?[0]?['itemSectionRenderer']?['contents']?[0]
              ?['playlistVideoListRenderer']?['contents'] as List? ??
          data['onResponseReceivedActions']?[0]
              ?['appendContinuationItemsAction']?['continuationItems'] as List?;
    } catch (_) {
      return null;
    }
  }

  /// 提取 continuation token
  String? _extractContinuationToken(Map<String, dynamic> data) {
    final contents = _getPlaylistVideoContents(data);
    if (contents == null) return null;

    for (final item in contents) {
      final token = item['continuationItemRenderer']?['continuationEndpoint']
          ?['continuationCommand']?['token'] as String?;
      if (token != null) return token;
    }
    return null;
  }

  @visibleForTesting
  static String? pickBestVideoCountText(Iterable<String?> texts) {
    String? bestText;
    int bestScore = -1;

    for (final raw in texts) {
      final text = raw?.trim();
      if (text == null || text.isEmpty) continue;

      var score = 0;
      if (RegExp(r'\d+(?:[\.,]\d+)?\s*[KMBkmb]?\s*(video|videos|影片|部)')
          .hasMatch(text)) {
        score += 4;
      }
      if (RegExp(r'\d+(?:[\.,]\d+)?\s*[KMBkmb]').hasMatch(text)) {
        score += 2;
      }
      if (RegExp(r'\d').hasMatch(text)) {
        score += 1;
      }
      if (RegExp(r'days?\s+ago|hours?\s+ago|minutes?\s+ago|updated',
              caseSensitive: false)
          .hasMatch(text)) {
        score -= 3;
      }

      if (score > bestScore) {
        bestScore = score;
        bestText = text;
      }
    }

    return bestScore > 0 ? bestText : null;
  }

  @visibleForTesting
  static int parseVideoCount(String? text) {
    if (text == null) return 0;

    final normalized = text.trim();
    if (normalized.isEmpty) return 0;

    final patterns = [
      RegExp(r'(\d+(?:[\.,]\d+)?)\s*([KMBkmb])?\s*(?=videos?\b|影片|部)',
          caseSensitive: false),
      RegExp(r'(\d+(?:[\.,]\d+)?)\s*([KMBkmb])?'),
    ];

    RegExpMatch? match;
    for (final pattern in patterns) {
      match = pattern.firstMatch(normalized);
      if (match != null) break;
    }
    if (match == null) return 0;

    final numberText = match.group(1)?.replaceAll(',', '');
    final value = double.tryParse(numberText ?? '');
    if (value == null) return 0;

    final suffix = match.group(2)?.toUpperCase();
    final multiplier = switch (suffix) {
      'K' => 1e3,
      'M' => 1e6,
      'B' => 1e9,
      _ => 1,
    };

    return (value * multiplier).round();
  }

  int _parseVideoCount(String? text) => parseVideoCount(text);

  void _checkResponse(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map) {
      final code = error['code']?.toString() ?? 'UNKNOWN';
      final message = error['message'] as String? ?? 'Unknown error';
      throw YouTubePlaylistException(code: code, message: message);
    }
    // edit_playlist 成功時返回 {"status": "STATUS_SUCCEEDED"}
    final status = data['status'] as String?;
    if (status != null && status != 'STATUS_SUCCEEDED') {
      throw YouTubePlaylistException(
        code: status,
        message: t.remote.error.unknown(code: status),
      );
    }
  }
}

/// YouTube 播放列表操作異常
class YouTubePlaylistException implements Exception {
  final String code;
  final String message;

  const YouTubePlaylistException({
    required this.code,
    required this.message,
  });

  bool get requiresLogin =>
      code == 'UNAUTHENTICATED' || code == '401' || code == '403';

  @override
  String toString() => 'YouTubePlaylistException($code): $message';
}
