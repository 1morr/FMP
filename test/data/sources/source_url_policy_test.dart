import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/playlist_import/netease_playlist_source.dart';
import 'package:fmp/data/sources/playlist_import/qq_music_playlist_source.dart';
import 'package:fmp/data/sources/playlist_import/spotify_playlist_source.dart';
import 'package:fmp/data/sources/source_url_policy.dart';

void main() {
  group('source URL validation', () {
    test('canHandle rejects substring host spoofing', () {
      expect(
        SpotifyPlaylistSource().canHandle(
          'http://127.0.0.1:8080/?next=spotify.link',
        ),
        isFalse,
      );
      expect(
        QQMusicPlaylistSource().canHandle(
          'https://attacker.example/?u=y.qq.com',
        ),
        isFalse,
      );
      expect(
        NeteasePlaylistSource().canHandle(
          'https://attacker.example/?u=music.163.com',
        ),
        isFalse,
      );
    });

    test('canHandle rejects trusted hosts when URL is not a playlist', () {
      expect(
        QQMusicPlaylistSource().canHandle('https://y.qq.com/n/ryqq/songDetail'),
        isFalse,
      );
      expect(
        QQMusicPlaylistSource().canHandle(
          'https://y.qq.com/n/ryqq/songDetail?id=123',
        ),
        isFalse,
      );
      expect(
        NeteasePlaylistSource().canHandle('https://music.163.com/song?id=123'),
        isFalse,
      );
    });

    test('canHandle accepts short links for redirect resolution', () {
      expect(
        SpotifyPlaylistSource().canHandle('https://spotify.link/abc'),
        isTrue,
      );
      expect(QQMusicPlaylistSource().canHandle('https://url.cn/abc'), isTrue);
      expect(NeteasePlaylistSource().canHandle('https://163cn.tv/abc'), isTrue);
    });

    test('rejects local and private literal hosts', () {
      for (final url in [
        'http://127.0.0.1:8080/playlist',
        'http://192.168.1.10/playlist',
        'http://169.254.1.1/playlist',
        'http://[::1]/playlist',
        'http://localhost/playlist',
      ]) {
        expect(
          SourceUrlPolicy.parseTrustedHttpUrl(
            url,
            allowedHosts: {Uri.parse(url).host},
          ),
          isNull,
          reason: url,
        );
      }
    });

    test('short-link redirects are not followed to local hosts', () async {
      final dio = Dio();
      final adapter = _RedirectAdapter('http://127.0.0.1:1234/private');
      dio.httpClientAdapter = adapter;
      final source = NeteasePlaylistSource(dio: dio);

      await expectLater(
        source.fetchPlaylist('https://163cn.tv/abc'),
        throwsA(anything),
      );

      expect(adapter.requestedHosts, everyElement('163cn.tv'));
      expect(adapter.requestedHosts, isNot(contains('127.0.0.1')));
    });

    // download_service.dart 的重定向循环用这个判定挡「公网跳内网」——
    // 每一跳都带着音源的 auth header，跳错地方就是把凭据送进内网或
    // 云端 metadata 端点。这里直接钉住分类结果。
    test('isLocalOrPrivateHost classifies loopback, RFC1918 and metadata', () {
      for (final host in const [
        'localhost',
        'api.localhost',
        '127.0.0.1',
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.1.1',
        '169.254.169.254', // 云端 metadata
        '100.64.0.1', // CGNAT
        '0.0.0.0',
        '::1',
      ]) {
        expect(
          SourceUrlPolicy.isLocalOrPrivateHost(host),
          isTrue,
          reason: '$host should be treated as local or private',
        );
      }

      for (final host in const [
        'api.bilibili.com',
        'music.163.com',
        'rr1---sn-example.googlevideo.com',
        '8.8.8.8',
        '172.32.0.1', // 刚好在 RFC1918 区间之外
        '11.0.0.1',
      ]) {
        expect(
          SourceUrlPolicy.isLocalOrPrivateHost(host),
          isFalse,
          reason: '$host should be reachable',
        );
      }
    });
  });
}

class _RedirectAdapter implements HttpClientAdapter {
  _RedirectAdapter(this.location);

  final String location;
  final requestedHosts = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedHosts.add(options.uri.host);
    return ResponseBody.fromBytes(
      utf8.encode(''),
      302,
      headers: {
        'location': [location],
      },
    );
  }
}
