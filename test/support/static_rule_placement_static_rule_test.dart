/// 讀 `lib/` 原始碼的測試必須自己承認它是一條靜態規則。
///
/// 源碼字串比對是有用的 —— 它抓得到編譯器與行為測試都看不見的東西（少一行
/// `prefetch-playlist`、多一個整包 watch）。問題從來不是它存在，是它藏在一支
/// 叫 `mini_player_test.dart` 的檔案裡：讀者以為那裡有 render 測試，重構的人
/// 以為紅燈是自己弄壞了行為。
///
/// 所以規則是位置與命名，不是禁止：
///
/// - 住在 `test/support/`（跨層規則）或 `test/<層>/static_rules/`（單層規則）。
/// - 檔名以 `_static_rule_test.dart` 結尾。
///
/// **沒有例外清單，也不打算有。** 一份行為測試需要順手 grep 一段源碼時，正確
/// 的動作是把那條斷言搬進對應的 `static_rules/` 檔案，不是在這裡加一行。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dart_source.dart';

/// `File('lib/…')` / `Directory('lib…')` 這一類對 `lib/` 的檔案系統存取。
///
/// 分兩段判斷而不是一條正則：路徑常常先存進變數或常數（`const viewerPath =
/// 'lib/ui/…dart'` 之後 `File(path)`），寫死 `File(` 緊接著字串的形狀掃不到。
final _fileSystemAccessPattern = RegExp(
  r'(?<![A-Za-z0-9_])(File|Directory)\s*\(',
);

/// 指向 `lib/` 的字面路徑：Dart 檔，或不含副檔名的目錄。
///
/// `lib/i18n/**.json` 之類的翻譯資料不算 —— 那是產品資料，不是原始碼，讀它的
/// 測試在斷言預設值與翻譯對得上，不是在凍結某次重構。
final _libSourcePathPattern = RegExp(r"'lib(/[^']*\.dart|/[A-Za-z0-9_/]*|)'");

final _compliantDirectoryPattern = RegExp(
  r'^test/(support/|[^/]+/static_rules/)',
);

/// 這支測試在讀 `lib/` 的原始碼。
bool readsLibSource(String source) {
  final code = stripDartComments(source);
  return _fileSystemAccessPattern.hasMatch(code) &&
      _libSourcePathPattern.hasMatch(code);
}

/// 這個路徑是靜態規則測試該待的地方。
bool isStaticRulePath(String path) =>
    _compliantDirectoryPattern.hasMatch(path) &&
    path.endsWith('_static_rule_test.dart');

void main() {
  group('static rule placement', () {
    test('every test that reads lib/ source is named and placed as one', () {
      final offenders = <String>[];
      var scanned = 0;

      for (final entity in Directory('test').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        // 本檔的合成樣本含有真的 `File('lib/…')` 字面值。
        if (path == _selfPath) continue;

        scanned++;
        if (!readsLibSource(entity.readAsStringSync())) continue;
        if (isStaticRulePath(path)) continue;
        offenders.add(path);
      }

      // 掃描本身要有作用 —— 路徑寫錯時 offenders 也會是空的。
      expect(scanned, greaterThan(200));
      expect(
        offenders,
        isEmpty,
        reason:
            'A test that greps lib/ is a static rule. Move it to '
            'test/support/ or test/<layer>/static_rules/ and end its name '
            'with _static_rule_test.dart. If the file also holds behaviour '
            'tests, move the grep out, not the file.',
      );
    });

    test('the static rule directories are not empty', () {
      // 規則靠目錄名生效；整批被改名走掉的話上面那條會安靜地全綠。
      final ruleFiles = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/'))
          .where(isStaticRulePath);

      expect(ruleFiles.length, greaterThan(10));
    });
  });

  group('the placement detector', () {
    test('catches a synthesised violation', () {
      const inlinePath = '''
test('the mini player delegates to the shared controls', () {
  final source = File('lib/ui/widgets/player/mini_player.dart')
      .readAsStringSync();
  expect(source, contains('MiniPlayerDesktopControls('));
});
''';
      const viaConstant = '''
const viewerPath = 'lib/ui/pages/settings/database_viewer_page.dart';

test('the viewer routes off the catalog', () {
  expect(File(viewerPath).readAsStringSync(), contains('fmpDatabaseCollections'));
});
''';
      const directoryScan = '''
for (final entity in Directory('lib/ui').listSync(recursive: true)) {
  offenders.add(entity.path);
}
''';

      expect(readsLibSource(inlinePath), isTrue);
      expect(readsLibSource(viaConstant), isTrue);
      expect(readsLibSource(directoryScan), isTrue);
      expect(
        isStaticRulePath('test/ui/widgets/mini_player_test.dart'),
        isFalse,
      );
      expect(
        isStaticRulePath('test/ui/static_rules/mini_player_test.dart'),
        isFalse,
        reason: 'the right directory is not enough; the name has to say it too',
      );
      expect(
        isStaticRulePath('test/ui/pages/mini_player_static_rule_test.dart'),
        isFalse,
        reason: 'the right name is not enough; test/ui/pages is not a rule dir',
      );
    });

    test('does not count a violation written in a comment', () {
      const commented = '''
// 不要在這裡 File('lib/ui/pages/search/search_page.dart').readAsStringSync()。
// 源碼比對屬於 test/ui/static_rules/。
testWidgets('the search page shows an empty state', (tester) async {
  await tester.pumpWidget(const SearchPage());
  expect(find.text('No results'), findsOneWidget);
});
''';

      expect(readsLibSource(commented), isFalse);
    });

    test('does not count translation data under lib/i18n', () {
      const i18nData = '''
test('every HLS description marks the stream as not recommended', () {
  final file = File('lib/i18n/\$locale/audioSettings.i18n.json');
  expect(jsonDecode(file.readAsStringSync()), containsPair('hls', isNotNull));
});
''';

      expect(readsLibSource(i18nData), isFalse);
    });

    test('accepts the two compliant shapes', () {
      expect(
        isStaticRulePath('test/support/layer_boundary_static_rule_test.dart'),
        isTrue,
      );
      expect(
        isStaticRulePath(
          'test/ui/static_rules/ui_consistency_static_rule_test.dart',
        ),
        isTrue,
      );
    });
  });
}

/// 本檔自己的路徑。
const _selfPath = 'test/support/static_rule_placement_static_rule_test.dart';
