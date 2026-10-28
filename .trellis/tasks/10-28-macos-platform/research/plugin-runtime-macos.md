# Research: 插件執行環境在 macOS（flutter_js 0.8.7 / JavaScriptCore）

- **Query**: 我們的插件 runtime 能不能在 macOS 的 JavaScriptCore 上跑？flutter_js 在 macOS 的實況、功能缺口、測試做法與選項。
- **Scope**: mixed（讀 repo 與 pub cache 原始碼，加上 scratchpad 的 C／ObjC 小實驗，加上 pub.dev 套件查詢）
- **Date**: 2026-10-28

## 結論先講（TL;DR）

1. **現況在 macOS 上一定載入失敗，而且不是「ADR 0014 規劃的 JSC」那條路**：`plugin_worker.dart` 直接繼承
   `QuickJsRuntime2`（QuickJS 的 FFI 包裝），flutter_js 0.8.7 的 macOS 外掛只有一個空的 Swift
   stub，沒有編 QuickJS；`ffi.dart` 在 macOS 用 `DynamicLibrary.process()` 找 `jsNewRuntime`，找不到。
   `getJavascriptRuntime()` 才會在 macOS 選 `JavascriptCoreRuntime`，但我們刻意不用它。
2. **flutter_js 的 `JavascriptCoreRuntime` 跟我們用到的 API 面幾乎不重疊**：沒有 `moduleHandler`、
   `hostPromiseRejectionHandler`、`JSInvokable`、Dart `Function`／`Future` 與 JS 函式／Promise 的自動轉換、
   `evaluate(name:)`；`executePendingJob()` 是個假的（evaluate 一個空函式）。要走 JSC 等於重寫
   `plugin_worker.dart` 的引擎層。
3. **JSC 本身（系統 framework）能做到我們需要的大部分，且比 QuickJS 更好的是看門狗可以真的中斷無窮迴圈**
   （實測 `JSContextGroupSetExecutionTimeLimit` 有效，連 NULL callback 都行）。**最大的洞是 ES module**：
   C API 的 `import()` 一律 `No module loader provided`；實測只有走 ObjC 的私有 SPI
   （`JSContext.moduleLoaderDelegate` + `JSScript`，在這台 Mac 上可用）才載得進插件。
4. **不用 JSC 的另一條路**：把 QuickJS 帶進 macOS。flutter_js 沒附 macOS 的 QuickJS；pub.dev 上
   `quickjs_engine`（flutter_js 的 API 相容 fork，附 macOS 預編 dylib）與 `flutter_qjs_next`
   （`QuickJsRuntime2` 同名 API，另有 `timeout` 中斷與 `memoryLimit`）都有 macOS，需換依賴並改 import。
5. 要決定的是「macOS／iOS 之後用 JSC（A）還是統一用 QuickJS（B）」，見 §5 與「建議」。

## 1. 我們的 runtime 怎麼用 flutter_js

### Files Found

| File Path | Description |
|---|---|
| `app/lib/plugins/runtime/plugin_worker.dart` | 背景 isolate 的進入點；唯一 import `flutter_js` 的檔案（`fmp_layer_imports`） |
| `app/lib/plugins/runtime/js_prelude.dart` | 宿主 API 的 JS（`fmp`、`console`、`load`／`call`），用動態 `import()` |
| `app/lib/plugins/runtime/plugin_runtime.dart` | 主 isolate：spawn、看門狗（`Timer`）、`Ping`／`Pong`、`Isolate.kill` |
| `app/lib/plugins/runtime/script_errors.dart` | 結構化錯誤 → `AppError` |
| `app/test/support/quickjs.dart`、`app/test/flutter_test_config.dart` | 測試預載 QuickJS 原生庫 |
| `app/integration_test/plugin_runtime_benchmark_test.dart` | 實機量測 |
| `app/linux/CMakeLists.txt:77-82` | 把 flutter_js 的 `.so` 補裝進 bundle |
| `.trellis/tasks/archive/2026-09/09-30-js-runtime/research/notes.md` | 上一輪的查證與實測 |

### 用到的 flutter_js API

`plugin_worker.dart` 全部的依賴（只有 `package:flutter_js/flutter_js.dart`，沒有直接 `dart:ffi` 對 QuickJS 符號）：

```dart
// plugin_worker.dart:181-189
final class _QuickJs extends QuickJsRuntime2 {
  _QuickJs({required super.moduleHandler, required super.hostPromiseRejectionHandler});
  @override
  JavascriptRuntime init() => this;   // 不裝 console／setTimeout／sendMessage
}
```

