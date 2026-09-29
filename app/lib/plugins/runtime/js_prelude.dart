/// 每個插件 runtime 在載入腳本之前先執行的 JS（宿主 API v1，ADR 0014 §決定 5）。
///
/// 它是一個函式運算式；插件的背景 isolate（`plugin_worker.dart`）以兩個 Dart
/// 函式與 API 版本呼叫它：
///
/// - `hostAsync(op, argsJson)` 回 Promise<回覆 JSON>：網路、storage、憑證，
///   以訊息交給主 isolate 執行；
/// - `hostSync(op, argsJson)` 直接回覆 JSON：crypto 在背景 isolate 算，log
///   檢查形狀後送給主 isolate（不等回覆）。
///
/// 回覆是 `{ok: true, value}` 或 `{ok: false, error}`。兩個函式只留在閉包裡，
/// 全域上看不到；腳本能碰到的只有唯讀的 `fmp` 與轉到 `fmp.log` 的 `console`。
/// JSON、Object.keys 在腳本執行前先取好，腳本改寫全域不影響宿主的溝通。
///
/// 回傳 `{load, call}`：
///
/// - `load(name)` 以動態 `import()` 載入插件 module（名稱只對得到插件腳本），
///   回覆匯出的函式名稱；
/// - `call(name, argJson)` 呼叫匯出的函式並等它完成。插件拋出的值轉成
///   `{kind: 'structured' | 'thrown' | 'unserializable', ...}`，永遠 resolve，
///   錯誤在 Dart 端轉成 `AppError`（`script_errors.dart`）。
///
/// 改了這裡的 `fmp` 形狀，同步改 `lib/plugins/types/fmp-plugin.d.ts`
/// （`type_definitions_test.dart` 比對兩邊的函式清單）。
const jsPrelude = r'''
(function (hostAsync, hostSync, apiVersion) {
  'use strict';
  const parse = JSON.parse;
  const stringify = JSON.stringify;
  const freeze = Object.freeze;
  const keys = Object.keys;
  const defineProperty = Object.defineProperty;

  const toError = (e) => {
    if (e.kind === 'argument') return new TypeError(e.message);
    const error = new Error(e.fmpError);
    error.fmpError = e.fmpError;
    error.hostErrorId = e.hostErrorId;
    if (e.retryAfterSeconds !== null) error.retryAfterSeconds = e.retryAfterSeconds;
    if (e.reason !== null) error.reason = e.reason;
    return error;
  };
  const unwrap = (reply) => {
    const result = parse(reply);
    if (result.ok) return result.value;
    throw toError(result.error);
  };
  // stringify 對函式、Symbol 回 undefined：一律送 null，宿主當成參數不對。
  const args = (value) => {
    const json = stringify(value);
    return json === undefined ? 'null' : json;
  };
  const callAsync = async (op, value) => unwrap(await hostAsync(op, args(value)));
  const callSync = (op, value) => unwrap(hostSync(op, args(value)));

  const text = (value) => {
    if (typeof value === 'string') return value;
    try {
      const json = stringify(value);
      return json === undefined ? String(value) : json;
    } catch (_) {
      return String(value);
    }
  };
  const logAt = (level) => (message, fields) =>
    callSync('log', { level, message: text(message), fields: fields === undefined ? null : fields });
  const consoleAt = (level) => (...values) =>
    callSync('log', { level, message: values.map(text).join(' '), fields: null });

  const fmp = freeze({
    apiVersion,
    http: freeze({
      request: (request) => callAsync('http.request', request),
    }),
    crypto: freeze({
      md5: (text) => callSync('crypto.md5', { text }),
      sha256: (text) => callSync('crypto.sha256', { text }),
    }),
    storage: freeze({
      get: (key) => callAsync('storage.get', { key }),
      set: (key, value) => callAsync('storage.set', { key, value }),
      delete: (key) => callAsync('storage.delete', { key }),
    }),
    credentials: freeze({
      get: () => callAsync('credentials.get', {}),
    }),
    log: freeze({
      debug: logAt('debug'),
      info: logAt('info'),
      warn: logAt('warn'),
      error: logAt('error'),
    }),
  });
  defineProperty(globalThis, 'fmp', { value: fmp });
  defineProperty(globalThis, 'console', {
    value: freeze({
      debug: consoleAt('debug'),
      log: consoleAt('debug'),
      info: consoleAt('info'),
      warn: consoleAt('warn'),
      error: consoleAt('error'),
    }),
  });

  const describe = (e) => {
    try {
      if (e !== null && typeof e === 'object' && typeof e.fmpError === 'string') {
        return {
          kind: 'structured',
          fmpError: e.fmpError,
          hostErrorId: typeof e.hostErrorId === 'number' ? e.hostErrorId : null,
          retryAfterSeconds: typeof e.retryAfterSeconds === 'number' ? e.retryAfterSeconds : null,
          reason: typeof e.reason === 'string' ? e.reason : null,
          message: typeof e.message === 'string' ? e.message : null,
        };
      }
      if (e instanceof Error) {
        return { kind: 'thrown', name: String(e.name), message: String(e.message), stack: String(e.stack || '') };
      }
      return { kind: 'thrown', name: typeof e, message: String(e), stack: '' };
    } catch (_) {
      return { kind: 'thrown', name: 'unknown', message: 'the thrown value cannot be described', stack: '' };
    }
  };
  const reply = (value) => {
    try {
      return stringify({ ok: true, value: value === undefined ? null : value });
    } catch (e) {
      return stringify({ ok: false, error: { kind: 'unserializable', message: String(e && e.message) } });
    }
  };
  const fail = (e) => stringify({ ok: false, error: describe(e) });

  let plugin = null;
  return {
    load: (name) => import(name).then((module) => {
      plugin = module;
      return reply(keys(module).filter((key) => typeof module[key] === 'function'));
    }, fail),
    call: async (name, argument) => {
      try {
        return reply(await plugin[name](parse(argument)));
      } catch (e) {
        return fail(e);
      }
    },
  };
})
''';
