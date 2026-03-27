import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../i18n/strings.g.dart';
import '../../data/sources/playlist_import/netease_playlist_source.dart';
import 'netease_account_service.dart';
import 'netease_auth_interceptor.dart';

class NeteasePlaylistInfo {
  final String playlistId;
  final String title;
  final int trackCount;
  final String? thumbnailUrl;
  final String? creatorId;
  final String? creatorName;
  final bool isMine;

  const NeteasePlaylistInfo({
    required this.playlistId,
    required this.title,
    required this.trackCount,
    this.thumbnailUrl,
    this.creatorId,
    this.creatorName,
    this.isMine = false,
  });
}

class NeteasePlaylistDetail {
  final String playlistId;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? ownerId;
  final String? ownerName;
  final List<Map<String, dynamic>> tracks;

  const NeteasePlaylistDetail({
    required this.playlistId,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.ownerId,
    this.ownerName,
    required this.tracks,
  });
}

class NeteasePlaylistException implements Exception {
  final String code;
  final String message;

  const NeteasePlaylistException({
    required this.code,
    required this.message,
  });

  bool get requiresLogin => code == 'NOT_LOGGED_IN';

  @override
  String toString() => 'NeteasePlaylistException($code): $message';
}

class NeteasePlaylistService with Logging {
  static const String _musicBase = 'https://music.163.com';
  static const String _linuxApiBase = '$_musicBase/api/linux/forward';
  static const String _linuxApiKey = 'rFgB&h#%2?^eDg:Q';
  static const String _linuxUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36';

  final NeteaseAccountService _accountService;
  final Dio _dio;
  final NeteasePlaylistSource _source;

  NeteasePlaylistService({
    required NeteaseAccountService accountService,
    Dio? dio,
    NeteasePlaylistSource? source,
  })  : _accountService = accountService,
        _dio = dio ?? _createDio(accountService),
        _source = source ?? NeteasePlaylistSource();

  static Dio _createDio(NeteaseAccountService accountService) {
    final dio = Dio(BaseOptions(
      headers: {
        'User-Agent': _linuxUserAgent,
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
        'Accept': 'application/json, text/plain, */*',
      },
      connectTimeout: AppConstants.networkConnectTimeout,
      receiveTimeout: AppConstants.networkReceiveTimeout,
    ));
    dio.interceptors.add(NeteaseAuthInterceptor(accountService));
    return dio;
  }

