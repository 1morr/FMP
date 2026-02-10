import 'dart:convert';
import 'package:dio/dio.dart';

import 'playlist_import_source.dart';
import 'qq_music_sign.dart';

/// QQ音乐歌单导入源
class QQMusicPlaylistSource implements PlaylistImportSource {
  final Dio _dio;

  QQMusicPlaylistSource({Dio? dio}) : _dio = dio ?? Dio();

  @override
  PlaylistSource get source => PlaylistSource.qqMusic;

  @override
  bool canHandle(String url) {
    return url.contains('y.qq.com') || url.contains('i.y.qq.com');
  }

  @override
  String? extractPlaylistId(String url) {
    // 新版链接: https://y.qq.com/n/ryqq/playlist/8407701300
    final ryqqMatch = RegExp(r'/playlist/(\d+)').firstMatch(url);
    if (ryqqMatch != null) {
      return ryqqMatch.group(1);
    }

    // 旧版链接: https://y.qq.com/n/yqq/playlist/xxx.html
    final yqqMatch = RegExp(r'/playlist/(\d+)\.html').firstMatch(url);
    if (yqqMatch != null) {
      return yqqMatch.group(1);
    }

    // 详情页: https://i.y.qq.com/n2/m/share/details/taoge.html?id=xxx
    final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (idMatch != null) {
      return idMatch.group(1);
    }

    return null;
  }

  @override
  Future<ImportedPlaylist> fetchPlaylist(String url) async {
    // 处理短链接重定向
    final resolvedUrl = await _resolveShortUrl(url);

    final playlistId = extractPlaylistId(resolvedUrl);
    if (playlistId == null) {
      throw Exception('无法解析歌单ID: $url');
    }

    final playlistIdInt = int.tryParse(playlistId);
    if (playlistIdInt == null) {
      throw Exception('无效的歌单ID: $playlistId');
    }

    // 获取歌单信息（分页获取，每页最多1000首）
    final allTracks = <ImportedTrack>[];
    String? playlistName;
    int totalCount = 0;
    const pageSize = 1000;
    var songBegin = 0;

    while (true) {
      final result = await _fetchPlaylistPage(playlistIdInt, songBegin, pageSize);

      playlistName ??= result.name;
      totalCount = result.totalCount;
      allTracks.addAll(result.tracks);

      // 检查是否还有更多
      if (allTracks.length >= totalCount || result.tracks.isEmpty) {
        break;
      }

      songBegin += pageSize;

      // 安全限制：最多获取10000首
      if (songBegin >= 10000) {
        break;
      }
    }

    return ImportedPlaylist(
      name: playlistName ?? '未知歌单',
      sourceUrl: url,
      source: PlaylistSource.qqMusic,
      tracks: allTracks,
      totalCount: totalCount,
    );
  }

  Future<String> _resolveShortUrl(String url) async {
    // QQ音乐短链接处理
    if (url.contains('c.y.qq.com') || url.contains('url.cn')) {
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

  Future<_PlaylistPageResult> _fetchPlaylistPage(
    int playlistId,
    int songBegin,
    int songNum,
  ) async {
    final requestBody = _buildRequest(playlistId, songBegin, songNum);
    final requestJson = jsonEncode(requestBody);
    final sign = QQMusicSign.encrypt(requestJson);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final response = await _dio.post(
      'https://u6.y.qq.com/cgi-bin/musics.fcg?sign=$sign&_=$timestamp',
      data: requestJson,
      options: Options(
        contentType: 'application/json',
        responseType: ResponseType.json,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
          'Referer': 'https://y.qq.com/',
        },
      ),
    );

    final data = _parseResponse(response.data);

    final req0 = data['req_0'];
    if (req0 is! Map<String, dynamic>) {
      throw Exception('响应数据格式错误');
    }

    final code = req0['code'];
    if (code != 0) {
      throw Exception('获取歌单失败: code=$code');
    }

    final reqData = req0['data'];
    if (reqData is! Map<String, dynamic>) {
      throw Exception('响应数据格式错误');
    }

    // 解析歌单信息
    final dirinfo = reqData['dirinfo'];
    final name = dirinfo is Map<String, dynamic>
        ? dirinfo['title'] as String?
        : null;
    final totalCount = dirinfo is Map<String, dynamic>
        ? (dirinfo['songnum'] as int? ?? 0)
        : 0;

    // 解析歌曲列表
    final songlist = reqData['songlist'];
    final tracks = <ImportedTrack>[];

    if (songlist is List) {
      for (final song in songlist) {
        if (song is! Map<String, dynamic>) continue;

        final title = song['name'] as String? ?? '';
        final singers = song['singer'];
        final artists = _extractArtists(singers);
        final album = _extractAlbumName(song['album']);
        final interval = song['interval'] as int?;

        tracks.add(ImportedTrack(
          title: title,
          artists: artists,
          album: album,
          duration: interval != null ? Duration(seconds: interval) : null,
        ));
      }
    }

    return _PlaylistPageResult(
      name: name,
      totalCount: totalCount,
      tracks: tracks,
    );
  }

  /// 解析响应数据，处理字符串或Map格式
  Map<String, dynamic> _parseResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
      } catch (_) {
        // 解析失败
      }
    }
    throw Exception('无效的响应格式');
  }

  Map<String, dynamic> _buildRequest(int playlistId, int songBegin, int songNum) {
    return {
      'req_0': {
        'module': 'music.srfDissInfo.aiDissInfo',
        'method': 'uniform_get_Dissinfo',
        'param': {
          'disstid': playlistId,
          'enc_host_uin': '',
          'tag': 1,
          'userinfo': 1,
          'song_begin': songBegin,
          'song_num': songNum,
        },
      },
      'comm': {
        'g_tk': 5381,
        'uin': 0,
        'format': 'json',
        'platform': 'android',
      },
    };
  }

  List<String> _extractArtists(dynamic singers) {
    if (singers is! List) {
      return ['未知艺术家'];
    }

    final artists = singers
        .map((singer) {
          if (singer is Map<String, dynamic>) {
            return singer['name'] as String?;
          }
          return null;
        })
        .whereType<String>()
        .toList();

    return artists.isEmpty ? ['未知艺术家'] : artists;
  }

  String? _extractAlbumName(dynamic album) {
    if (album is Map<String, dynamic>) {
      return album['name'] as String?;
    }
    return null;
  }
}

class _PlaylistPageResult {
  final String? name;
  final int totalCount;
  final List<ImportedTrack> tracks;

  _PlaylistPageResult({
    this.name,
    required this.totalCount,
    required this.tracks,
  });
}