- 建構：`moduleHandler: (name) => name == 'fmp-plugin' ? script : throw`（`:34-37`）、
  `hostPromiseRejectionHandler`（`:38-39`）。**這兩個是 QuickJsRuntime2 專有的建構參數。**
  沒有傳 `timeout`、`memoryLimit`、`stackSize`（用預設 `stackSize = 1 MiB`）。
- 執行：`_engine.evaluate(jsPrelude, name: '<fmp-prelude>')`（`:43`，`name:` 也是 QuickJsRuntime2 專有；
  `JavascriptCoreRuntime.evaluate` 只有 `sourceUrl:`）。
- 取回 JS 函式：`prelude.rawResult as JSInvokable`，`factory.invoke([_hostAsync, _hostSync, hostApiVersion])`
  （`:47-51`）。**傳 Dart `Function` 當 JS 函式、Dart 回傳 `Future<String>` 自動變 JS Promise**
  （notes.md §1 引 `wrapper.dart` 的 `_dartToJs`／`_jsToDart`）。`_load.invoke(...)`／`_call.invoke(...)`
  回來的 JS Promise 被轉成 Dart `Future`（`:77`、`:92`）。
- Promise 工作：自己呼叫 `_engine.executePendingJob()`（`:103`），在 `load`／`call` 之後與每次
  `HostReply` 之後（`scheduleMicrotask(_pump)`，`:96-100`）。
- 釋放：`JSInvokable.free()`、`_engine.dispose()`（`:107-110`）。
- 沒有用 `onMessage`／`sendMessage`／`handlePromise`／`getJavascriptRuntime()`／`setInspectable`。

### 是否在背景 isolate

是。每插件一個 `Isolate.spawn(pluginWorkerMain, ...)`（`plugin_runtime.dart:174`），QuickJS 在裡面建立。
看門狗在主 isolate（`plugin_runtime.dart:459` `Timer`），逾時先 `Ping`，2 秒沒 `Pong` 才
`Isolate.kill(priority: immediate)`（`:293`）。

### 沒有直接用 dart:ffi 對 QuickJS 符號

- repo 內 `grep` 不到 `DynamicLibrary` 於 `lib/`；看門狗**不是**靠 `JS_SetInterruptHandler`，
  是靠 isolate 探測；沒有 `JS_SetMemoryLimit`／`JS_SetMaxStackSize` 的直接呼叫（flutter_js 的
  `QuickJsRuntime2` 內部在 `_ensureEngine` 呼叫 `jsSetMaxStackSize(rt, stackSize)`，
  `quickjs_runtime2.dart:128-131`；memory limit 的 FFI 符號 `jsSetMemoryLimit` 在 0.8.7 的 Windows DLL
  根本不存在，notes.md §1）。
- **唯一以檔名載入原生庫的地方在 flutter_js 內部**（`lib/quickjs/ffi.dart` 的 `_qjsLib`）：

```dart
// flutter_js-0.8.7/lib/quickjs/ffi.dart
final DynamicLibrary _qjsLib = Platform.environment['FLUTTER_TEST'] == 'true'
    ? (Platform.isWindows ? DynamicLibrary.open('quickjs_c_bridge.dll')
        : Platform.isMacOS ? DynamicLibrary.process()
        : DynamicLibrary.open(Platform.environment['LIBQUICKJSC_TEST_PATH'] ?? 'libquickjs_c_bridge_plugin.so'))
    : (Platform.isWindows ? DynamicLibrary.open('quickjs_c_bridge.dll')
        : (Platform.isLinux ? DynamicLibrary.open(Platform.environment['LIBQUICKJSC_PATH'] ?? 'libquickjs_c_bridge_plugin.so')
        : (Platform.isAndroid ? DynamicLibrary.open('libfastdev_quickjs_runtime.so')
        : DynamicLibrary.process())));
```

  macOS（測試與正式）都是 `DynamicLibrary.process()`：QuickJS 符號要已經被連進 App 行程。flutter_js 的
  macOS 外掛沒有（見 §2），所以第一次 `jsNewRuntime` lookup 時丟 `ArgumentError: Failed to lookup symbol`。
  它發生在 `_QuickJs` 建構子裡（`_ensureEngine`），也就是 `pluginWorkerMain` 內、`_Worker` 建構時，
  未捕捉 → `onError` → 主 isolate `_markUnresponsive`（`plugin_runtime.dart:347-350`）。
  結果是每個插件在 macOS 一載入就變 `PluginHealth.unresponsive`。

### 腳本載入方式（對 JSC 很關鍵）

