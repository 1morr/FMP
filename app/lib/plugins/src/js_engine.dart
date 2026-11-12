import 'dart:async';

import 'package:fjs/fjs.dart';

/// 插件引擎開的 fjs 內建模組：只有 timers（Promise 與 setTimeout 的
/// driver）。fs、net、child_process、fetch 這類都不開：fjs 自帶的 fetch 會
/// 繞過宿主的網域白名單（brief 事實 K11），插件也不該有檔案系統與 socket
/// （ADR 0038）。`test/plugins/js_engine_builtins_test.dart` 守著：多開任何
/// 一個不在白名單的模組就紅，而且 `lib/` 裡建立引擎只能用這一組。
const pluginBuiltins = JsBuiltinOptions(timers: true);

/// 每個插件引擎的記憶體上限；超過時 JS 拿到可捕捉的 out of memory。
final pluginMemoryLimit = BigInt.from(64 * 1024 * 1024);

/// 插件模組在引擎裡的名稱。
const _pluginModule = 'plugin';

/// 呼叫插件的包裝模組：把插件丟的錯誤變成回傳值。fjs 把 JS 例外交給 Dart
/// 時只留訊息字串，`PluginError` 的 `code` 會不見（brief 事實 K19）。
const invokeModule = 'fmp_invoke';

/// 插件看得到的宿主 API：`host.http.request` 與 `PluginError`。全部經
/// fjs 的單一 bridge（`fjs.bridge_call`）進 Dart，在一處分派與檢查。
const _prelude = r'''
(() => {
  const bridge = fjs.bridge_call;
  class PluginError extends Error {
    constructor(code, message) {
      super(message ?? code);
      this.name = 'PluginError';
      this.code = code;
    }
  }
  const unwrap = (result) => {
    if (result && result.error) {
      throw new PluginError(result.error.code, result.error.message);
    }
    return result;
  };
  globalThis.PluginError = PluginError;
  globalThis.host = Object.freeze({
    http: Object.freeze({
      request: (req) =>
        bridge({
          op: 'http.request',
          url: String(req?.url),
          headers: req?.headers ?? {},
        }).then(unwrap),
    }),
  });
})();
''';

const _invoke =
    '''
import * as plugin from '$_pluginModule';
export async function invoke(method, args) {
  const fn = plugin[method];
  if (typeof fn !== 'function') {
    return { error: { code: 'unsupported', message: 'plugin has no ' + method } };
  }
  try {
    return { ok: await fn(args) };
  } catch (e) {
    const code = typeof e?.code === 'string' ? e.code : 'internal';
    return { error: { code, message: String(e?.message ?? e) } };
  }
}
''';

/// fjs 的原生庫（flutter_rust_bridge）每個 isolate 要初始化一次才能用；
/// 同時建好幾個引擎時共用同一次。測試先以 `loadFjsForTests()` 自己初始化
/// 了，這裡就略過。
Future<void>? _fjsReady;

Future<void> _ensureFjs() => _fjsReady ??=
    // ignore: invalid_use_of_internal_member -- fjs 只把 instance 標成內部；`initialized` 是 flutter_rust_bridge 公開的，沒有別的方式問初始化過沒
    LibFjs.instance.initialized ? Future.value() : LibFjs.init();

/// 建一個插件引擎：只開 [pluginBuiltins]、設記憶體上限、接上 [bridge]、
/// 放進宿主 API 與插件的程式 [code]（esbuild 打包的 ES module）。
/// 用 `call(module: invokeModule, method: 'invoke', ...)` 呼叫插件。
Future<JsEngine> createPluginEngine({
  required String code,
  required FutureOr<JsResult> Function(JsValue) bridge,
}) async {
  await _ensureFjs();
  final engine = await JsEngine.create(
    builtins: pluginBuiltins,
    runtimeOptions: JsEngineRuntimeOptions(memoryLimit: pluginMemoryLimit),
  );
  try {
    await engine.init(bridge: bridge);
    await engine.eval(source: const JsCode.code(_prelude));
    await engine.declareNewModules(
      modules: [
        JsModule.code(module: _pluginModule, code: code),
        JsModule.code(module: invokeModule, code: _invoke),
      ],
    );
    return engine;
  } catch (_) {
    await engine.close().catchError((Object _) {});
    rethrow;
  }
}
