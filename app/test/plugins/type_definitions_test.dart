import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/json_shape.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/plugin_host.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'contract/checks.dart';
import 'contract/fixture.dart';
import 'plugin_harness.dart';

// `lib/plugins/types/fmp-plugin.d.ts` 是給插件作者的介面說明。這裡以一個只
// 認得那個檔案寫法的小解析器，比對它與 Dart 端實際的欄位表、宿主 API 與
// 列舉；檔案結構改了，先改解析器再改比對。

// 換行統一成 LF：Windows 的 checkout 可能是 CRLF，變異案例以 `\n` 比對。
final _dts = File('lib/plugins/types/fmp-plugin.d.ts')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

/// Dart 端有欄位表的 interface。契約檢查的格式（checks.json、fixture）由
/// 契約執行器解碼。
final _shapes = <String, JsonShape>{
  ...manifestShapes,
  ...sourceDtoShapes,
  ...hostApiShapes,
  ...checkShapes,
  ...fixtureShapes,
};

/// 沒有 JSON 欄位表的 interface：宿主 API 由執行中的 runtime 比對，其他是
/// 說明用的型別。
const _apiInterfaces = {
  'FmpHost',
  'FmpHttp',
  'FmpCrypto',
  'FmpStorage',
  'FmpCredentials',
  'FmpLog',
  'FmpError',
  'FmpPluginExports',
};

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// 每個 interface 的成員：名稱 → 是否必填（沒有 `?`）。
Map<String, Map<String, bool>> _interfaces(String dts) {
  final source = _withoutComments(dts);
  final result = <String, Map<String, bool>>{};
  for (final match in RegExp(r'interface\s+(\w+)\s*\{').allMatches(source)) {
    var depth = 1;
    var end = match.end;
    while (depth > 0) {
      final char = source[end++];
      if (char == '{') depth++;
      if (char == '}') depth--;
    }
    final body = source.substring(match.end, end - 1);
    result[match[1]!] = {
      for (final statement in body.split(';'))
        if (RegExp(r'^(?:readonly\s+)?(\w+)(\?)?\s*[:(]')
                .firstMatch(statement.trim())
            case final member?)
          member[1]!: member[2] == null,
    };
  }
  return result;
}

/// `type Name = 'a' | 'b';` 的字串值。
Set<String> _union(String dts, String name) {
  final source = _withoutComments(dts);
  final match = RegExp('type\\s+$name\\s*=([^;]*);').firstMatch(source);
  if (match == null) return {};
  return {
    for (final value in RegExp("'([^']*)'").allMatches(match[1]!)) value[1]!,
  };
}

/// d.ts 與 Dart 欄位表的差異；一致時是空的。
List<String> _shapeDifferences(String dts) {
  final interfaces = _interfaces(dts);
  final differences = <String>[];
  for (final MapEntry(key: name, value: shape) in _shapes.entries) {
    final members = interfaces[name];
    if (members == null) {
      differences.add('$name is missing from the d.ts');
    } else if (!_sameShape(members, shape)) {
      differences.add('$name: d.ts $members, Dart $shape');
    }
  }
  for (final name in interfaces.keys) {
    if (!_shapes.containsKey(name) && !_apiInterfaces.contains(name)) {
      differences.add('$name has no Dart shape');
    }
  }
  return differences;
}

bool _sameShape(Map<String, bool> a, Map<String, bool> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

void main() {
  test('interfaces match the Dart JSON shapes', () {
    expect(_shapeDifferences(_dts), isEmpty);
  });

  group('the comparison', () {
    test('catches a missing field', () {
      final mutated = _dts.replaceFirst('  uploader?: string | null;\n', '');

      expect(mutated, isNot(_dts));
      expect(_shapeDifferences(mutated), [startsWith('TrackSummary:')]);
    });

    test('catches a field that became optional', () {
      final mutated = _dts.replaceFirst(
        '  hasMore: boolean;',
        '  hasMore?: boolean;',
      );

      expect(_shapeDifferences(mutated), [startsWith('SearchPage:')]);
    });

    test('catches an interface without a Dart shape', () {
      final mutated =
          '$_dts\nexport interface LyricsPage { lines: string[]; }\n';

      expect(_shapeDifferences(mutated), ['LyricsPage has no Dart shape']);
    });

    test('ignores comments, layout and member order', () {
      final reformatted = _dts
          .replaceAll('\n  ', '\n\t\t')
          .replaceFirst(
            '  sourceId: string;\n  cid?: number | null;',
            '  // extra: string;\n  /* hidden: number; */ cid?: number | null; '
                'sourceId: string;',
          );

      expect(reformatted, isNot(_dts));
      expect(_shapeDifferences(reformatted), isEmpty);
    });
  });

  test('FmpHost matches the fmp object the prelude builds', () async {
    final runtime = await PluginHarness().runtime('''
export function shape() {
  const out = {};
  for (const key of Object.keys(fmp)) {
    out[key] = typeof fmp[key] === 'object' ? Object.keys(fmp[key]).sort() : typeof fmp[key];
  }
  return out;
}
''');
    final interfaces = _interfaces(_dts);
    final host = interfaces['FmpHost']!;
    final hostTypes = {
      for (final match in RegExp(
        r'readonly\s+(\w+):\s*(Fmp\w+);',
      ).allMatches(_withoutComments(_dts)))
        match[1]!: match[2]!,
    };

    final actual = await runtime.invoke('shape', null) as Map;

    expect(actual.keys.toSet(), host.keys.toSet());
    expect(actual['apiVersion'], 'number');
    for (final MapEntry(key: member, value: type) in hostTypes.entries) {
      expect(
        actual[member],
        (interfaces[type]!.keys.toList()..sort()),
        reason: 'fmp.$member vs $type',
      );
    }
  });

  test('the capability union matches PluginCapability', () {
    expect(_union(_dts, 'FmpCapability'), {
      for (final capability in PluginCapability.values) capability.wireName,
    });
  });

  test('every error name maps to the AppError of that name', () {
    final names = _union(_dts, 'FmpErrorName');

    expect(names, hasLength(10));
    for (final name in names) {
      expect(
        structuredScriptError(
          pluginId: 'p',
          fmpError: name,
          reason: 'region',
        ).typeName,
        name,
      );
    }
  });

  test('the Unavailable reasons match UnavailableReason', () {
    expect(_union(_dts, 'FmpUnavailableReason'), {
      for (final reason in UnavailableReason.values)
        unavailableReasonWireName(reason),
    });
  });
}
