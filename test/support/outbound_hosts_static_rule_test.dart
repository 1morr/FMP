/// `lib/` 裡寫死的每一個主機都要在 [_hosts] 上有用途；做 DNS 解析的目標要在
/// [_dnsLookups] 上。
///
/// 每 15 秒解析三家公共 DNS 的輪詢，進 repo 時沒有 PR、沒有 issue、沒有任何測試
/// 提到那三個名字 —— 它只存在於一個 `static const` 裡。這條規則讓下一個寫死的
/// 主機必須在這裡出現一次，寫明它拿來做什麼。
///
/// **比的是集合，不是字串存在。** 實際掃到的主機集合要等於名單的鍵，多一個、
/// 少一個都紅；主機換行、改常數名、重排名單都不紅 —— 兩個方向都由本檔最後兩條
/// 測試示範。
///
/// 看不到的：從 API 回應拿到的網址（串流、圖片 CDN、GitHub release 的下載
/// 連結）、套件自己連的主機（`youtube_explode_dart`），以及不帶 `http(s)://` 拼出來
/// 的網址（`Uri.https(...)`，目前沒有）。名單記的是「程式碼自己決定要連誰」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

/// 主機 → 用途。只出現在標頭、提示文字或「點了才開瀏覽器」的連結也列，
/// 用途寫「不連線」—— 否則下一個人得自己去確認它不是一條連線。
const _hosts = <String, String>{
  'api.bilibili.com':
      'Bilibili 搜尋、串流、排行榜、收藏夾與帳號；啟動時驗證帳號狀態'
      '（`accountStatusCheckProvider`），不能關閉',
  'passport.bilibili.com':
      'Bilibili 登入頁；啟動時刷新 Cookie（`accountCookieRefreshProvider`），不能關閉',
  'www.bilibili.com':
      'Bilibili 登入頁、Cookie 刷新要讀的 correspond 頁、Origin / Referer 標頭',
  'bilibili.com': 'Bilibili 登入頁（WebView）與 Cookie 網域',
  'api.live.bilibili.com': '電台直播狀態與直播間資訊（輪詢見 periodic timer 名單）',
  'live.bilibili.com': '直播間網址與 Referer 標頭；在瀏覽器開直播間（點了才開）',
  'search.bilibili.com': '不連線：搜尋請求的 Origin / Referer 標頭',
  'space.bilibili.com': '不連線：UP 主頁與收藏夾網址，點了才在瀏覽器開，或當匯入網址',
  'www.youtube.com': 'YouTube InnerTube API、登入、帳號與歌單；啟動時驗證帳號狀態，不能關閉',
  'youtube.com': 'YouTube 登入頁（WebView）允許的網域',
  'google.com': 'YouTube 登入頁（WebView）允許的網域',
  'accounts.google.com': 'YouTube 登入頁（WebView）；登出時清它的 Cookie',
  'i.ytimg.com': 'YouTube 縮圖',
  'music.163.com': '網易雲搜尋、歌詞、歌單、登入與帳號；啟動時驗證帳號狀態，不能關閉',
  'interface3.music.163.com': '網易雲 eapi（取串流）',
  'lrclib.net': '歌詞搜尋（LRCLIB）',
  'u.y.qq.com': 'QQ 音樂歌詞搜尋',
  'u6.y.qq.com': '匯入 QQ 音樂歌單',
  'y.qq.com': '不連線：匯入 QQ 音樂歌單時的 Referer 標頭',
  'open.spotify.com': '匯入 Spotify 歌單（讀嵌入頁）',
  'api.github.com': '手動檢查更新（設定 > 關於）',
  'github.com': '不連線：授權聲明、LRCLIB 的 User-Agent、啟動失敗頁的 issue 連結',
  'example.com': '不連線：封面網址輸入框的提示文字',
};

/// 呼叫 `InternetAddress.lookup` 的檔案 → 它解析的主機。
///
/// 目標在常數裡、不是 `lookup(` 的字面參數，所以認的是那個檔案裡所有長得像
/// 網域的字串常量。
const _dnsLookups = <String, Set<String>>{
  // 網路狀態偵測，輪詢間隔見 periodic timer 名單。不能關閉：2026-09 決定不改
  // 行為，只把它列出來。
  'lib/services/network/connectivity_service.dart': {
    'dns.google',
    'one.one.one.one',
    'dns.alidns.com',
  },
};