插件是 **ES module**，`js_prelude.dart` 的 `load: (name) => import(name).then(...)`，worker 的
`moduleHandler` 只對 `'fmp-plugin'` 回傳腳本（`plugin_worker.dart:15-17`、`:34-37`）。
測試 `plugin_runtime_test.dart:99` 也驗證別的 `import(name)` 會被拒絕。

## 2. flutter_js 0.8.7 在 macOS

（版本：`app/pubspec.lock:574-581` → 0.8.7；pub cache `~/.pub-cache/hosted/pub.dev/flutter_js-0.8.7/`）

- **`getJavascriptRuntime()` 的選擇**（`lib/flutter_js.dart`）：Android（且沒 `forceJavascriptCoreOnAndroid`）、
  Windows、Linux 是 `QuickJsRuntime2`；**其餘（iOS、macOS）是 `JavascriptCoreRuntime`**，
  並預設 `enableFetch()`（`xhr: true`）與 `enableHandlePromises()`。沒有「在 macOS 強制 QuickJS」的旗標
  （`forceJavascriptCoreOnAndroid` 只反方向）。
- **macOS 外掛內容**：`macos/flutter_js.podspec`（`s.source_files = 'Classes/**/*'`、只依賴 `FlutterMacOS`、
  **沒有 `s.frameworks = 'JavaScriptCore'`**，沒有 vendored lib）與
  `macos/Classes/FlutterJsPlugin.swift`（只實作 `getPlatformVersion`）。整個 `macos/`、`ios/` 底下
  `grep -i quickjs` 只命中 iOS podspec 的描述字串。**套件裡沒有任何 C／C++ QuickJS 原始碼**（只有
  `linux/shared/*.so`、`windows/shared/*.dll` 預編檔，Android 走 jitpack AAR）。所以
  「在 macOS 強制用 QuickJS」在 0.8.7 無法成立。repo 現在的 `app/macos/Podfile.lock` 的 `flutter_js`
  就是那個 stub。
- **`JavascriptCoreRuntime` 的實作**（`lib/javascriptcore/`）：純 `dart:ffi` 直打系統 framework：

```dart
// lib/javascriptcore/binding/jsc_ffi.dart
static DynamicLibrary lib = Platform.isIOS || Platform.isMacOS
    ? getMacOsIOSJavascriptCoreLibPath()   // 'JavaScriptCore.framework/JavaScriptCore'，退而 /System/Library/Frameworks/...
```

  C API 的綁定（`jSEvaluateScript`、`jSObjectMakeFunctionWithCallback`、`jSGlobalContextSetInspectable`…）
  在 `lib/javascriptcore/binding/*.dart`。`flutter_js.dart` 沒 export 它們，但可 import
  `package:flutter_js/javascriptcore/flutter_jscore.dart`。
- **API 面對照**（`jscore_runtime.dart` vs 我們的用法）：

| 我們用的 | QuickJsRuntime2 | JavascriptCoreRuntime |
|---|---|---|
| `moduleHandler` | 有（`JS_SetModuleLoaderFunc`） | **沒有** |
| `hostPromiseRejectionHandler` | 有 | **沒有** |
| `evaluate(name:)` + `rawResult as JSInvokable` | 有 | `evaluate(js, {sourceUrl})`，`rawResult` 是原生指標，無 `JSInvokable` |
| Dart 函式當 JS 函式、Future↔Promise | 有（`wrapper.dart`） | 只有 `sendMessage` 通道；Future 靠拼字串 `__JSC_promise_result$id.resolve(json)` 再 `evaluate`，reject 用 `"$error"` 拼進字串（有注入／跳脫問題） |
| `executePendingJob()` | `JS_ExecutePendingJob` 迴圈 | `evaluate('(function(){})();'); return 0;`（靠 JSC 在外層呼叫返回時自己清 microtask） |
| `setInspectable` | 空實作 | `JSGlobalContextSetInspectable`（iOS／macOS） |
| `dispose` | `JS_FreeRuntime` 等 | `JSGlobalContextRelease` + `JSContextGroupRelease` |
| 建構子裝 `console`／`setTimeout`／`sendMessage` | 可覆寫 `init()` 跳過 | `JavascriptCoreRuntime()` 建構子最後呼叫 `init()`，**不能覆寫掉**（`_setupSetTimeout` 等要靠 `sendMessage` 才有效），須自己子類化或不用 |

