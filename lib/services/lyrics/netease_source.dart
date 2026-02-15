import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'lyrics_result.dart';

// ============================================================
// 网易云音乐歌词源 - Demo / 概念验证
//
// API 端点（无需登录、无需加密）：
//   搜索: POST https://music.163.com/api/search/get
//   歌词: GET  https://music.163.com/api/song/lyric?id={id}&lv=1&tv=1
//
// 注意：这些是网易云音乐的非官方 API，可能随时变更。
// 仅供学习研究使用。
// ============================================================

/// 网易云搜索结果中的歌曲
class NeteaseSong {
  final int id;
  final String name;
  final List<String> artists;
  final String albumName;
  final int durationMs;

  const NeteaseSong({
    required this.id,
    required this.name,
    required this.artists,
    required this.albumName,
    required this.durationMs,
  });

  factory NeteaseSong.fromJson(Map<String, dynamic> json) {
    final artistList = (json['artists'] as List<dynamic>?)
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];

    return NeteaseSong(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      artists: artistList,
      albumName:
          (json['album'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      durationMs: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }

  /// 歌手名拼接
  String get artistsJoined => artists.join(', ');

  /// 时长（秒）
  int get durationSeconds => (durationMs / 1000).round();

  @override
  String toString() =>
      'NeteaseSong(id: $id, "$name" by "$artistsJoined", '
      'album: "$albumName", ${durationSeconds}s)';
}

/// 网易云歌词结果
class NeteaseLyrics {
  final int songId;

  /// 原文歌词（LRC 格式）
  final String? lrc;

  /// 翻译歌词（LRC 格式）
  final String? tlyric;

  /// 罗马音歌词（LRC 格式）
  final String? romalrc;

  const NeteaseLyrics({
    required this.songId,
    this.lrc,
    this.tlyric,
    this.romalrc,
  });

  factory NeteaseLyrics.fromJson(int songId, Map<String, dynamic> json) {
    return NeteaseLyrics(
      songId: songId,
      lrc: (json['lrc'] as Map<String, dynamic>?)?['lyric'] as String?,
      tlyric: (json['tlyric'] as Map<String, dynamic>?)?['lyric'] as String?,
      romalrc: (json['romalrc'] as Map<String, dynamic>?)?['lyric'] as String?,
    );
  }

  bool get hasLrc => lrc != null && lrc!.trim().isNotEmpty;
  bool get hasTranslation => tlyric != null && tlyric!.trim().isNotEmpty;
  bool get hasRomaji => romalrc != null && romalrc!.trim().isNotEmpty;

  /// 是否为纯音乐（无歌词）
  bool get isInstrumental =>
      !hasLrc ||
      (lrc != null && lrc!.contains('纯音乐，请欣赏'));

  @override
  String toString() =>
      'NeteaseLyrics(songId: $songId, lrc: $hasLrc, '
      'tlyric: $hasTranslation, romalrc: $hasRomaji)';
}

/// 网易云 API 异常
class NeteaseException implements Exception {
  final int? statusCode;
  final int? apiCode;
  final String message;

  const NeteaseException({this.statusCode, this.apiCode, required this.message});

  @override
  String toString() =>
      'NeteaseException(http: $statusCode, api: $apiCode): $message';
}

/// 网易云音乐歌词源
///
/// 直接调用网易云音乐 Web API，无需登录。
/// 搜索歌曲 → 获取歌词，两步完成。
class NeteaseSource with Logging {
  static const _baseUrl = 'https://music.163.com';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final Dio _dio;

  NeteaseSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              headers: {
                'User-Agent': _userAgent,
                'Referer': 'https://music.163.com/',
                'Origin': 'https://music.163.com',
              },
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  /// 搜索歌曲
  ///
  /// [keywords] 搜索关键词（歌名、歌手等）
  /// [limit] 返回数量，默认 20
  /// [offset] 偏移量，用于分页
  Future<List<NeteaseSong>> searchSongs({
    required String keywords,
    int limit = 20,
    int offset = 0,
  }) async {
    logDebug('Netease search: "$keywords" (limit=$limit, offset=$offset)');

    try {
      final response = await _dio.post(
        '/api/search/get',
        data:
            's=${Uri.encodeComponent(keywords)}&type=1&limit=$limit&offset=$offset',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );

      final data = _ensureMap(response.data);
      final code = data['code'] as int?;

      if (code != 200) {
        throw NeteaseException(
          apiCode: code,
          message: 'Search failed with code $code',
        );
      }

      final result = data['result'] as Map<String, dynamic>?;
      final songs = result?['songs'] as List<dynamic>?;

      if (songs == null || songs.isEmpty) {
        logDebug('No results found');
        return [];
      }

      final results = songs
          .cast<Map<String, dynamic>>()
          .map(NeteaseSong.fromJson)
          .toList();

      logDebug('Found ${results.length} songs');
      return results;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 获取歌词
  ///
  /// [songId] 网易云歌曲 ID
  /// 返回包含原文歌词、翻译歌词、罗马音歌词的结果
  Future<NeteaseLyrics> getLyrics(int songId) async {
    logDebug('Fetching lyrics for song $songId');

    try {
      final response = await _dio.get(
        '/api/song/lyric',
        queryParameters: {
          'id': songId,
          'lv': 1, // 请求原文歌词
          'tv': 1, // 请求翻译歌词
          'rv': 1, // 请求罗马音歌词
        },
        options: Options(responseType: ResponseType.plain),
      );

      final data = _ensureMap(response.data);
      final code = data['code'] as int?;

      if (code != 200) {
        throw NeteaseException(
          apiCode: code,
          message: 'Get lyrics failed with code $code',
        );
      }

      final result = NeteaseLyrics.fromJson(songId, data);
      logDebug('Lyrics result: $result');
      return result;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 搜索并获取歌词（便捷方法）
  ///
  /// 搜索歌曲，取第一个结果的歌词。
  /// 返回 null 表示未找到。
  Future<NeteaseLyrics?> searchAndGetLyrics({
    required String keywords,
  }) async {
    final songs = await searchSongs(keywords: keywords, limit: 5);
    if (songs.isEmpty) return null;

    // 取第一个结果
    final song = songs.first;
    logDebug('Using first result: $song');

    return getLyrics(song.id);
  }

  /// 搜索歌词并返回统一的 LyricsResult 列表
  ///
  /// 搜索歌曲 → 批量获取歌词 → 转换为 LyricsResult。
  /// [query] 全文搜索关键词
  /// [trackName] 歌曲名（可选，用于构建搜索词）
  /// [artistName] 歌手名（可选，用于构建搜索词）
  /// [limit] 最大返回数量
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    // 构建搜索关键词
    final keywords = query ??
        [trackName, artistName].where((s) => s != null && s.isNotEmpty).join(' ');
    if (keywords.isEmpty) return [];

    final songs = await searchSongs(keywords: keywords, limit: limit);
    if (songs.isEmpty) return [];

    // 批量获取歌词，转换为 LyricsResult
    final results = <LyricsResult>[];
    for (final song in songs) {
      try {
        final lyrics = await getLyrics(song.id);
        if (!lyrics.hasLrc && !lyrics.isInstrumental) continue;

        results.add(_toLyricsResult(song, lyrics));
      } catch (e) {
        logWarning('Failed to get lyrics for song ${song.id}: $e');
      }
    }

    logDebug('Netease searchLyrics: ${results.length} results with lyrics');
    return results;
  }

  /// 通过网易云歌曲 ID 获取歌词，返回统一的 LyricsResult
  Future<LyricsResult?> getLyricsResult(int songId) async {
    try {
      // 先获取歌曲信息（用于填充 trackName 等字段）
      final lyrics = await getLyrics(songId);
      if (!lyrics.hasLrc) return null;

      return LyricsResult(
        id: songId,
        trackName: '',
        artistName: '',
        albumName: '',
        duration: 0,
        instrumental: lyrics.isInstrumental,
        plainLyrics: null,
        syncedLyrics: lyrics.lrc,
        source: 'netease',
        translatedLyrics: lyrics.tlyric,
        romajiLyrics: lyrics.romalrc,
      );
    } catch (e) {
      logError('Failed to get lyrics result for song $songId: $e');
      return null;
    }
  }

  /// 将 NeteaseSong + NeteaseLyrics 转换为统一的 LyricsResult
  LyricsResult _toLyricsResult(NeteaseSong song, NeteaseLyrics lyrics) {
    return LyricsResult(
      id: song.id,
      trackName: song.name,
      artistName: song.artistsJoined,
      albumName: song.albumName,
      duration: song.durationSeconds,
      instrumental: lyrics.isInstrumental,
      plainLyrics: null,
      syncedLyrics: lyrics.lrc,
      source: 'netease',
      translatedLyrics: lyrics.tlyric,
      romajiLyrics: lyrics.romalrc,
    );
  }

  /// 确保响应数据是 Map（Dio 有时返回 String 而非 Map）
  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    throw NeteaseException(
      message: 'Unexpected response type: ${data.runtimeType}',
    );
  }

  NeteaseException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timeout',
      DioExceptionType.receiveTimeout => 'Receive timeout',
      DioExceptionType.connectionError => 'Connection error: ${e.message}',
      _ => e.response?.data?.toString() ?? e.message ?? 'Unknown error',
    };
    logError('Netease API error: $statusCode $message');
    return NeteaseException(statusCode: statusCode, message: message);
  }
}
