import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/src/plugin_error.dart';

/// 插件的錯誤代碼列在兩處：JS 端的型別 `app/plugins/host.d.ts`，Dart 端的
/// [PluginErrorCode]。兩邊要一致：插件能丟的代碼宿主都認得，宿主自己才用的
/// 代碼不給插件丟。
///
/// 變異驗證兩個方向都要有：任一邊多一個或少一個代碼要紅；改 `host.d.ts`
/// 的排版、引號或註解不能紅。
void main() {
  /// 宿主自己才用、插件不丟的代碼。
  const hostOnly = {PluginErrorCode.domainNotAllowed, PluginErrorCode.internal};

  Set<String> dartCodes() => {
    for (final code in PluginErrorCode.values)
      if (!hostOnly.contains(code)) code.wire,
  };

  test('host.d.ts lists exactly the codes the host maps', () {
    final declared = errorCodeUnion(
      File('plugins/host.d.ts').readAsStringSync(),
    );
    expect(declared, isNotEmpty);
    expect(declared, dartCodes());
  });

  group('errorCodeUnion', () {
    test('turns red when a code is missing on either side', () {
      const dts = '''
type PluginErrorCode =
  | 'network'
  | 'rate_limited';
''';
      expect(errorCodeUnion(dts), isNot({'network', 'rate_limited', 'x'}));
      expect(errorCodeUnion(dts), isNot({'network'}));
    });

    test('stays green on layout, quotes and comments', () {
      const dts = '''
// 前面的註解
interface Other { code: 'not_a_code' }
/** 代碼 */
type PluginErrorCode = "network" | 'rate_limited' // 行尾註解
  | 'not_found';
type After = 'ignored';
''';
      expect(errorCodeUnion(dts), {'network', 'rate_limited', 'not_found'});
    });
  });
}

/// `host.d.ts` 裡 `type PluginErrorCode = …;` 列出的字串。
Set<String> errorCodeUnion(String dts) {
  final match = RegExp(r'type\s+PluginErrorCode\s*=([^;]*);').firstMatch(dts);
  if (match == null) return {};
  final body = match[1]!.replaceAll(RegExp(r'//[^\n]*'), '');
  return {
    for (final m in RegExp(r'''['"]([a-z_]+)['"]''').allMatches(body)) m[1]!,
  };
}
