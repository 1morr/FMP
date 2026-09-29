import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

/// 每條規則的測試基底：把程式碼寫到 test package 內指定的相對路徑，只看
/// 受測規則的診斷（未解析的名稱等編譯錯誤不參與比對）。
///
/// 路徑一律寫 posix（`lib/ui/foo.dart`）；`analyzer_testing` 在 Windows 上，
/// 或設了 `TEST_ANALYZER_WINDOWS_PATHS=true` 時轉成 Windows 路徑，所以同一組
/// 測試兩種分隔符都跑得到。
abstract class FmpRuleTest extends AnalysisRuleTest {
  /// 受測規則的新實例。
  AnalysisRule createRule();

  /// 在 `super.setUp()` 之前建立的假套件，例如 `newPackage('dio')`。
  void addStubPackages() {}

  @override
  void setUp() {
    rule = createRule();
    addStubPackages();
    super.setUp();
  }

  /// 把 [markedCode] 寫到 [relativePath]，斷言受測規則正好在每個
  /// `[!…!]` 標記的範圍報一次；沒有標記就是斷言不報。
  Future<void> assertLints(String relativePath, String markedCode) async {
    final (code, ranges) = _stripMarkers(markedCode);
    final path = '$testPackageRootPath/$relativePath';
    newFile(path, code);
    result = await resolveFile(convertPath(path));
    assertDiagnosticsIn(
      <Diagnostic>[
        for (final diagnostic in result.diagnostics)
          if (diagnostic.diagnosticCode.lowerCaseName == rule.name) diagnostic,
      ],
      [for (final (offset, length) in ranges) lint(offset, length)],
    );
  }
}

(String, List<(int, int)>) _stripMarkers(String marked) {
  final code = StringBuffer();
  final ranges = <(int, int)>[];
  int? start;
  for (var i = 0; i < marked.length;) {
    if (marked.startsWith('[!', i)) {
      start = code.length;
      i += 2;
    } else if (marked.startsWith('!]', i)) {
      ranges.add((start!, code.length - start));
      start = null;
      i += 2;
    } else {
      code.write(marked[i]);
      i++;
    }
  }
  return (code.toString(), ranges);
}