- **能不能在非主 isolate 用 JSC**：flutter_js 的 JSC 路徑沒有任何 isolate 限制，且是純 FFI。我用 C 在
  `pthread` 非主執行緒建立 context group、context、evaluate、時間上限，全部正常（t.c、t4.c，見 §6）。
  要注意的是 `Pointer.fromFunction` 的回呼（`sendMessageBridgeFunction`）只能在建立它的 isolate 的
  執行緒被呼叫；JSC 的 host function 與時間上限 callback 都是在**執行 JS 的那條執行緒**同步呼叫（t4.c 實測
  `cb on eval thread: 1`），所以同一個背景 isolate 內安全。`JavascriptCoreRuntime` 的
  `_sendMessageDartFunc` 是 `static`，但 Dart 的 static 是 per-isolate，不會互相踩。
- 不透過 flutter_js 的方法：macOS 的 JSC 是系統 framework，連結免費（不用打包）；flutter_js 的 podspec
  沒宣告 framework 是因為它用 `dlopen` 開 `/System/Library/Frameworks/...`。

## 3. JSC 的功能缺口（逐項；全部是我在這台 Mac 以 C／ObjC 小程式實測，除非註明）

環境：macOS（Darwin 27.0.0）、Xcode 27.1 SDK、Apple Silicon，直接連結系統 JavaScriptCore。實驗檔都在
`<暫存目錄>/jsc/`
（`t.c`、`t2.c`、`t3.m`、`t4.c`、`t5.m`、`t6.c`）。

