import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/source_id_literal.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(SourceIdLiteralTest));
}

@reflectiveTest
class SourceIdLiteralTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => SourceIdLiteral();

  // 報

  Future<void> test_idInUi() => assertLints('lib/ui/page.dart', '''
bool isBili(String id) => id == [!'bilibili'!];
''');

  Future<void> test_idOutsideLib() => assertLints('tool/demo.dart', '''
const id = [!"bilibili"!];
''');

  Future<void> test_youtubeId() => assertLints('lib/ui/page.dart', '''
bool isYoutube(String id) => id == [!'youtube'!];
''');

  Future<void> test_neteaseId() => assertLints('lib/ui/page.dart', '''
bool isNetease(String id) => id == [!'netease'!];
''');

  // 不報

  Future<void> test_allowedDirectories() async {
    await assertLints('test/ui/page_test.dart', "const id = 'youtube';\n");
    await assertLints(
      'lib/legacy_import/source_map.dart',
      "const id = 'bilibili';\n",
    );
    await assertLints('test/ui/page_test.dart', "const id = 'bilibili';\n");
  }

  Future<void> test_otherStrings() => assertLints('lib/ui/page.dart', '''
const label = 'Bilibili';
const key = 'bilibili_cookie';
const other = 'youtube_music';
const neteaseKey = 'netease_cookie';
const sentence = 'from bilibili';
''');

  Future<void> test_mentionInComment() => assertLints('lib/ui/page.dart', '''
// 'bilibili'
void f() {}
''');
}
