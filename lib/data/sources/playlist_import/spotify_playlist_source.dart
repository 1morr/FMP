import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fmp/i18n/strings.g.dart';

import 'playlist_import_source.dart';

/// Spotify 歌单导入源
///
/// 通过抓取 Spotify embed 页面的 __NEXT_DATA__ JSON 获取曲目信息。
/// embed 页面不需要认证，包含完整的曲目列表（标题、艺术家、时长）。
class SpotifyPlaylistSource implements PlaylistImportSource {
  final Dio _dio;

  SpotifyPlaylistSource({Dio? dio}) : _dio = dio ?? Dio();

  @override
  PlaylistSource get source => PlaylistSource.spotify;

  @override
  bool canHandle(String url) {
    return url.contains('open.spotify.com/playlist') ||
        url.contains('spotify.link');
  }

  @override
  String? extractPlaylistId(String url) {
    // 标准链接: https://open.spotify.com/playlist/{id}
    // 带参数: https://open.spotify.com/playlist/{id}?si=...
    final match =
        RegExp(r'open\.spotify\.com/playlist/([a-zA-Z0-9]+)').firstMatch(url);
    return match?.group(1);
  }

  @override
  Future<ImportedPlaylist> fetchPlaylist(String url) async {
    // 处理短链接重定向
    final resolvedUrl = await _resolveShortUrl(url);

    final playlistId = extractPlaylistId(resolvedUrl);
    if (playlistId == null) {
      throw Exception(t.importSource.cannotParsePlaylistId(url: url));
    }

    // 使用 embed 页面获取数据（包含 __NEXT_DATA__）
    final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';

    final response = await _dio.get(
      embedUrl,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en',
        },
        responseType: ResponseType.plain,
      ),
    );

    final html = response.data as String;
    final data = _extractNextData(html);

    if (data == null) {
      throw Exception(t.importSource.spotifyCannotParsePageData);
    }

    return _parsePlaylistData(data, url);
  }

  /// 处理 spotify.link 短链接重定向
  Future<String> _resolveShortUrl(String url) async {
    if (url.contains('spotify.link')) {
      try {
        final response = await _dio.get(
          url,
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
          ),
        );
        return response.realUri.toString();
      } catch (_) {
        // 忽略错误，返回原始URL
      }
    }
    return url;
  }

  /// 从 HTML 中提取 __NEXT_DATA__ JSON
  Map<String, dynamic>? _extractNextData(String html) {
    // 匹配 <script id="__NEXT_DATA__" type="application/json">...</script>
    final match = RegExp(
      r'<script\s+id="__NEXT_DATA__"\s+type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);

    if (match == null) return null;

    try {
      final json = jsonDecode(match.group(1)!);
      if (json is Map<String, dynamic>) {
        return json;
      }
    } catch (_) {
      // JSON 解析失败
    }

    return null;
  }

  /// 从 __NEXT_DATA__ 解析歌单数据
  ImportedPlaylist _parsePlaylistData(
    Map<String, dynamic> nextData,
    String sourceUrl,
  ) {
    // 路径: props.pageProps.state.data.entity
    final entity = _navigateJson(nextData, [
      'props',
      'pageProps',
      'state',
      'data',
      'entity',
    ]);

    if (entity is! Map<String, dynamic>) {
      throw Exception(t.importSource.spotifyPageDataAbnormal);
    }

    final name =
        entity['name'] as String? ?? entity['title'] as String? ?? t.importSource.unknownPlaylist;

    final trackList = entity['trackList'];
    if (trackList is! List) {
      throw Exception(t.importSource.spotifyCannotGetTrackList);
    }

    final tracks = <ImportedTrack>[];

    for (final item in trackList) {
      if (item is! Map<String, dynamic>) continue;

      final title = item['title'] as String?;
      if (title == null || title.isEmpty) continue;

      // subtitle 包含艺术家名（多个艺术家用逗号分隔）
      final subtitle = item['subtitle'] as String? ?? '';
      final artists = subtitle.isNotEmpty
          ? subtitle.split(', ').where((s) => s.isNotEmpty).toList()
          : <String>[t.general.unknownArtist];

      // duration 单位为毫秒
      final durationMs = item['duration'] as int?;

      // 提取 Spotify track ID（uid 或 id 字段）
      final trackId = (item['uid'] as String?) ?? (item['id'] as String?);

      tracks.add(ImportedTrack(
        title: title,
        artists: artists,
        duration:
            durationMs != null ? Duration(milliseconds: durationMs) : null,
        sourceId: trackId,
        source: PlaylistSource.spotify,
      ));
    }

    if (tracks.isEmpty) {
      throw Exception(t.importSource.playlistEmptyOrInaccessible);
    }

    return ImportedPlaylist(
      name: name,
      sourceUrl: sourceUrl,
      source: PlaylistSource.spotify,
      tracks: tracks,
      totalCount: tracks.length,
    );
  }

  /// 安全地按路径导航 JSON 对象
  dynamic _navigateJson(dynamic json, List<String> path) {
    dynamic current = json;
    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }
}
