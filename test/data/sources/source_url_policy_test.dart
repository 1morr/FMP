import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/netease_source.dart';
import 'package:fmp/data/sources/playlist_import/qq_music_playlist_source.dart';
import 'package:fmp/data/sources/playlist_import/spotify_playlist_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/source_url_policy.dart';
import 'package:fmp/data/sources/youtube_source.dart';

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
        NeteaseSource(
          dio: Dio(),
        ).isPlaylistUrl('https://attacker.example/?u=music.163.com'),
        isFalse,
      );
      // 比對「被接受的網址」整個清單，一次紅就看得到每一個被放行的案例。
      final youtube = YouTubeSource(dio: Dio());
      final bilibili = BilibiliSource(dio: Dio(), liveDio: Dio());
      expect([
        ...const [
          'https://attacker.example/?u=youtube.com&list=x',
          'https://youtube.com.attacker.example/playlist?list=x',
          'https://attacker.example/youtu.be/playlist',
          'attacker.example/?u=youtube.com&list=x',
        ].where(youtube.isPlaylistUrl),
        ...const [
          'https://attacker.example/?u=space.bilibili.com&fid=123',
          'https://bilibili.com.attacker.example/medialist/detail/ml123',
          'https://attacker.example/favlist',
        ].where(bilibili.isPlaylistUrl),
      ], isEmpty);
    });

    test('YouTube isPlaylistUrl accepts playlist shapes on YouTube hosts', () {
      final source = YouTubeSource(dio: Dio());
      for (final url in const [
        'https://www.youtube.com/playlist?list=PLabc',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc',
        'https://music.youtube.com/playlist?list=PLabc',
        'https://youtu.be/dQw4w9WgXcQ?list=PLabc',
        // 不帶協定的輸入當成 https 讀（舊資料可能這樣存著）。
        'www.youtube.com/playlist?list=PLabc',
      ]) {
        expect(source.isPlaylistUrl(url), isTrue, reason: url);
      }
      expect(
        source.isPlaylistUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isFalse,
        reason: 'a video URL without list is not a playlist',
      );
    });

    test(
      'Bilibili isPlaylistUrl accepts favorites shapes on Bilibili hosts',
      () {
        final source = BilibiliSource(dio: Dio(), liveDio: Dio());
        for (final url in const [
          'https://space.bilibili.com/12345/favlist?fid=67890',
          'https://www.bilibili.com/medialist/detail/ml67890',
          // 不帶協定的輸入當成 https 讀（舊資料可能這樣存著）。
          'space.bilibili.com/12345/favlist?fid=67890',
        ]) {
          expect(source.isPlaylistUrl(url), isTrue, reason: url);
        }
        expect(
          source.isPlaylistUrl('https://b23.tv/abc'),
          isFalse,
          reason: 'b23.tv short links stay unsupported',
        );
      },
    );

    test('SourceManager routes a YouTube playlist whose id contains ml + digit '
        'to YouTube', () {
      // 與預設 SourceManager() 同樣的順序：Bilibili → YouTube → Netease。
      final manager = SourceManager(
        sources: [
          BilibiliSource(dio: Dio(), liveDio: Dio()),
          YouTubeSource(dio: Dio()),
          NeteaseSource(dio: Dio()),
        ],
      );
      addTearDown(manager.dispose);

      expect(
        manager
            .playlistParsingSourceForUrl(
              'https://www.youtube.com/playlist?list=PLhtml5abc',
            )
            ?.sourceType,
        SourceIds.youtube,
      );
    });

    test('withDefaultHttpsScheme only prefixes scheme-less input', () {
      expect(
        SourceUrlPolicy.withDefaultHttpsScheme('www.youtube.com/playlist'),
        'https://www.youtube.com/playlist',
      );
      expect(
        SourceUrlPolicy.withDefaultHttpsScheme('http://www.bilibili.com/x'),
        'http://www.bilibili.com/x',
      );
      expect(
        SourceUrlPolicy.withDefaultHttpsScheme('ftp://www.youtube.com/x'),
        'ftp://www.youtube.com/x',
        reason: 'a non-http scheme is kept so the host check rejects it',
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
        NeteaseSource(
          dio: Dio(),
        ).isPlaylistUrl('https://music.163.com/song?id=123'),
        isFalse,
      );
    });

    test('canHandle accepts short links for redirect resolution', () {
      expect(
        SpotifyPlaylistSource().canHandle('https://spotify.link/abc'),
        isTrue,
      );
      expect(QQMusicPlaylistSource().canHandle('https://url.cn/abc'), isTrue);
      expect(
        NeteaseSource(dio: Dio()).isPlaylistUrl('https://163cn.tv/abc'),
        isTrue,
      );
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
      // 網易雲短鏈由 NeteaseSource._resolveShortUrl 解析（匯入對話框把所有網易雲
      // URL 都交給內部來源），所以 SSRF 迴歸釘在這裡而不是外部匯入源上。
      final source = NeteaseSource(dio: dio);

      await expectLater(
        source.parsePlaylist('https://163cn.tv/abc'),
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
