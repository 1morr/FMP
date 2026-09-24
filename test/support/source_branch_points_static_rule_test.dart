/// `lib/data/sources/` 以外，依具體音源 id 比較或分派的地方，只能變少。
///
/// 這種分支每一處都是「加第四個音源時要記得改」的地方，而漏改不會編譯錯誤：
/// 首頁排行曾經用 `switch` 對三個音源名字取資料、`default` 回 null，設定頁列得出
/// 來的新音源在首頁永遠不出現。改成查表或查能力之後，那一處就不必再改。
///
/// 預算按檔案記錄，而且是等號比較：多了一處會紅（先想能不能改成查
/// `SourceManager` 的能力或以音源 id 為鍵查表）；少了一處也會紅，要把預算一起
/// 降下來，數字才不會留著空間讓別處長回去。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/source_ids.dart';

import 'dart_source.dart';

/// 檔案 → 分支點數。只記錄現況，不代表這些分支都該留著。
const _budget = <String, int>{
  'lib/core/errors/user_message.dart': 1,
  'lib/core/utils/icon_helpers.dart': 3,
  'lib/providers/account/account_provider.dart': 3,
  'lib/services/account/source_auth_context.dart': 3,
  'lib/services/lyrics/lyrics_auto_match_service.dart': 1,
  'lib/services/platform/url_launcher_service.dart': 8,
  'lib/services/radio/radio_controller.dart': 1,
  'lib/ui/pages/player/player_page.dart': 3,
  'lib/ui/pages/settings/account_management_page.dart': 3,
  'lib/ui/pages/settings/widgets/account_playlists_sheet.dart': 3,
  'lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart': 3,
  'lib/ui/widgets/panels/track_detail_panel.dart': 4,
};

/// 分支點：拿音源 id 做 `==` / `!=`、`case`，或當 switch 運算式的分支。
///
/// 以音源 id 為鍵的 map（`{SourceIds.bilibili: ...}`）不算：那是查表，找不到
/// 的鍵有明確的 null，不會像 `default` 一樣被靜默吞掉。
List<RegExp> _branchPatterns({required bool includeLiterals}) {
  final ids = SourceIds.values.join('|');
  final constant = r'SourceIds\s*\.\s*(?:' + ids + r')\b';
  final literal = '[\'"](?:$ids)[\'"]';
  final id = includeLiterals ? '(?:$constant|$literal)' : constant;
  return [
    RegExp('[!=]=\\s*$id'),
    RegExp('$id\\s*[!=]='),
    RegExp('\\bcase\\s+$id'),
    RegExp('$id\\s*=>'),
  ];
}

/// 每個檔案的分支點數，只列出大於零的。
///
/// 歌詞來源也有一個叫 `netease` 的 id，所以檔名含 `lyrics` 的檔案只算
/// `SourceIds.` 常數，不算字面值 —— 那裡的 `'netease'` 指的是歌詞來源。
Map<String, int> sourceBranchPoints(Map<String, String> sourcesByPath) {
  final withLiterals = _branchPatterns(includeLiterals: true);
  final constantsOnly = _branchPatterns(includeLiterals: false);
  return {
    for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
      if (!path.startsWith('lib/data/sources/') && !path.endsWith('.g.dart'))
        if ((path.split('/').last.contains('lyrics')
                    ? constantsOnly
                    : withLiterals)
                .map((p) => p.allMatches(stripDartComments(source)).length)
                .fold(0, (a, b) => a + b)
            case final count when count > 0)
          path: count,
  };
}

void main() {
  test('per-source branches outside the adapters only go down', () {
    final sources = <String, String>{
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.path.replaceAll('\\', '/'): entity.readAsStringSync(),
    };
    // 掃描本身要有作用。
    expect(sources.length, greaterThan(100));

    expect(
      sourceBranchPoints(sources),
      equals(_budget),
      reason:
          'A file gained or lost a branch on a concrete source id. Gained: '
          'ask SourceManager for a capability or look the source up in a map '
          'keyed by source id instead. Lost: lower _budget in this file.',
    );
  });

  group('the branch counter', () {
    test('counts comparisons, cases and switch arms', () {
      const source = '''
bool a(Track t) => t.sourceType == SourceIds.bilibili;
bool b(String s) => SourceIds.netease != s;
String c(String s) {
  switch (s) {
    case SourceIds.youtube:
      return 'yt';
  }
  return switch (s) { SourceIds.netease => 'ne', _ => '' };
}
''';

      expect(sourceBranchPoints({'lib/services/x.dart': source}), {
        'lib/services/x.dart': 4,
      });
    });

    test('counts a switch on bare source names', () {
      // 首頁排行當初就是這樣寫的。
      const source = '''
List<Track>? pick(String source) {
  switch (source) {
    case 'bilibili':
      return a;
    case "youtube":
      return b;
  }
  return null;
}
''';

      expect(sourceBranchPoints({'lib/ui/pages/home/x.dart': source}), {
        'lib/ui/pages/home/x.dart': 2,
      });
    });

    test('ignores lookups, comments, adapters and lyrics source names', () {
      const lookups = '''
// if (t.sourceType == SourceIds.bilibili) 已改成查表
final adapters = {SourceIds.bilibili: a, SourceIds.youtube: b};
final all = SourceIds.values;
final name = SourceIds.displayNameFor(SourceIds.netease);
final match = type == SourceIds . bilibiliLive;
''';
      const lyrics = '''
String icon(String source) => switch (source) { 'netease' => a, _ => b };
''';
      const adapter = '''
bool mine(String s) => s == SourceIds.bilibili;
''';

      expect(
        sourceBranchPoints({
          'lib/services/x.dart': lookups,
          'lib/ui/pages/lyrics/lyrics_search_sheet.dart': lyrics,
          'lib/data/sources/bilibili_source.dart': adapter,
        }),
        isEmpty,
      );
    });
  });
}