  Future<List<NeteasePlaylistInfo>> getPlaylists() async {
    final userId = await _getRequiredUserId();

    final data = await _postLinuxApi(
      path: 'user/playlist',
      payload: {
        'uid': userId,
        'limit': 1000,
        'offset': 0,
      },
    );
    _ensureSuccess(data, fallbackCode: 'LOAD_FAILED');

    final rawPlaylists = data['playlist'] as List? ?? const [];
    return rawPlaylists
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final creator = item['creator'] as Map<String, dynamic>?;
          return NeteasePlaylistInfo(
            playlistId: item['id']?.toString() ?? '',
            title: item['name'] as String? ?? '',
            trackCount: (item['trackCount'] as num?)?.toInt() ?? 0,
            thumbnailUrl: item['coverImgUrl'] as String?,
            creatorId: creator?['userId']?.toString(),
            creatorName: creator?['nickname'] as String?,
            isMine: creator?['userId']?.toString() == userId,
          );
        })
        .where((item) => item.playlistId.isNotEmpty)
        .toList();
  }

  Future<List<NeteasePlaylistInfo>> getWritablePlaylists() async {
    final playlists = await getPlaylists();
    return playlists.where((playlist) => playlist.isMine).toList();
  }

  Future<NeteasePlaylistDetail> getPlaylistDetail(String playlistId) async {
    final data = await _postLinuxApi(
      path: 'v6/playlist/detail',
      payload: {'id': playlistId},
    );
    _ensureSuccess(data, fallbackCode: 'DETAIL_FAILED');

    final playlist = data['playlist'] as Map<String, dynamic>? ?? const {};
    final trackIds = (playlist['trackIds'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => item['id'])
        .whereType<num>()
        .map((id) => id.toInt())
        .toList();

    List<Map<String, dynamic>> tracks = [];
    if (trackIds.isNotEmpty) {
      tracks = await _fetchTrackDetails(trackIds);
    }

    if (tracks.isEmpty) {
      try {
        final imported =
            await _source.fetchPlaylist(canonicalPlaylistUrl(playlistId));
        tracks = imported.tracks.map((track) {
          return <String, dynamic>{
            'sourceId': track.sourceId,
            'title': track.title,
            'artist': track.artists.join(', '),
            'durationMs': track.duration?.inMilliseconds,
          };
        }).toList();
      } catch (_) {
        // Keep authenticated detail metadata even if public import fallback fails.
      }
    }

    final creator = playlist['creator'] as Map<String, dynamic>?;
    return NeteasePlaylistDetail(
      playlistId: playlistId,
      title: playlist['name'] as String? ?? '',
      description: playlist['description'] as String?,
      thumbnailUrl: playlist['coverImgUrl'] as String?,
      ownerId: creator?['userId']?.toString(),
      ownerName: creator?['nickname'] as String?,
      tracks: tracks,
    );
  }

  Future<String> createPlaylist({
    required String title,
    bool isPrivate = false,
  }) async {
    final data = await _postLinuxApi(
      path: 'playlist/create',
      payload: {
        'name': title,
        if (isPrivate) 'privacy': '10',
      },
    );
    _ensureSuccess(data, fallbackCode: 'CREATE_FAILED');

    final playlist = data['playlist'] as Map<String, dynamic>? ?? const {};
    final playlistId = playlist['id']?.toString() ?? data['id']?.toString();
    if (playlistId == null || playlistId.isEmpty) {
      throw NeteasePlaylistException(
        code: 'CREATE_FAILED',
        message: t.remote.error.unknown(code: 'CREATE_FAILED'),
      );
    }

    return playlistId;
  }

  Future<Set<String>> getTrackIdsInPlaylist(
    String playlistId, {
    Set<String>? targetTrackIds,
  }) async {
    final data = await _postLinuxApi(
      path: 'v6/playlist/detail',
      payload: {'id': playlistId},
    );
    _ensureSuccess(data, fallbackCode: 'DETAIL_FAILED');

    final playlist = data['playlist'] as Map<String, dynamic>? ?? const {};
    final rawTrackIds = playlist['trackIds'] as List? ?? const [];
    final trackIds = rawTrackIds
        .whereType<Map<String, dynamic>>()
        .map((item) => item['id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();

    if (targetTrackIds == null) return trackIds;
    return trackIds.intersection(targetTrackIds);
  }

  Future<void> addTracksToPlaylist(
      String playlistId, List<String> trackIds) async {
    final normalizedIds = normalizeTrackIds(trackIds);
    if (normalizedIds.isEmpty) return;
    await _manipulateTracks(
      playlistId: playlistId,
      trackIds: normalizedIds,
      operation: 'add',
    );
  }

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    final normalizedIds = normalizeTrackIds(trackIds);
    if (normalizedIds.isEmpty) return;

    final playlists = await getPlaylists();
    final targetPlaylist = playlists
        .where((playlist) => playlist.playlistId == playlistId)
        .cast<NeteasePlaylistInfo?>()
        .firstWhere((playlist) => playlist != null, orElse: () => null);
    final shouldRemapNotFoundAsPermission = targetPlaylist?.isMine == false;

    await _manipulateTracks(
      playlistId: playlistId,
      trackIds: normalizedIds,
      operation: 'del',
      remapNotFoundAsPermission: shouldRemapNotFoundAsPermission,
    );
  }

  Future<void> _manipulateTracks({
    required String playlistId,
    required List<String> trackIds,
    required String operation,
    bool remapNotFoundAsPermission = false,
  }) async {
    final data = await _postLinuxApi(
      path: 'playlist/manipulate/tracks',
      payload: {
        'trackIds': trackIds,
        'pid': playlistId,
        'op': operation,
      },
    );

    final code = data['code'];
    final message = data['message']?.toString() ?? '';
    final normalizedMessage = message.toLowerCase();
    final looksLikeNotOwnedDeleteFailure = remapNotFoundAsPermission &&
        operation == 'del' &&
        (normalizedMessage.contains('playlist not exist') ||
            normalizedMessage.contains('playlist does not exist') ||
            normalizedMessage.contains('歌单不存在'));

    if (looksLikeNotOwnedDeleteFailure) {
      throw NeteasePlaylistException(
        code: 'PERMISSION_DENIED',
        message: t.remote.error.noPermission,
      );
    }

    _ensureSuccess(data, fallbackCode: code?.toString() ?? 'UPDATE_FAILED');
  }

  static String canonicalPlaylistUrl(String playlistId) {
    return 'https://music.163.com/playlist?id=$playlistId';
  }

  @visibleForTesting
  static List<String> normalizeTrackIds(Iterable<String?> trackIds) {
    return trackIds
        .map((id) => id?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  @visibleForTesting
  static Set<String> extractTrackIds(Iterable<Map<String, dynamic>> tracks) {
    return tracks
        .map((track) => track['sourceId']?.toString().trim())
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();
  }

  Future<List<Map<String, dynamic>>> _fetchTrackDetails(
      List<int> trackIds) async {
    final tracks = <Map<String, dynamic>>[];
    const batchSize = 400;

    for (var i = 0; i < trackIds.length; i += batchSize) {
      final batchIds = trackIds.skip(i).take(batchSize).toList();
      final songIds = batchIds.map((id) => {'id': id}).toList();
      final data = await _postLinuxApi(
        path: 'v3/song/detail',
        payload: {'c': jsonEncode(songIds)},
      );
      _ensureSuccess(data, fallbackCode: 'TRACK_DETAIL_FAILED');
      final songs = data['songs'] as List? ?? const [];
      tracks.addAll(songs.whereType<Map<String, dynamic>>().map((song) {
        final albumData = song['al'] as Map<String, dynamic>?;
        final artists = (song['ar'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((artist) => artist['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .join(', ');
        return <String, dynamic>{
          'sourceId': song['id']?.toString(),
          'title': song['name']?.toString() ?? '',
          'artist': artists,
          'durationMs': (song['dt'] as num?)?.toInt(),
          'thumbnailUrl': albumData?['picUrl']?.toString(),
        };
      }));
    }

    return tracks;
  }

  Future<Map<String, dynamic>> _postLinuxApi({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final rawCookieString = await _accountService.getAuthCookieString();
    if (rawCookieString == null || rawCookieString.isEmpty) {
      throw const NeteasePlaylistException(
        code: 'NOT_LOGGED_IN',
        message: 'Not logged in',
      );
    }

    final sanitizedCookies = rawCookieString
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) => !part.toLowerCase().startsWith('os='))
        .join('; ');

    final response = await _dio.post(
      _linuxApiBase,
      data: {'eparams': _encryptLinuxApiPayload(path, payload)},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        headers: {
          'User-Agent': _linuxUserAgent,
          'Referer': '$_musicBase/',
          'Cookie': 'os=linux; $sanitizedCookies',
          'X-Real-IP': '118.88.88.88',
        },
      ),
    );

    return _parseResponse(response.data);
  }

  String _encryptLinuxApiPayload(String path, Map<String, dynamic> payload) {
    final body = jsonEncode({
      'method': 'POST',
      'url': '$_musicBase/api/$path',
      'params': payload,
    });

    final keyBytes = Uint8List.fromList(utf8.encode(_linuxApiKey));
    final cipher = ECBBlockCipher(AESEngine());
    final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher)
      ..init(
        true,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(keyBytes),
          null,
        ),
      );

    final encrypted =
        paddedCipher.process(Uint8List.fromList(utf8.encode(body)));
    return encrypted
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  Future<String> _getRequiredUserId() async {
    final account = await _accountService.getCurrentAccount();
    final userId = account?.userId;
    if (userId == null || userId.isEmpty) {
      throw const NeteasePlaylistException(
        code: 'NOT_LOGGED_IN',
        message: 'Not logged in',
      );
    }
    return userId;
  }

  void _ensureSuccess(
    Map<String, dynamic> data, {
    required String fallbackCode,
  }) {
    final code = data['code'];
    if (code == 200) return;

    throw NeteasePlaylistException(
      code: code?.toString() ?? fallbackCode,
      message: data['message']?.toString() ??
          t.remote.error.unknown(code: code?.toString() ?? fallbackCode),
    );
  }

  Map<String, dynamic> _parseResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    throw const NeteasePlaylistException(
      code: 'INVALID_RESPONSE',
      message: 'Invalid NetEase response format',
    );
  }
}