| 項目 | JSC 能不能 | 怎麼做／實測結果 |
|---|---|---|
| **ES module（`import()`）** | C API 不能；私有 SPI 可以 | `JSEvaluateScript` 裡 `import('x')` → rejected `Module specifier: x does not start with "/", "./", or "../"`；改成 `/abs/path.js` 或 `./p.js` → `No module loader provided`（t2.c）。ObjC 的 `JSContext.moduleLoaderDelegate`（`setModuleLoaderDelegate:`）與 `JSScript scriptOfType:withSource:andSourceURL:andBytecodeCache:inVirtualMachine:error:`（type 1 = module）在這台 Mac 上都存在且可用：delegate 的 `context:fetchModuleForIdentifier:withResolveHandler:andRejectHandler:` 收到 `file:///fmp-plugin`，resolve 一個 module 型的 JSScript 後，`import('./fmp-plugin')` 成功、匯出 `search,y`、`await m.search('q')` 得 `hi q`；其他名稱 reject → 與 `plugin_runtime_test.dart:99` 的期待一致（t5.m）。公開標頭（`JSContext.h`）只有 `@class JSScript` 前向宣告，所以是 SPI／非公開 API。**識別字必須長得像路徑**（`./`、`../`、`/`），要把 `pluginModuleName`（現為 `fmp-plugin`）改成 `./fmp-plugin` 之類。 |
| **看門狗／CPU 逾時中斷** | 可以（比 QuickJS 好） | `JSContextGroupSetExecutionTimeLimit(group, seconds, callback, ctx)` 是 `extern`（不在公開標頭，但在 SDK 的 `JavaScriptCore.tbd` 匯出：`_JSContextGroupSetExecutionTimeLimit`、`_JSContextGroupClearExecutionTimeLimit`）。實測：`while(true){}` 在 0.5 秒後被終止，evaluate 回例外 `JavaScript execution terminated.`，之後同一個 context 還能 `1+1`。callback 傳 `NULL` 也終止（t4.c），所以不需要 Dart 提供原生回呼。callback 非 NULL 時是在**執行緒本身**呼叫，回 `true` 終止、`false` 續跑。限制：算的是 JS 執行的 CPU 時間（不含等 Dart／網路的時間），且每次 JS 進入（evaluate／callAsFunction）重新計。**這意味著 JSC 上「卡住的執行緒回收不了」的限制可以消失**（`app/AGENTS.md:1264`）。 |
| **記憶體上限** | 沒有公開 API | JSC 沒有 `JS_SetMemoryLimit` 對應物（SDK tbd 裡找不到）。目前 flutter_js 0.8.7 的 QuickJS 路徑**也沒有**（Windows DLL 無 `jsSetMemoryLimit`，notes.md §1），App 現狀沒有記憶體上限，所以不是退步。 |
| **堆疊深度** | 有，但看執行緒堆疊 | 無限遞迴得到 `RangeError: Maximum call stack size exceeded.`（t.c，在 pthread 預設 512 KB 的堆疊上也沒崩）。不像 QuickJS 的 `JS_SetMaxStackSize` 有 1 MiB 的設定。 |
| **ES2020 語法與內建** | 有 | optional chaining、`??`、`Array.at`、`replaceAll`、`matchAll`、`Promise.allSettled`、`flat`、`Object.fromEntries`、`WeakRef`、`BigInt`（`2n**64n` → `18446744073709551616`）都通過（t2.c、t.c）。JSC 比 QuickJS（flutter_js 附的 2021-03 版）新，不是缺口。 |
| **BigInt** | JSC 有、flutter_js 附的 QuickJS 沒有 | `plugin_runtime_test.dart:20` 註解寫 QuickJS 版「沒有 BigInt」。反方向：在 macOS 上寫的插件若用了 BigInt，Windows／Android／Linux 會壞。 |
| **TextEncoder／TextDecoder、URL、fetch、setTimeout、queueMicrotask、structuredClone** | **JSC 全域沒有**（C API 的 JSGlobalContext 只有 ECMAScript 內建，`typeof` 全是 `undefined`） | 與 QuickJS 一致（兩邊都沒有），所以插件本來就得自己補（ADR 0014 補充：YouTube.js 在插件檔內補 TextEncoder 等）。`js_prelude.dart` 也不提供 `setTimeout`。**不是 macOS 專有缺口。** |
| **Promise job 排空** | 有，語義略不同 | JSC 在最外層的 API 呼叫返回時自動排空 microtask：`Promise.resolve(1).then(()=>{r='drained'}); r` 該次回 `pending`，下一次 evaluate 時 `r` 已是 `drained`（t.c）。所以 `executePendingJob()` 在 JSC 沒有對應動作，等同「再進入 JS 一次」。我們的流程「Dart 完成 host Future → 呼叫 JS 的 resolve」本身就是一次進入 JS，返回時 microtask 就排空，不需要 `_pump`。 |
| **unhandled rejection 通知** | 有私有 API | `JSGlobalContextSetUnhandledRejectionCallback` 在 SDK tbd 匯出（SPI）。對應 `hostPromiseRejectionHandler`。公開 C API 沒有。 |
| **錯誤格式** | 格式不同，但我們的解析不依賴 | `plugin_runtime.dart:396-448` 的 `_unwrap` 只讀 prelude 回的 JSON：`name`（唯一的邏輯判斷是 `name == 'SyntaxError'`，`:429`）、`message`、`stack`（只當 `PluginScriptError.jsStack` 進 log）。JSC 的 `SyntaxError`、`TypeError` 名稱與標準一致；`message` 文字不同（`null is not an object (evaluating 'null.x')` vs V8 風格），`stack` 是 `f@plugin.js:1:29\nglobal code@plugin.js:1:45`（SpiderMonkey 風格，無 `at`）。repo 的 `app/lib/plugins/` 內**沒有用 regex 解析 JS 錯誤字串**；測試是否斷言 QuickJS 的 message／stack 格式要在移植測試時再查（我只確認了 `_builtIns` 一處）。 |
| **全域物件差異** | 有 | JSC 全域比 QuickJS 多 `Atomics, BigInt, BigInt64Array, BigUint64Array, FinalizationRegistry, Float16Array, Intl, Iterator, WeakRef, WebAssembly, console`；少 `InternalError, SharedArrayBuffer, __date_clock`（t6.c）。`plugin_runtime_test.dart:21-33` 的 `_builtIns` 比對「全域只有內建＋`fmp`＋`console`」在 JSC 要換一份清單。另外 JSC 的 `console` 是原生全域，prelude 的 `defineProperty(globalThis,'console',{value})` 是改既有屬性，保留原屬性的 writable／configurable，而 QuickJS 上是新建（不可寫）；`fmp` 兩邊都是新建，不受影響。**`WebAssembly` 出現在插件可見的全域**（沙箱面積變大，ADR 0014 沒討論）。 |
| **`setInspectable`** | 有 | `JSGlobalContextSetInspectable`（macOS 13.3+／iOS 16.4+ 才會讓 Safari Web Inspector 連上）。flutter_js 已實作。 |

JIT：JSC 在 macOS 上的 JIT 需要 `com.apple.security.cs.allow-jit`（hardened runtime）。`app/macos/Runner/DebugProfile.entitlements`
有 allow-jit；`Release.entitlements` 只有 `app-sandbox`（沒有 allow-jit）。沒有 JIT 時 JSC 退回直譯器，仍能跑，
只是慢（這點我沒量，需要實機）。

## 4. 測試

- `app/test/flutter_test_config.dart:23` 對每個測試檔呼叫 `loadQuickJsForTests()`。
- `app/test/support/quickjs.dart:21-35`：Windows 開 `windows/shared/quickjs_c_bridge.dll`、Linux 開
  `linux/shared/libquickjs_c_bridge_plugin.so`（先用絕對路徑 `DynamicLibrary.open`，之後 flutter_js 以檔名
  開就拿到同一份）；**其他平台直接 `return`**（註解：「macOS 的 flutter_js 走 JavaScriptCore，App 在 macOS
  也還沒支援，不處理」）。所以在 macOS 主機跑插件測試會是 `Failed to lookup symbol 'jsNewRuntime'`
  （flutter_js 在 `FLUTTER_TEST=true` 且 macOS 用 `DynamicLibrary.process()`，flutter_tester 行程裡沒有）。
