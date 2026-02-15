import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'lyrics_result.dart';


/// lrclib.net API 异常
class LrclibException implements Exception {
  final int? statusCode;
  final String message;

  const LrclibException({this.statusCode, required this.message});

  @override
  String toString() => 'LrclibException($statusCode): $message';
}

/// lrclib.net API 客户端
///
/// API 文档: https://lrclib.net/docs
/// 无需 API key，无速率限制。
class LrclibSource with Logging {
  static const _baseUrl = 'https://lrclib.net/api';
  static const _userAgent = 'FMP/1.0.0 (https://github.com/user/fmp)';

  final Dio _dio;

  LrclibSource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              headers: {
                'User-Agent': _userAgent,
              },
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  /// 搜索歌词
  ///
  /// [q] 全文搜索（匹配 trackName/artistName/albumName 任意字段）
  /// [trackName] 按歌曲名搜索
  /// [artistName] 按歌手名搜索（需配合 trackName 使用）
  ///
  /// 至少提供 [q] 或 [trackName] 之一。最多返回 20 条结果。
  Future<List<LyricsResult>> search({
    String? q,
    String? trackName,
    String? artistName,
  }) async {
    assert(
      q != null || trackName != null,
      'At least one of q or trackName must be provided',
    );

    final params = <String, String>{};
    if (q != null) params['q'] = q;
    if (trackName != null) params['track_name'] = trackName;
    if (artistName != null) params['artist_name'] = artistName;

    logDebug('Searching lrclib: $params');

    try {
      final response = await _dio.get('/search', queryParameters: params);
      final data = response.data;

      if (data is! List) {
        logWarning('Unexpected response type: ${data.runtimeType}');
        return [];
      }

      final results = data
          .cast<Map<String, dynamic>>()
          .map(LyricsResult.fromJson)
          .toList();

      logDebug('Found ${results.length} results');
      return results;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 按 ID 获取歌词
  Future<LyricsResult?> getById(String id) async {
    logDebug('Getting lyrics by id: $id');

    try {
      final response = await _dio.get('/get/$id');
      return LyricsResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleDioError(e);
    }
  }

  /// 精确匹配歌词（需要完整签名）
  ///
  /// duration 容差为 ±2 秒（lrclib 服务端限制）。
  /// 此 API 会尝试从外部源获取，响应时间可能较长。
  Future<LyricsResult?> getExact({
    required String trackName,
    required String artistName,
    String albumName = '',
    required int durationSeconds,
  }) async {
    logDebug(
      'Exact match: track="$trackName", artist="$artistName", '
      'album="$albumName", duration=${durationSeconds}s',
    );

    try {
      final response = await _dio.get('/get', queryParameters: {
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'duration': durationSeconds,
      });
      return LyricsResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleDioError(e);
    }
  }

  LrclibException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timeout',
      DioExceptionType.receiveTimeout => 'Receive timeout',
      DioExceptionType.connectionError => 'Connection error: ${e.message}',
      _ => e.response?.data?.toString() ?? e.message ?? 'Unknown error',
    };
    logError('lrclib API error: $statusCode $message');
    return LrclibException(statusCode: statusCode, message: message);
  }
}