final _urlHost = RegExp(r'https?://([A-Za-z0-9.-]+)');
final _lookupCall = RegExp(r'\bInternetAddress\s*\.\s*lookup\s*\(');
final _domainLiteral = RegExp(r'''['"]((?:[a-z0-9-]+\.)+[a-z]{2,})['"]''');

/// 註解之外寫死的 `http(s)://` 主機。
Set<String> hardcodedHosts(Iterable<String> sources) => {
  for (final source in sources)
    for (final match in _urlHost.allMatches(stripDartComments(source)))
      match.group(1)!.replaceFirst(RegExp(r'\.+$'), ''),
};

/// 做 DNS 解析的檔案 → 那個檔案裡長得像網域的字串常量。
Map<String, Set<String>> dnsLookupTargets(Map<String, String> sourcesByPath) =>
    {
      for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
        if (stripDartComments(source) case final code
            when _lookupCall.hasMatch(code))
          path: {for (final m in _domainLiteral.allMatches(code)) m.group(1)!},
    };

void main() {
  group('outbound hosts', () {
    late Map<String, String> sources;

    setUpAll(() {
      sources = {
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart'))
            entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
      };
    });

    test('every hard-coded host in lib/ is on the list', () {
      // 掃描本身要有作用 —— 路徑寫錯時兩邊都會是空的。
      expect(sources.length, greaterThan(300));
      expect(
        hardcodedHosts(sources.values),
        equals(_hosts.keys.toSet()),
        reason:
            'A hard-coded host was added or removed. Update _hosts in this '
            'file and say what the app uses it for.',
      );
    });

    test('every DNS lookup target is on the list', () {
      expect(
        dnsLookupTargets(sources),
        equals(_dnsLookups),
        reason:
            'InternetAddress.lookup was added somewhere, or its targets '
            'changed. Update _dnsLookups in this file.',
      );
    });

    test('every host says what it is for', () {
      for (final MapEntry(key: host, value: purpose) in _hosts.entries) {
        expect(purpose, isNotEmpty, reason: host);
      }
    });

    test('a new host or lookup target turns the rule red', () {
      const listed = '''
const _base = 'https://api.example.org/v1';
''';
      const withExtra = '''
const _base = 'https://api.example.org/v1';
final _beacon = Uri.parse('https://telemetry.example.net/ping');
''';
      expect(hardcodedHosts([listed]), equals({'api.example.org'}));
      expect(hardcodedHosts([withExtra]), isNot(equals({'api.example.org'})));

      const lookup = '''
const _targets = ['dns.google'];
Future<void> probe() => InternetAddress.lookup(_targets.first);
''';
      const lookupWithExtra = '''
const _targets = ['dns.google', 'probe.example.net'];
Future<void> probe() => InternetAddress.lookup(_targets.first);
''';
      final expected = {
        'lib/a.dart': {'dns.google'},
      };
      expect(dnsLookupTargets({'lib/a.dart': lookup}), equals(expected));
      expect(
        dnsLookupTargets({'lib/a.dart': lookupWithExtra}),
        isNot(equals(expected)),
      );
      expect(
        dnsLookupTargets({'lib/a.dart': lookup, 'lib/b.dart': lookup}),
        isNot(equals(expected)),
        reason: 'a lookup in a new file is a new lookup',
      );
    });

    test('line breaks, renames, comments and reordering do not', () {
      const reformatted = '''
/// 以前打的是 https://legacy.example.com，註解不算。
static const String renamedApiRoot =
    'https://api.example.org'
    '/v1';
// final old = 'https://old.example.com';
''';
      expect(hardcodedHosts([reformatted]), equals({'api.example.org'}));

      const reformattedLookup = '''
// 'commented.example.com' 不算。
const _renamedHosts = [
  'dns.google',
];
Future<void> probe() =>
    InternetAddress
        .lookup(
      _renamedHosts.first,
    );
''';
      expect(
        dnsLookupTargets({'lib/a.dart': reformattedLookup}),
        equals({
          'lib/a.dart': {'dns.google'},
        }),
      );
      expect(
        Map.fromEntries(_hosts.entries.toList().reversed).keys.toSet(),
        equals(_hosts.keys.toSet()),
      );
    });
  });
}