- Mac 上現行的做法：`app/tool/linux_test.sh`（OrbStack 的 x86_64 Ubuntu 跑完整 `flutter test`，
  `app/AGENTS.md:28-40`）；macOS 本機只跑不碰插件的測試。
- **能不能在 macOS 主機跑 QuickJS 測試**：flutter_js 沒有 macOS dylib（`find` 只有 linux 的 `.so`、
  windows 的 `.dll`；也沒有 C 原始碼可自己編）。選項：(a) 換成 `quickjs_engine`，它在
  `macos/Frameworks/libquickjs_c_bridge_plugin.dylib` 附 universal 預編檔（README 有「Tests can't find the
  dylib」一節，做法跟我們 `loadQuickJsForTests` 類似）；(b) `flutter_qjs_next` 自帶 `cxx/` 原始碼，
  由 SPM／CocoaPods 編；其 FFI 在測試怎麼載入我沒有查。(c) 維持 Linux 容器跑插件測試。
- 若走 JSC：`flutter test` 的 flutter_tester 行程可以 FFI 開系統 framework，但 `testWidgets` 之外純 Dart
  測試也行；障礙不是載入，而是 §3 的 module loader SPI 需要原生碼（ObjC／Swift）——flutter_tester 沒有我們的
  原生外掛，**測試環境拿不到 module loader shim**（除非用 `package:objective_c` 之類的 Dart ObjC interop
  從 Dart 端直接呼叫 SPI，我沒有驗證可行性），所以 macOS 主機上跑 JSC 版的插件測試會比 QuickJS 難。
- 整合測試／量測：`app/integration_test/plugin_runtime_benchmark_test.dart`（`flutter test
  integration_test/plugin_runtime_benchmark_test.dart -d <裝置>`，檔頭 `:28-30` 範例是 emulator 與 windows；
  支援 `--dart-define=FMP_BENCH_PLUGIN=<路徑>` 量外部插件載入）。它透過 `ScriptSourcePlugin` 走完整
  runtime，所以**在 macOS 上 `-d macos` 可跑，但現況會因 QuickJS 載不到而失敗**，換引擎後可直接拿來驗證
  JSC（量建立／載入／search 往返與 RSS）。另外 `integration_test/install_search_play_test.dart` 也用到插件。
  CI 的 macOS job（`.github/workflows/ci.yml:412-444`）只做 `flutter build macos`，沒有跑任何插件測試。
- `test/plugins/runtime/plugin_runtime_test.dart` 的看門狗案例（`while (true) {}`，`:679`、`:719`）在 JSC
  上會因時間上限而結束，原本斷言的「卡住的執行緒」行為要改寫。

## 5. 選項與取捨

### 選項 A：照 ADR 0014，macOS 用 JavaScriptCore

要做的事（對 repo 內的 `plugin_worker.dart` 引擎層）：

1. 不用 `QuickJsRuntime2`，也不能直接用 flutter_js 的 `JavascriptCoreRuntime`（API 面不夠，見 §2 表）。
   需自寫一層薄的 JSC 包裝：可借 flutter_js 的 `lib/javascriptcore/binding/*`（FFI 綁定）或自己對
   C API 做 `ffigen`。要補 `JSObjectMakeFunctionWithCallback`（`hostAsync`／`hostSync`）、把 JS Promise 變
   Dart Future（或改成 callback 風格：呼叫 `JSObjectCallAsFunction` 傳一個 resolve 函式）、值轉換（字串即可，
   因為協定本來就是 JSON 字串）。
2. **ES module 載入**需要 ObjC SPI（moduleLoaderDelegate + JSScript），要寫 Swift／ObjC 外掛，或用 Dart 的
   ObjC interop。替代：不走 ES module，由宿主改寫腳本（把 `export` 轉成對 `exports` 物件的指派）——
   但 `.js` 插件是 esbuild 打的 bundle，最後的 `export { a as b }` 形式需要可靠的轉換，風險高；也會偏離
   「插件是 ES module」的契約（`fmp-plugin.d.ts`、ADR 0014 補充）。
3. 看門狗：`JSContextGroupSetExecutionTimeLimit`（`extern` 私有符號，經 FFI `lookup` 取得）。
4. 測試與契約執行器：`loadQuickJsForTests` 對 macOS 要有對應，且跨引擎測試要容許 JSC 的全域清單與
   錯誤訊息差異。
