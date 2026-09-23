/// 幾個「只准某些檔案碰」的呼叫，寫成一張擁有權表。
///
/// 每一列都是一個搬錯地方不會有任何訊號的東西：直播 API 散回音源與電台、
/// 搜尋頁自己去查音源、標題列在兩個地方各畫一次、歌單改完各自失效 provider。
/// 這些原本分散在好幾個檔案裡，各自用「某檔含／不含某字串」釘著，只看得到
/// 自己點名的那幾個檔案，第四個地方長出來就看不見。
///
/// **比的是集合。** 全 `lib/`（或列上寫的範圍）裡符合樣式的檔案，要剛好等於
/// 那一列的擁有者；多一個、少一個都紅。換行、改名、註解都不紅 —— 兩個方向都由
/// 本檔最後兩條測試示範。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

class _Ownership {
  const _Ownership({
    required this.why,
    required this.pattern,
    required this.owners,
    this.scope = 'lib/',
  });

  /// 為什麼只有這些檔案可以碰。
  final String why;
  final String pattern;
  final Set<String> owners;

  /// 只看這個前綴底下的檔案。
  final String scope;
}

const _table = <String, _Ownership>{
  'bilibili live API': _Ownership(
    why:
        '直播的端點與標頭只住在 live client；音源與電台透過它說話，不各自組'
        '一份請求。直播用的 Dio 可以由音源建好注入，請求本身不行',
    pattern: r'/room/v1/|/xlive/|\bbilibiliLiveHeaders\s*\(',
    owners: {
      'lib/data/sources/bilibili_live_client.dart',
      'lib/data/sources/source_http_policy.dart',
    },
  ),
  'source manager in the UI': _Ownership(
    why:
        '搜尋頁載分 P 走 SearchNotifier.loadVideoPagesForTrack；UI 直接查音源'
        '等於把音源身分帶回 UI。匯入對話框要依網址挑匯入音源，是唯一的例外',
    pattern: r'\bsourceManagerProvider\b',
    scope: 'lib/ui/',
    owners: {'lib/ui/pages/library/widgets/import_playlist_dialog.dart'},
  ),
  'source calls in the UI': _Ownership(
    why: '分 P 與帳號標頭是服務層的事，UI 不直接呼叫',
    pattern: r'\bgetVideoPages\s*\(|\bbuildAuthHeaders\s*\(',
    scope: 'lib/ui/',
    owners: {},
  ),
  'custom title bar': _Ownership(
    why:
        '桌面標題列由 app 外層包一次；頁面自己再放一個，Windows 上就會出現兩條'
        '可拖曳的標題列',
    pattern: r'\bCustomTitleBar\s*\(',
    owners: {'lib/app.dart', 'lib/ui/widgets/app_bars/custom_title_bar.dart'},
  ),
  'playlist invalidation': _Ownership(
    why:
        '改動歌單的入口透過 libraryInvalidationCoordinatorProvider 失效；'
        '各自失效就會漏掉封面或詳情。首頁「重試」只重新載入清單，不是改動',
    pattern:
        r'\bref\s*\.\s*invalidate\s*\(\s*(?:allPlaylistsProvider|playlistDetailProvider|playlistCoverProvider|playlistCoverMapProvider)\b',
    owners: {
      'lib/providers/library/library_invalidation_coordinator.dart',
      'lib/ui/pages/home/home_page.dart',
    },
  ),
};

/// [sourcesByPath] 裡，在 [scope] 底下、註解之外符合 [pattern] 的檔案。
Set<String> filesMatching(
  Map<String, String> sourcesByPath,
  String pattern, {
  String scope = 'lib/',
}) {
  final regex = RegExp(pattern);
  return {
    for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
      if (path.startsWith(scope) && regex.hasMatch(stripDartComments(source)))
        path,
  };
}

void main() {
  group('call-site ownership', () {
    late Map<String, String> sources;

    setUpAll(() {
      sources = {
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !entity.path.endsWith('.g.dart'))
            entity.path.replaceAll(r'\', '/'): entity.readAsStringSync(),
      };
      // 掃描本身要有作用 —— 路徑寫錯時每一列都會是空集合。
      expect(sources.length, greaterThan(300));
    });

    for (final MapEntry(key: name, value: row) in _table.entries) {
      test('$name stays with its owners', () {
        expect(
          filesMatching(sources, row.pattern, scope: row.scope),
          equals(row.owners),
          reason: '${row.why}. Update _table in this file if that changed.',
        );
      });
    }

    test('every owner still exists', () {
      for (final row in _table.values) {
        for (final path in row.owners) {
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    });
  });

  group('the ownership detector', () {
    test('a call outside the owners turns a row red', () {
      const sources = {
        'lib/data/sources/bilibili_live_client.dart':
            "final url = '\$liveApiBase/room/v1/Room/playUrl';",
        'lib/services/radio/radio_source.dart':
            "final url = '\$base/room/v1/Room/playUrl';",
        'lib/ui/pages/player/player_page.dart': '''
return Column(children: [
  const CustomTitleBar
      (),
]);
''',
        'lib/ui/pages/library/playlist_detail_page.dart':
            'ref.invalidate(playlistDetailProvider(id));',
      };

      expect(
        filesMatching(sources, _table['bilibili live API']!.pattern),
        contains('lib/services/radio/radio_source.dart'),
      );
      expect(filesMatching(sources, _table['custom title bar']!.pattern), {
        'lib/ui/pages/player/player_page.dart',
      });
      expect(filesMatching(sources, _table['playlist invalidation']!.pattern), {
        'lib/ui/pages/library/playlist_detail_page.dart',
      });
    });

    test('scope, comments, lookalikes and line breaks do not', () {
      const sources = {
        // 範圍外：服務層本來就該查音源。
        'lib/services/search/search_service.dart':
            'final manager = ref.read(sourceManagerProvider);\n'
            'return source.getVideoPages(track.sourceId);',
        'lib/ui/pages/search/search_page.dart': '''
// 以前直接 ref.read(sourceManagerProvider) 再 getVideoPages(...)。
final pages = await ref
    .read(searchProvider.notifier)
    .loadVideoPagesForTrack(track);
final coordinator = ref.read(libraryInvalidationCoordinatorProvider);
''',
      };

      final uiSourceManager = _table['source manager in the UI']!;
      final uiSourceCalls = _table['source calls in the UI']!;
      expect(
        filesMatching(
          sources,
          uiSourceManager.pattern,
          scope: uiSourceManager.scope,
        ),
        isEmpty,
      );
      expect(
        filesMatching(
          sources,
          uiSourceCalls.pattern,
          scope: uiSourceCalls.scope,
        ),
        isEmpty,
      );
      expect(
        filesMatching(sources, _table['playlist invalidation']!.pattern),
        isEmpty,
      );
    });
  });
}
