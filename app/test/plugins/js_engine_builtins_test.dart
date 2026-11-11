import 'dart:io';

import 'package:fjs/fjs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/src/js_engine.dart';

import '../architecture/dependency_rules.dart' show readLibSources;
import '../support/fjs.dart';
import 'js_builtins_rule.dart';

/// 插件引擎只開白名單內的 fjs 內建模組（票 08，擁有者 2026-11-11 確認）：
/// fjs 自帶的 fetch 會繞過宿主的網域白名單（brief 事實 K11），插件也不該有
/// 檔案系統與 socket（ADR 0038）。三層：設定值、`lib/` 裡建立引擎的地方、
/// 真的引擎裡摸不到。
///
/// 變異驗證兩個方向都要有：多開一個非白名單模組、繞過 [pluginBuiltins]
/// 要紅；改無關的設定或排版不能紅。
void main() {
  group('pluginBuiltins', () {
    test('enables only allow-listed modules', () {
      expect(enabledBuiltins(pluginBuiltins), isNotEmpty);
      expect(
        enabledBuiltins(pluginBuiltins).difference(allowedBuiltins),
        isEmpty,
      );
    });

    test('turns red when one more module is enabled', () {
      for (final options in const [
        JsBuiltinOptions(timers: true, fetch: true),
        JsBuiltinOptions(timers: true, fs: true),
        JsBuiltinOptions(timers: true, net: true),
        JsBuiltinOptions(timers: true, childProcess: true),
        JsBuiltinOptions(timers: true, console: true),
      ]) {
        expect(
          enabledBuiltins(options).difference(allowedBuiltins),
          isNotEmpty,
          reason: '$options',
        );
      }
    });

    test('stays green when a module is explicitly turned off', () {
      const options = JsBuiltinOptions(timers: true, fetch: false, fs: false);
      expect(enabledBuiltins(options).difference(allowedBuiltins), isEmpty);
    });
  });

  group('engine creation in lib/', () {
    test('always goes through JsEngine.create with pluginBuiltins', () {
      final files = readLibSources(Directory('lib'));
      final creating = files.keys.where(
        (path) => files[path]!.contains('JsEngine.create'),
      );
      expect(creating, isNotEmpty, reason: 'the rule must see the real call');
      final violations = engineCreationViolations(files);
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('turns red on other builtins or a bare runtime', () {
      const sources = {
        'all': 'f() => JsEngine.create(builtins: JsBuiltinOptions.all());',
        'inline':
            'f() => JsEngine.create(builtins: JsBuiltinOptions(fetch: true));',
        'none given': 'f() => JsEngine.create();',
        'prefixed':
            "import 'package:fjs/fjs.dart' as fjs;\n"
            'f() => fjs.JsEngine.create(builtins: other);',
        'async runtime':
            'f() => JsAsyncRuntime.create(builtins: pluginBuiltins);',
        'sync runtime': 'f() => JsRuntime();',
        'new runtime': 'f() => new JsRuntime();',
      };
      sources.forEach((name, source) {
        expect(
          engineCreationViolations({'plugins/src/x.dart': source}),
          hasLength(1),
          reason: name,
        );
      });
    });

    test('stays green on unrelated changes', () {
      const sources = [
        // 換記憶體上限、加別的參數、換行排版、加註解。
        'f() => JsEngine.create(builtins: pluginBuiltins, runtimeOptions: '
            'JsEngineRuntimeOptions(memoryLimit: BigInt.one));',
        'f() => JsEngine.create(\n'
            '  // 只開白名單\n'
            '  runtimeOptions: null,\n'
            '  builtins: pluginBuiltins,\n'
            ');',
        "import 'package:fjs/fjs.dart' as fjs;\n"
            'f() => fjs.JsEngine.create(builtins: pluginBuiltins);',
        'f() => engine.eval(source: const JsCode.code("1"));',
      ];
      for (final source in sources) {
        expect(
          engineCreationViolations({'plugins/src/x.dart': source}),
          isEmpty,
          reason: source,
        );
      }
    });
  });

  group('a plugin engine', () {
    late JsEngine engine;

    setUpAll(loadFjsForTests);
    setUp(() async {
      engine = await createPluginEngine(
        code: 'export const x = 1;',
        bridge: (_) => const JsResult.ok(JsValue.none()),
      );
    });
    tearDown(() => engine.close());

    Future<Object?> eval(String code) async =>
        (await engine.eval(source: JsCode.code(code))).value;

    test('has no fetch, require or process', () async {
      expect(
        await eval(
          '[typeof fetch, typeof require, typeof process, '
          'typeof XMLHttpRequest, typeof WebSocket].join()',
        ),
        List.filled(5, 'undefined').join(','),
      );
    });

    for (final module in [
      'fs',
      'fs/promises',
      'net',
      'http',
      'https',
      'child_process',
      'dgram',
      'dns',
      'os',
    ]) {
      test('cannot import $module', () async {
        expect(
          await eval('''
            (async () => {
              try { await import('$module'); return 'imported'; }
              catch (e) { return 'blocked'; }
            })()
          '''),
          'blocked',
        );
      });
    }

    test('still runs promises and timers', () async {
      expect(
        await eval(
          'new Promise((resolve) => setTimeout(() => resolve(42), 10))',
        ),
        42,
      );
    });
  });
}
