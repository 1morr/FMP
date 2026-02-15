import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'lyrics_result.dart';

// ============================================================
// QQ 音乐歌词源
//
// API 端点：
//   搜索: POST https://u.y.qq.com/cgi-bin/musicu.fcg
//         body: JSON (music.search.SearchCgiService / DoSearchForQQMusicDesktop)
//   歌词: POST https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg
//         body: format=json&nobase64=1&g_tk=5381&songmid=xxx
//         headers: Referer: https://y.qq.com
//
// 注意：这些是 QQ 音乐的非官方 API，可能随时变更。
// 仅供学习研究使用。
// ============================================================

/// QQ 音乐搜索结果中的歌曲
class QQMusicSong {
  final String songmid;
  final String songname;
  final List<String> singers;
  final String albumName;
  final int interval; // 秒

  const QQMusicSong({
    required this.songmid,
    required this.songname,
    required this.singers,
    required this.albumName,
    required this.interval,
  });

  factory QQMusicSong.fromJson(Map<String, dynamic> json) {
    final singerList = (json['singer'] as List<dynamic>?)
            ?.map((s) => (s as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];
    return QQMusicSong(
      songmid: json['mid'] as String? ?? json['songmid'] as String? ?? '',
      songname: json['name'] as String? ?? json['songname'] as String? ?? '',
      singers: singerList,
      albumName:
          (json['album'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      interval: (json['interval'] as num?)?.toInt() ?? 0,
    );
  }

  String get singersJoined => singers.join(', ');

  @override
  String toString() =>
      'QQMusicSong(mid: $songmid, "$songname" by "$singersJoined", '
      'album: "$albumName", ${interval}s)';
}

/// QQ 音乐歌词结果
class QQMusicLyrics {
  final String songmid;

  /// 原文歌词（LRC 格式）
  final String? lyric;

  /// 翻译歌词（LRC 格式）
  final String? trans;

  const QQMusicLyrics({
    required this.songmid,
    this.lyric,
    this.trans,
  });

  bool get hasLyric => lyric != null && lyric!.trim().isNotEmpty;
  bool get hasTranslation => trans != null && trans!.trim().isNotEmpty;

  @override
  String toString() =>
      'QQMusicLyrics(mid: $songmid, lyric: $hasLyric, trans: $hasTranslation)';
}

/// QQ 音乐 API 异常
class QQMusicException implements Exception {
  final int? statusCode;
  final String message;

  const QQMusicException({this.statusCode, required this.message});

  @override
  String toString() => 'QQMusicException(http: $statusCode): $message';
}

/// QQ 音乐歌词源
///
/// 直接调用 QQ 音乐 Web API，无需登录。
/// 搜索歌曲 → 获取歌词，两步完成。
class QQMusicSource with Logging {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) '
      'Gecko/20100101 Firefox/115.0';

  final Dio _dio;

  QQMusicSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              headers: {
                'User-Agent': _userAgent,
                'Accept': 'application/json, text/plain, */*',
                'Accept-Language': 'zh-CN,zh;q=0.8,en-US;q=0.3,en;q=0.2',
              },
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  /// 搜索歌曲
  ///
  /// [keywords] 搜索关键词
  /// [limit] 返回数量，默认 10
  Future<List<QQMusicSong>> searchSongs({
    required String keywords,
    int limit = 10,
  }) async {
    logDebug('QQMusic search: "$keywords" (limit=$limit)');

    try {
      final body = jsonEncode({
        'comm': {'ct': '19', 'cv': '1859', 'uin': '0'},
        'req': {
          'method': 'DoSearchForQQMusicDesktop',
          'module': 'music.search.SearchCgiService',
          'param': {
            'grp': 1,
            'num_per_page': limit,
            'page_num': 1,
            'query': keywords,
            'search_type': 0,
          },
        },
      });

      final resp = await _dio.post(
        'https://u.y.qq.com/cgi-bin/musicu.fcg',
        data: body,
        options: Options(
          contentType: 'application/json;charset=utf-8',
          responseType: ResponseType.plain,
        ),
      );

      final data = _ensureMap(resp.data);
      final songBody =
          data['req']?['data']?['body']?['song'] as Map<String, dynamic>?;
      final list = (songBody?['list'] as List<dynamic>?) ?? [];

      final results = list
          .cast<Map<String, dynamic>>()
          .map(QQMusicSong.fromJson)
          .toList();

      logDebug('Found ${results.length} songs');
      return results;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 获取歌词
  ///
  /// [songmid] QQ 音乐歌曲 mid
  Future<QQMusicLyrics> getLyrics(String songmid) async {
    logDebug('Fetching QQMusic lyrics for $songmid');

    try {
      final resp = await _dio.post(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg',
        data: 'format=json&nobase64=1&g_tk=5381&songmid=$songmid',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://y.qq.com',
          },
        ),
      );

      final data = _ensureMap(resp.data);
      final retcode = data['retcode'] as int?;

      if (retcode != 0) {
        // nobase64=1 失败时，尝试 base64 模式
        logDebug('nobase64 mode failed (retcode=$retcode), trying base64...');
        return _getLyricsBase64(songmid);
      }

      return QQMusicLyrics(
        songmid: songmid,
        lyric: data['lyric'] != null
            ? _decodeHtmlEntities(data['lyric'] as String)
            : null,
        trans: data['trans'] != null
            ? _decodeHtmlEntities(data['trans'] as String)
            : null,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 获取歌词（base64 模式，作为 fallback）
  Future<QQMusicLyrics> _getLyricsBase64(String songmid) async {
    try {
      final resp = await _dio.post(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_yqq.fcg',
        data: 'format=json&g_tk=5381&songmid=$songmid',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://y.qq.com',
          },
        ),
      );

      final data = _ensureMap(resp.data);
      final retcode = data['retcode'] as int?;

      if (retcode != 0) {
        logWarning('QQMusic lyrics API failed: retcode=$retcode');
        return QQMusicLyrics(songmid: songmid);
      }

      return QQMusicLyrics(
        songmid: songmid,
        lyric: _decodeField(_tryDecodeBase64(data['lyric'])),
        trans: _decodeField(_tryDecodeBase64(data['trans'])),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 搜索歌词并返回统一的 LyricsResult 列表
  ///
  /// [query] 全文搜索关键词
  /// [trackName] 歌曲名（可选）
  /// [artistName] 歌手名（可选）
  /// [limit] 最大返回数量
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    final keywords = query ??
        [trackName, artistName]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ');
    if (keywords.isEmpty) return [];

    final songs = await searchSongs(keywords: keywords, limit: limit);
    if (songs.isEmpty) return [];

    final results = <LyricsResult>[];
    for (final song in songs) {
      try {
        final lyrics = await getLyrics(song.songmid);
        if (!lyrics.hasLyric) continue;

        results.add(_toLyricsResult(song, lyrics));
      } catch (e) {
        logWarning('Failed to get lyrics for song ${song.songmid}: $e');
      }
    }

    logDebug('QQMusic searchLyrics: ${results.length} results with lyrics');
    return results;
  }

  /// 通过 songmid 获取歌词，返回统一的 LyricsResult
  Future<LyricsResult?> getLyricsResult(String songmid) async {
    try {
      final lyrics = await getLyrics(songmid);
      if (!lyrics.hasLyric) return null;

      return LyricsResult(
        id: songmid,
        trackName: '',
        artistName: '',
        albumName: '',
        duration: 0,
        instrumental: false,
        plainLyrics: null,
        syncedLyrics: lyrics.lyric,
        source: 'qqmusic',
        translatedLyrics: lyrics.trans,
      );
    } catch (e) {
      logError('Failed to get lyrics result for songmid $songmid: $e');
      return null;
    }
  }

  /// 将 QQMusicSong + QQMusicLyrics 转换为统一的 LyricsResult
  LyricsResult _toLyricsResult(QQMusicSong song, QQMusicLyrics lyrics) {
    return LyricsResult(
      id: song.songmid,
      trackName: song.songname,
      artistName: song.singersJoined,
      albumName: song.albumName,
      duration: song.interval,
      instrumental: false,
      plainLyrics: null,
      syncedLyrics: lyrics.lyric,
      source: 'qqmusic',
      translatedLyrics: lyrics.trans,
    );
  }

  /// 解码 HTML 实体
  ///
  /// QQ 音乐歌词接口返回的 HTML 编码，如 `&#58;` → `:`, `&#32;` → 空格
  String _decodeHtmlEntities(String input) {
    var result = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#38;apos&#59;', "'");

    // 数字实体 &#xx;
    result = result.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!)),
    );

    // 十六进制实体 &#xHH;
    result = result.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
    );

    return result;
  }

  /// 尝试 base64 解码，失败则返回原文
  String? _tryDecodeBase64(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(str));
    } catch (_) {
      return str;
    }
  }

  /// 对可能含 HTML 实体的字段做解码
  String? _decodeField(String? value) {
    if (value == null) return null;
    return _decodeHtmlEntities(value);
  }

  /// 确保响应数据是 Map
  Map<String, dynamic> _ensureMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    throw QQMusicException(
      message: 'Unexpected response type: ${data.runtimeType}',
    );
  }

  QQMusicException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timeout',
      DioExceptionType.receiveTimeout => 'Receive timeout',
      DioExceptionType.connectionError => 'Connection error: ${e.message}',
      _ => e.response?.data?.toString() ?? e.message ?? 'Unknown error',
    };
    logError('QQMusic API error: $statusCode $message');
    return QQMusicException(statusCode: statusCode, message: message);
  }
}
