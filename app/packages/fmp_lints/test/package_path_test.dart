import 'package:fmp_lints/src/package_path.dart';
import 'package:fmp_lints/src/rules/ignore_reason.dart';
import 'package:fmp_lints/src/rules/layer_imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 路徑判斷與analyzer 無關的部分。規則測試本身在 Windows 上（或設了
/// `TEST_ANALYZER_WINDOWS_PATHS=true`）以 Windows 路徑跑；這裡固定兩種分隔符
/// 各跑一次，不依賴執行平台。
void main() {
  group('PackagePath.relative', () {
    test('Windows paths become posix package paths', () {
      expect(
        PackagePath.relative(
          r'C:\Users\me\FMP\app\lib\ui\toast\toast_host.dart',
          r'C:\Users\me\FMP\app',
          p.windows,
        ),
        PackagePath('lib/ui/toast/toast_host.dart'),
      );
    });

    test('posix paths stay as they are', () {
      expect(
        PackagePath.relative(
          '/home/me/FMP/app/test/support/pump_until.dart',
          '/home/me/FMP/app',
          p.posix,
        ),
        PackagePath('test/support/pump_until.dart'),
      );
    });

    test('a file outside the root has no package path', () {
      expect(
        PackagePath.relative(
          r'C:\Users\me\FMP\lib\main.dart',
          r'C:\Users\me\FMP\app',
          p.windows,
        ),
        isNull,
      );
    });
  });

  group('PackagePath.isIn', () {
    const path = PackagePath('lib/ui/theme/app_tokens.dart');

    test('matches the directory and its subdirectories', () {
      expect(path.isIn('lib/ui'), isTrue);
      expect(path.isIn('lib/ui/theme'), isTrue);
    });

    test('does not match a sibling that shares a prefix', () {
      expect(const PackagePath('lib/uikit/a.dart').isIn('lib/ui'), isFalse);
      expect(
        const PackagePath('lib/core/endpoints_test.dart')
            .isIn('lib/core/endpoints.dart'),
        isFalse,
      );
    });
  });

  group('PackagePath.resolve', () {
    const from = PackagePath('lib/core/errors/app_error.dart');

    test('resolves inside the package', () {
      expect(
        from.resolve('../../ui/page.dart'),
        PackagePath('lib/ui/page.dart'),
      );
    });

    test('leaving the package or an absolute path is null', () {
      expect(from.resolve('../../../../lib/main.dart'), isNull);
      expect(from.resolve('/lib/main.dart'), isNull);
    });
  });

  group('layerViolation from a Windows-derived path', () {
    final from = PackagePath.relative(
      r'C:\FMP\app\lib\core\logging\log.dart',
      r'C:\FMP\app',
      p.windows,
    )!;

    test('reports an upper layer', () {
      expect(
        layerViolation(from, 'package:fmp/ui/page.dart', ownPackage: 'fmp'),
        contains('lib/core/ must not import lib/ui/'),
      );
    });

    test('allows the same layer', () {
      expect(
        layerViolation(from, '../errors/app_error.dart', ownPackage: 'fmp'),
        isNull,
      );
    });
  });

  group('lacksReason', () {
    test('an fmp ignore without a reason', () {
      expect(lacksReason('// ignore: fmp_lints/fmp_url_literal'), isTrue);
      expect(lacksReason('//ignore_for_file:fmp_design_tokens'), isTrue);
    });

    test('an fmp ignore with a reason, or a non-fmp ignore', () {
      expect(
        lacksReason('// ignore: fmp_lints/fmp_url_literal — why'),
        isFalse,
      );
      expect(lacksReason('// ignore: fmp_url_literal - why'), isFalse);
      expect(lacksReason('// ignore: unused_element'), isFalse);
    });
  });
}