5. 同一份插件在 QuickJS（Android／Windows／Linux）與 JSC（macOS／iOS）兩種引擎行為會有小差異
   （BigInt、全域清單、錯誤訊息、`Intl` 存在）。契約測試（`test/plugins/contract/`）只在 CI 的 Linux／QuickJS 跑，
   macOS 的 JSC 行為沒人守。

優點：不增加原生二進位大小、系統維護、與 iOS 路線一致、macOS 看門狗能真的中斷。缺點：需要私有 SPI 與原生
外掛、兩套引擎要維護與對測。iOS 的 JSC：第三方 App 的 `JSContext` 沒有 JIT（沒有 `dynamic-codesigning`
權限，只有 WKWebView 有），所以是直譯器；JSC 的 `moduleLoaderDelegate`／`JSScript` 在 iOS 同樣是 SPI。
App Store 審查對私有 API 有風險，但 ADR 0009 已定 FMP 不上架任何商店，iOS 走側載。

### 選項 B：macOS（以及之後 iOS）也用 QuickJS

- **B1 `quickjs_engine` 0.1.6**（pub.dev，2026-09-30 發佈）：flutter_js 的 API 相容 fork，QuickJS-ng 0.14.0，
  附 macOS 預編 dylib＋SPM／CocoaPods，五平台。`QuickJsRuntime2` 的欄位（`moduleHandler`、
  `hostPromiseRejectionHandler`、`timeout`、`memoryLimit`、`stackSize`）都在；memoryLimit 已修
  （changelog 0.1.6）。**但 native bridge 沒有 `JS_SetInterruptHandler`**（`native/cxx/libfastdev_quickjs_runtime.cpp`
  只有 `JS_SetMemoryLimit`，interrupt 只在 `quickjs-libc.c`），`timeout` 看起來同 flutter_js 一樣無作用，
  同步無窮迴圈仍回收不了。單一作者、發佈在名為 `flutter_full_svg_support` 的 repo，likes 4。
- **B2 `flutter_qjs_next` 1.5.2**（2026-09-26）：QuickJS 2026-06-04，`QuickJsRuntime2` 同名同簽名
  （`moduleHandler`、`hostPromiseRejectionHandler`、`JSInvokable`），有 `timeout`（`cxx/ffi.cpp:188`
  `JS_SetInterruptHandler`）與預設 64 MiB 的 `memoryLimit`（`ffi.cpp:244`），五平台，Flutter ≥ 3.44。
  單一作者、likes 1、30 天下載約 650。ADR 0014 已因「單一作者、低採用」未採用這兩個。
  若採用，則**所有平台一起換**，能同時解掉「卡住的執行緒回收不了」（三個桌面／Android 平台都受益），
  但 API 差異（例如 `evaluate` 簽名、`JSInvokable` 行為、`FREE_OBJECT`）要逐項驗。
- 其他查到的：`fjs` 3.3.2（Rust＋QuickJS，fluttercandies，2026-09-30，24 likes，五平台，API 完全不同）、
  `qjs` 0.2.2（2026-10-26，Dart QuickJS 綁定，pubspec 沒宣告 Flutter plugin 平台）、`flutter_qjs` 0.3.7
  （2022 後無更新）、`flutter_quickjs`（只 Android／iOS）。維護程度我只看了 pub.dev metadata，沒有深查。
- B 的代價：macOS 要帶 QuickJS 二進位進 App、sandbox 與 hardened runtime 下的 dylib 簽署；iOS 之後也走同一條，
  QuickJS 是純直譯器，沒有 JIT 問題，iOS 允許（沒有動態程式碼產生）。

### 選項 C：維持 flutter_js 的 QuickJS 給三平台，macOS 自建 flutter_js 缺的原生庫

flutter_js 沒附 C 原始碼（上游 `abner/quickjs-c-bridge`，最後 push 2021-04，notes.md），要自己 fork 該 bridge
並編進 macOS。等於自己維護 QuickJS 綁定，不建議當首選。

### 比較

| | A（JSC） | B2（flutter_qjs_next 全平台統一） | B1（quickjs_engine） |
|---|---|---|---|
| 要改的程式 | 重寫引擎層＋原生 SPI 外掛 | 換依賴、對 API 差異修改，其餘沿用 | 換依賴，最小 |
| 看門狗中斷 | 可（私有 API） | 可（`timeout`） | 不可（同現況） |
| 記憶體上限 | 無 | 有 | 有 |
| 引擎一致性 | macOS／iOS 與其他不同 | 全平台一致 | 全平台一致 |
| 套件風險 | 無外部套件；用私有 SPI | 單一作者新套件 | 單一作者 fork |
| macOS 測試 | 需要 SPI 在 flutter_tester 可用 | 需要載 dylib（可能） | 預編 dylib 現成 |

