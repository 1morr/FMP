import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/legacy_import/remote_playlist_url.dart';

// 網址辨識的表格測試。期望值逐條取自官方插件自己的單元測試（fmp-plugins repo，目前版本如下）：
// - bilibili 1.10.0：`bilibili/test/import_playlist.test.js` 的 `playlistFromUrl: every accepted
//   form` 與 `anything else is null`（規則在 `bilibili/src/plugin.js` 的 `playlistFromUrl`）；
// - youtube 1.6.0：`youtube/test/import_playlist.test.js` 的 `playlist urls in every accepted
//   form`、`Mix urls…`、`anything else is null`（規則在 `youtube/src/playlist.js`）；
// - netease 1.7.0：`netease/test/import_playlist.test.js` 的 `every accepted form of a playlist
//   url`、`anything else is null`、`a 163cn.tv short url…`（規則在 `netease/src/plugin.js`）。
// 插件改了 `playlistFromUrl` 的輸出形狀時，回頭改 `remote_playlist_url.dart` 與這個檔案。
// 這裡只認不需要連網的形式，所以短網址 `163cn.tv` 的期望是 null（插件要發一個請求才認得）。

void main() {
  const bilibiliFid = '4026748432';
  const youtubePlaylist = 'PLjxrf2q8roU23XGwz3Km7sQZFTdB996iG';
  const neteaseId = '19723756';

  void accepts(String plugin, String id, List<String> urls) {
    for (final url in urls) {
      test('$plugin accepts ${url.trim()}', () {
        expect(
          recognizeRemotePlaylistUrl(url),
          RecognizedRemote(pluginId: plugin, remoteId: id),
        );
      });
    }
  }

  void rejects(List<String> urls) {
    for (final url in urls) {
      test('rejects "$url"', () {
        expect(recognizeRemotePlaylistUrl(url), isNull);
      });
    }
  }

  group('bilibili 1.10.0', () {
    accepts('bilibili', bilibiliFid, [
      'https://space.bilibili.com/8047632/favlist?fid=$bilibiliFid&ftype=create',
      'https://space.bilibili.com/8047632/favlist?ftype=create&fid=$bilibiliFid',
      'https://www.bilibili.com/medialist/detail/ml$bilibiliFid',
      'https://www.bilibili.com/medialist/detail/ml$bilibiliFid?type=1',
      'https://www.bilibili.com/list/ml$bilibiliFid',
      'https://m.bilibili.com/medialist/detail/ml$bilibiliFid',
      'https://bilibili.com/medialist/play/ml$bilibiliFid',
      'www.bilibili.com/medialist/detail/ml$bilibiliFid',
      '  http://WWW.bilibili.com./medialist/detail/ml$bilibiliFid#top  ',
      'https://www.bilibili.com:443/medialist/detail/ml$bilibiliFid',
    ]);
    rejects([
      '',
      'not a url',
      'ml$bilibiliFid',
      'https://space.bilibili.com/8047632/favlist',
      'https://space.bilibili.com/8047632/favlist?fid=abc',
      'https://space.bilibili.com/8047632/favlist?fid=',
      'https://www.bilibili.com/video/BV1xx411c79H',
      'https://www.bilibili.com/medialist/detail/ml',
      'https://www.bilibili.com/medialist/detail/xml123',
      'https://www.bilibili.com/medialist/detail/ml0',
      'https://evil.example.com/medialist/detail/ml$bilibiliFid',
      'https://bilibili.com.evil.example/medialist/detail/ml$bilibiliFid',
      'https://attacker.example/?u=www.bilibili.com&fid=$bilibiliFid',
      'https://www.bilibili.com@evil.example/medialist/detail/ml$bilibiliFid',
      'ftp://www.bilibili.com/medialist/detail/ml$bilibiliFid',
      'https://b23.tv/ml$bilibiliFid',
      'https://www.bilibili.com/medialist/detail/ml${'9' * 19}',
    ]);
  });

  group('youtube 1.6.0', () {
    accepts('youtube', youtubePlaylist, [
      'https://www.youtube.com/playlist?list=$youtubePlaylist',
      'https://youtube.com/playlist?list=$youtubePlaylist&si=abc',
      'https://m.youtube.com/playlist?list=$youtubePlaylist',
      'https://music.youtube.com/playlist?list=$youtubePlaylist',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=$youtubePlaylist&index=3',
      'https://youtu.be/dQw4w9WgXcQ?list=$youtubePlaylist',
      'www.youtube.com/playlist?list=$youtubePlaylist',
      '  http://www.youtube.com./playlist?list=$youtubePlaylist  ',
    ]);
    // Mix（插件回 mixSeed）不是歌單：舊版的 Mix 歌單走 `isMix`，不經網址辨識。
    rejects([
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ',
      'https://www.youtube.com/playlist?list=RDdQw4w9WgXcQ',
      'mix:dQw4w9WgXcQ',
      '  MIX: dQw4w9WgXcQ ',
      'https://www.youtube.com/playlist?list=RD',
    ]);
    rejects([
      '',
      'not a url',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://www.youtube.com/playlist',
      'https://www.youtube.com/playlist?list=',
      'https://evil.example.com/playlist?list=$youtubePlaylist',
      'https://youtube.com.evil.example/playlist?list=$youtubePlaylist',
      'https://attacker.example/?u=youtube.com&list=$youtubePlaylist',
      'ftp://www.youtube.com/playlist?list=$youtubePlaylist',
      'https://www.youtube.com/playlist?list=bad id!',
      'https://www.youtube.com/playlist?list=${'a' * 101}',
    ]);
  });

  group('netease 1.7.0', () {
    accepts('netease', neteaseId, [
      'https://music.163.com/#/playlist?id=$neteaseId',
      'https://music.163.com/#/playlist?id=$neteaseId&userid=1',
      'https://music.163.com/playlist?id=$neteaseId',
      'https://music.163.com/playlist?id=$neteaseId&uct2=abc',
      'https://music.163.com/m/playlist?id=$neteaseId',
      'https://y.music.163.com/m/playlist?app_version=9.0&id=$neteaseId&dlt=0846',
      'https://music.163.com/#/my/m/music/playlist?id=$neteaseId',
      'https://music.163.com/playlist/$neteaseId/123456/?userid=123456',
      'https://y.music.163.com/m/playlist/$neteaseId',
      'music.163.com/#/playlist?id=$neteaseId',
      '  http://MUSIC.163.com./#/playlist?id=$neteaseId  ',
      'https://music.163.com:443/playlist?id=$neteaseId',
    ]);
    rejects([
      '',
      'not a url',
      neteaseId,
      'https://music.163.com/',
      'https://music.163.com/#/discover',
      'https://music.163.com/#/song?id=139774',
      'https://music.163.com/song?id=139774',
      'https://music.163.com/#/playlist',
      'https://music.163.com/#/playlist?id=abc',
      'https://music.163.com/#/playlist?id=0',
      'https://music.163.com/#/album?id=$neteaseId',
      'https://evil.example.com/#/playlist?id=$neteaseId',
      'https://music.163.com.evil.example/playlist?id=$neteaseId',
      'https://attacker.example/?u=music.163.com/playlist&id=$neteaseId',
      'https://music.163.com@evil.example/playlist?id=$neteaseId',
      'ftp://music.163.com/playlist?id=$neteaseId',
      'https://163cn.tv.evil.example/abc',
      'https://music.163.com/playlist?id=${'9' * 19}',
      // 短網址要連網才認得（插件發一個 GET），轉換器不連網，認不出。
      'https://163cn.tv/AbCdEf',
    ]);
  });

  group('mutations', () {
    test('only the whitespace around the url changes nothing', () {
      expect(
        recognizeRemotePlaylistUrl(
          'https://music.163.com/playlist?id=$neteaseId',
        ),
        recognizeRemotePlaylistUrl(
          '\n\thttps://music.163.com/playlist?id=$neteaseId \n',
        ),
      );
    });

    test('a plugin-specific rejection url is another plugin playlist here', () {
      // bilibili／netease 的插件測試用這兩條當「別家的網址」期望 null；轉換器三家一起試，歸 youtube。
      for (final url in [
        'https://www.youtube.com/playlist?list=PLhtml5abc',
        'https://www.youtube.com/playlist?list=PL$neteaseId',
      ]) {
        expect(
          recognizeRemotePlaylistUrl(url)!.pluginId,
          'youtube',
          reason: url,
        );
      }
    });

    test('a url of one plugin is not taken by another', () {
      expect(
        recognizeRemotePlaylistUrl(
          'https://www.youtube.com/playlist?list=$youtubePlaylist&fid=$bilibiliFid',
        )!.pluginId,
        'youtube',
      );
    });
  });
}
