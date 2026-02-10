import 'dart:convert';
import 'package:dio/dio.dart';

import 'playlist_import_source.dart';

/// 网易云音乐歌单导入源
class NeteasePlaylistSource implements PlaylistImportSource {
  final Dio _dio;

  NeteasePlaylistSource({Dio? dio}) : _dio = dio ?? Dio();

  @override
  PlaylistSource get source => PlaylistSource.netease;

  @override
  bool canHandle(String url) {
    return url.contains('music.163.com') ||
        url.contains('163cn.tv') ||
        url.contains('y.music.163.com');
  }

  @override
  String? extractPlaylistId(String url) {
    // 标准链接: https://music.163.com/#/playlist?id=2829896389
    // 或: https://music.163.com/playlist?id=2829896389
    final idMatch = RegExp(r'[?&]id=(\d+)').firstMatch(url);
    if (idMatch != null) {
      return idMatch.group(1);
    }

    // 移动端链接: https://y.music.163.com/m/playlist?id=xxx
    final mobileMatch = RegExp(r'/playlist[?/].*?(\d{5,})').firstMatch(url);
    if (mobileMatch != null) {
      return mobileMatch.group(1);
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

    // 1. 获取歌单基本信息
    final playlistInfo = await _fetchPlaylistInfo(playlistId);
    final name = playlistInfo['name'] as String? ?? '未知歌单';
    final trackIds = _extractTrackIds(playlistInfo);

    if (trackIds.isEmpty) {
      throw Exception('歌单为空或无法访问');
    }

    // 2. 批量获取歌曲详情（每次最多400首）
    final tracks = <ImportedTrack>[];
    const batchSize = 400;

    for (var i = 0; i < trackIds.length; i += batchSize) {
      final batchIds = trackIds.skip(i).take(batchSize).toList();
      final batchTracks = await _fetchTrackDetails(batchIds);
      tracks.addAll(batchTracks);
    }

    return ImportedPlaylist(
      name: name,
      sourceUrl: url,
      source: PlaylistSource.netease,
      tracks: tracks,
      totalCount: trackIds.length,
    );
  }

  Future<String> _resolveShortUrl(String url) async {
    if (url.contains('163cn.tv')) {
      try {
        final response = await _dio.head(
          url,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        final location = response.headers.value('location');
        if (location != null) {
          return location;
        }
      } catch (e) {
        // 如果重定向失败，尝试 GET 请求
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
    }
    return url;
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

  Future<Map<String, dynamic>> _fetchPlaylistInfo(String playlistId) async {
    final response = await _dio.post(
      'https://music.163.com/api/v6/playlist/detail',
      data: 'id=$playlistId',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        responseType: ResponseType.json,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        },
      ),
    );

    final data = _parseResponse(response.data);

    final code = data['code'];
    if (code != 200) {
      throw Exception('获取歌单失败: ${data['message'] ?? '未知错误'}');
    }

    final playlist = data['playlist'];
    if (playlist is! Map<String, dynamic>) {
      throw Exception('歌单数据格式错误');
    }

    return playlist;
  }

  List<int> _extractTrackIds(Map<String, dynamic> playlist) {
    final trackIds = playlist['trackIds'];
    if (trackIds is! List) {
      return [];
    }

    return trackIds
        .map((item) {
          if (item is Map<String, dynamic>) {
            return item['id'] as int?;
          }
          return null;
        })
        .whereType<int>()
        .toList();
  }

  Future<List<ImportedTrack>> _fetchTrackDetails(List<int> trackIds) async {
    final songIds = trackIds.map((id) => {'id': id}).toList();

    final response = await _dio.post(
      'https://music.163.com/api/v3/song/detail',
      data: 'c=${jsonEncode(songIds)}',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        responseType: ResponseType.json,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com/',
        },
      ),
    );

    final data = _parseResponse(response.data);

    final songs = data['songs'];
    if (songs is! List) {
      return [];
    }

    return songs.map((song) {
      if (song is! Map<String, dynamic>) {
        return null;
      }

      final name = song['name'] as String? ?? '';
      final artists = _extractArtists(song['ar']);
      final album = _extractAlbumName(song['al']);
      final duration = song['dt'] as int?;

      return ImportedTrack(
        title: name,
        artists: artists,
        album: album,
        duration: duration != null ? Duration(milliseconds: duration) : null,
      );
    }).whereType<ImportedTrack>().toList();
  }

  List<String> _extractArtists(dynamic ar) {
    if (ar is! List) {
      return ['未知艺术家'];
    }

    final artists = ar
        .map((artist) {
          if (artist is Map<String, dynamic>) {
            return artist['name'] as String?;
          }
          return null;
        })
        .whereType<String>()
        .toList();

    return artists.isEmpty ? ['未知艺术家'] : artists;
  }

  String? _extractAlbumName(dynamic al) {
    if (al is Map<String, dynamic>) {
      return al['name'] as String?;
    }
    return null;
  }
}