## 6. 實驗記錄（`<暫存目錄>/jsc/`）

- `t.c`／`t2.c`：能力探測（TextEncoder 等為 undefined；BigInt、Intl 存在；ES2020 語法通過；microtask 排空時機；
  `import()` 失敗訊息；錯誤與 stack 格式；遞迴上限）。
- `t4.c`：`JSContextGroupSetExecutionTimeLimit`，NULL callback、非主執行緒、callback 在執行緒本身呼叫。
- `t5.m`：ObjC `moduleLoaderDelegate` + `JSScript` 載入 `export async function search`，動態 `import()` 通過。
- `t6.c`：JSC 全域名稱與 `_builtIns` 的差集。
- `dl/`：下載的 `quickjs_engine` 0.1.6、`flutter_qjs_next` 1.5.2（只用來讀 README／原始碼）。
- **沒有**做的：在 Dart／Flutter 內實際用 `flutter_js` 跑 JSC（`flutter pub get` 會動 app/ 的檔，且 flutter_js
  依賴 Flutter SDK，無法用純 `dart` 跑）；沒有量 JSC 在 Release 無 allow-jit 時的速度；沒有建置
  `quickjs_engine`／`flutter_qjs_next` 的 macOS 版。

## Caveats / Not Found

- `flutter_js` 的 JSC 路徑我只讀了原始碼，沒有在 Flutter 內實跑。
- SPI（`moduleLoaderDelegate`、`JSScript`、`JSContextGroupSetExecutionTimeLimit`、
  `JSGlobalContextSetUnhandledRejectionCallback`）是非公開 API：在這台 macOS 26 級的系統可用，OS 升級後可能變；
  無法在 flutter_tester 保證可得。
- 沒找到 repo 內有 regex 解析 JS 錯誤字串的程式碼；測試是否斷言 QuickJS 特有的訊息文字沒有全面查。
- 沒驗證 `flutter_qjs_next` 在 `flutter test`（macOS）如何載入原生庫。

## 建議

**短期（讓 macOS 先能跑插件，風險最低）：選項 B2 的方向，但先在拋棄式分支驗證**。理由：
(1) 現有程式碼以 `QuickJsRuntime2` 的 `moduleHandler`／`JSInvokable`／Future↔Promise 為核心，B2 同名同簽名，
改動最小；(2) 它順便給三個現有平台 `timeout` 中斷與 `memoryLimit`，補上目前 `app/AGENTS.md:1264` 寫的
已知限制；(3) 引擎統一後 macOS 與 iOS 都不需要私有 SPI 與原生外掛，契約測試守得到所有平台；
(4) 測試可以像現在一樣預載 dylib。主要代價是依賴換成單一作者的新套件（ADR 0014 當初的顧慮），要升一則 ADR 補充。
若不想換依賴，退而求其次是 B1（改動最小，但沒有中斷）。

**選項 A（JSC）技術上可行，我實測過 module loader、時間上限都能動，但它需要私有 SPI 與原生外掛，且
macOS 的測試與雙引擎行為差異要長期扛**；若擁有者想維持 ADR 0014 的「iOS／macOS 用 JSC」，建議當作第二步，
等 B2 驗證後再比較。

只有實機能回答的開放問題：

1. `flutter_qjs_next`（或 `quickjs_engine`）的 macOS 版在 `flutter build macos --flavor dev --debug` 與
   `--release`（sandbox＋hardened runtime，簽署）後 dylib 是否正確載入？universal 或僅 arm64？
2. 換引擎後 `plugin_runtime_benchmark_test.dart -d macos` 的建立／search 往返／RSS 數字，以及 QuickJS-ng 對
   YouTube.js 793 KB 插件的載入時間。
3. `timeout` 的 interrupt 在 isolate 內被觸發後，插件 context 是否可繼續使用，還是必須丟棄；與現有看門狗
   （Ping／Pong＋`Isolate.kill`）如何合併。
4. 若走 A：Release 沒有 `allow-jit` 時 JSC 的速度（YouTube.js 載入與 search）；`moduleLoaderDelegate` 在
   Dart 端（ObjC interop）或 Swift 外掛中的最小實作，及 flutter_tester 能否用。
5. 現有 `test/plugins/**` 與契約測試在新引擎上有沒有斷言 QuickJS 特有的錯誤訊息／全域清單
   （`_builtIns` 一定要改）。
