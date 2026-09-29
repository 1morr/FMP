# flutter_js 查證與實測（M1 PR 9a）

- 日期：2026-09-30
- 環境：Flutter 3.47.5（Dart 3.13.4）、Windows 11 Pro for Workstations 10.0.26200、
  Android 模擬器 `emulator-5554`（Android 17，x86_64）。
- 套件：`flutter_js` 0.8.7（pub.dev 最新，2026-01-27；`https://pub.dev/api/packages/flutter_js`）。
- 所有結論來自套件原始碼（pub cache 的 `flutter_js-0.8.7/`）、上游 repo（`gh api`）或本機實測，
  逐條附來源。

## 1. API 與行為（原始碼）

| 問題 | 結論 | 來源 |
|---|---|---|
| 各平台用哪個引擎 | `getJavascriptRuntime()`：Android、Windows、Linux 是 `QuickJsRuntime2`（dart:ffi），其他（iOS、macOS）是 `JavascriptCoreRuntime` | `lib/flutter_js.dart` |
| `getJavascriptRuntime()` 能不能用 | 不用：它預設 `xhr: true` 會裝 `fetch`／`XMLHttpRequest`（走 `package:http`，繞過宿主網路層），並裝 promise 輪詢（每 20ms 的 `Timer.periodic`）| `lib/flutter_js.dart`、`lib/extensions/fetch.dart`、`lib/extensions/handle_promises.dart` |
| 建構子另外裝了什麼 | `QuickJsRuntime2` 建構子呼叫 `init()`：`sendMessage`、`console`（寫到 `print`）、`setTimeout`（Timer 到期時呼叫 `evaluate`；`evaluate` 會在 runtime 釋放後重建引擎）| `lib/javascript_runtime.dart` 的 `init`、`_setupSetTimeout`；`lib/quickjs/quickjs_runtime2.dart` 的 `evaluate` → `_ensureEngine` |
| 執行腳本 | `evaluate(code, name:, evalFlags:)`，同步回 `JsEvalResult`（`rawResult` 是轉成 Dart 的值）| `quickjs_runtime2.dart` |
| Promise／microtask | JS 回傳的 Promise 轉成 Dart `Future`（`_jsToDart` 對 `jsIsPromise` 掛 `then`）；Promise 工作**不會自己跑**，要呼叫 `executePendingJob()`（→ `JS_ExecutePendingJob` 迴圈）| `lib/quickjs/wrapper.dart`、`quickjs_runtime2.dart` 的 `_executePendingJob` |
| JS 呼叫 Dart 的非同步函式 | Dart 的 `Function` 轉成 JS 函式（`JSInvokable`）；它回傳的 `Future` 轉成 JS Promise（`jsNewPromiseCapability`，Future 完成時呼叫 resolve／reject）。不需要 `sendMessage` 的 JSON 通道 | `wrapper.dart` 的 `_dartToJs` |
| 每插件一個 runtime | 每個 `QuickJsRuntime2` 各自 `JS_NewRuntime` + `JS_NewContext`，堆積不共用 | `quickjs_runtime2.dart` 的 `_ensureEngine`；實測見 §3 |
| ES module | 有 module loader：建構參數 `moduleHandler(name) → 原始碼`，由 `import()` 觸發（`JS_SetModuleLoaderFunc`）；`moduleHandler` 丟錯時 import 被拒絕 | `quickjs_runtime2.dart`；上游 `abner/quickjs-c-bridge` 的 `cxx/libfastdev_quickjs_runtime.cpp` 的 `jsNewRuntime`；實測見 §3 |
| 釋放 | `dispose()`：關 port、`JS_FreeContext`、銷毀所有 Dart 端持有的 JS 參照、`JS_FreeRuntime`；洩漏的參照只 `print` | `quickjs_runtime2.dart` 的 `dispose`、`close`；`lib/quickjs/ffi.dart` 的 `jsFreeRuntime` |
| 未處理的 rejection | `hostPromiseRejectionHandler`；QuickJS 在拒絕的當下沒有處理者就回報，之後接上也不收回 | 上游 bridge 的 `js_promise_rejection_tracker`（`is_handled` 為真才略過）；實測：`async` 函式拋錯、呼叫端隨後 `await` 也會報 |
| 逾時／記憶體上限 | **沒有作用**。Dart 端把 `timeout` 傳給 `jsNewRuntime`，但上游 bridge 的 `jsNewRuntime(JSChannel)` 只收一個參數、沒有 interrupt handler；Windows 的 `quickjs_c_bridge.dll` 匯出 65 個符號，沒有 `jsSetMemoryLimit`、沒有任何 interrupt 相關符號（傳 `memoryLimit` 會在 lookup 時拋錯）| `ffi.dart` 的 `jsNewRuntime`、`jsSetMemoryLimit`；上游 bridge 原始碼；DLL 匯出表（以 Python 解析 PE）；實測：`timeout: 1000` 下 `while(true){}` 卡住 3 分鐘直到測試被停 |

上游狀態（`gh api repos/abner/flutter_js`、`repos/abner/quickjs-c-bridge`，2026-09-30）：flutter_js 最後一次
commit 2026-01-27；quickjs-c-bridge 最後 push 2021-04-13。

### 採用的做法

- 繼承 `QuickJsRuntime2`、覆寫 `init()` 為不做事：不裝 `console`、`setTimeout`、`sendMessage`。
  測試逐一比對全域名稱（`plugin_runtime_test.dart` 的 `the global object has only ...`）。
- 宿主 API 以一段 prelude（`lib/plugins/runtime/js_prelude.dart`）建出唯讀的 `fmp`；兩個 Dart 函式
  只經閉包傳入，全域看不到。
- 插件腳本是 **ES module**（`export async function search(...)`），以 `import('fmp-plugin')` 載入，
  loader 只對這個名稱回傳腳本。所以不需要改用全域寫法，ADR 0014 的補充句不用改。
- Promise 工作：呼叫之後、每次宿主非同步函式完成後各執行一次；後者用 `scheduleMicrotask`（見 §4）。
- 每個插件的 QuickJS 在自己的背景 isolate（§6，擁有者 2026-09-30 決定）。
- iOS、macOS 目前也走 `QuickJsRuntime2`（App 在這兩個平台還沒支援）；JavaScriptCore 在那兩個平台的
  任務處理。

## 2. QuickJS 能否在 `flutter test` 內載入（§7）

結論：**可以，裸 `flutter test` 就行，不必先建置桌面版，也不必設環境變數。**

- flutter_js 在測試裡（`FLUTTER_TEST=true`，flutter_tools 會設）以檔名開原生庫：Windows
  `quickjs_c_bridge.dll`；Linux `LIBQUICKJSC_TEST_PATH` 或 `libquickjs_c_bridge_plugin.so`
  （`ffi.dart` 的 `_qjsLib`）。套件在 `windows/shared/`、`linux/shared/` 內附預先編譯的這兩個檔。
- 實測（Windows）：不做任何事時載入失敗（`error code: 126`）。先以絕對路徑
  `DynamicLibrary.open(<pub cache>/flutter_js-0.8.7/windows/shared/quickjs_c_bridge.dll)`，之後 flutter_js
  以檔名開就拿到同一份（LoadLibrary 對已載入的同名模組直接回傳，Microsoft Learn〈Dynamic-link library
  search order〉）。
- Linux：`libquickjs_c_bridge_plugin.so` 的 SONAME 就是 `libquickjs_c_bridge_plugin.so`，只依賴
  `libstdc++`、`libm`、`libgcc_s`、`libc`（解析 ELF dynamic section）。glibc 的 dlopen 會比對已載入物件的
  SONAME。以 Docker `python:3-slim`（Debian、glibc）實測：以檔名 dlopen 先失敗；以絕對路徑載入後再以
  檔名 dlopen 成功，拿到同一個 handle，`jsNewRuntime` 符號存在。**完整的 `flutter test` 在 Linux 上只能在
  CI 驗證**（本機沒有 Linux 的 Flutter）。
- 實作：`app/test/support/quickjs.dart` 從 `.dart_tool/package_config.json` 找 flutter_js 的位置並預先載入，
  `test/flutter_test_config.dart` 對每個測試檔呼叫；Windows、Linux 找不到或載入失敗就拋錯（CI 不會默默跳過）。
- 所以 CI 的 `app` job 不用加步驟，`flutter test` 就會跑到 QuickJS 的測試。`integration_test` 的退路不需要。

## 3. 探針實測（Windows，`flutter test`）

- `evaluate('1+2')` → `3`；Dart 函式回 `Future` → JS `await` 拿到值；JS `async` 函式 → Dart `Future`。
- `import('plugin')` 經 `moduleHandler` 載入 `export function search…`，拿到 namespace（`search,x`）；
  `import('other')`（handler 丟錯）→ Promise 被拒絕。直接以 `JSEvalFlag.MODULE` evaluate 不回傳匯出，不用。
- 兩個 runtime：一個設 `globalThis.secret`，另一個 `typeof secret` 是 `undefined`。
- 同步 `throw` → `JsEvalResult.isError`；Dart 函式丟錯 → JS 的 `catch` 拿到；參數個數不合 →
  JS 拿到 `NoSuchMethodError`；`JSON.stringify(2**53)` 正常（沒有 BigInt）。

## 4. 實測數字（量測入口 `app/integration_test/plugin_runtime_benchmark_test.dart`）

方法：`flutter test integration_test/plugin_runtime_benchmark_test.dart -d <裝置>`（dev flavor、**debug
模式**：`flutter test` 不支援 profile；x86_64 模擬器不能跑 profile）。Stopwatch 量主 isolate 看到的時間。

- 「建立 runtime」：載入一個空插件的完整流程：解析 manifest、建 HTTP client、**spawn 背景 isolate**、
  QuickJS runtime、prelude、module 載入、匯出檢查。
- 「載入測試插件」：同上但換成 `fmp-test`。
- 「search 往返」：DTO 轉 JSON、送到背景 isolate、Promise、一次 `fmp.storage.get`（跨 isolate 回主 isolate
  查 drift 記憶體資料庫）、結果送回、驗證。
- 「宿主呼叫往返（跨 isolate）」：search 裡連續 20 次 `await fmp.credentials.get()`，
  （中位數 − 沒有宿主呼叫的 search 中位數）÷ 20。
- 「純 Dart isolate 往返」：對照組，spawn 一個只會回送的 isolate，量一次送收。
- RSS 是 `ProcessInfo.currentRss` 的差（Dart 不能強制 GC，數字有雜訊；負值就是雜訊）。

### 背景 isolate 版（現行）

| 項目 | Windows（3–4 次） | Android 模擬器（3–6 次） |
|---|---|---|
| 第一次建立 runtime（含 dlopen、JIT 首次編譯、spawn） | 49–82 ms | 64–206 ms |
| 建立 runtime（空插件，9 次中位數） | 1.5–2.0 ms | 13–18 ms |
| 載入測試插件（9 次中位數） | 1.5–1.6 ms | 11–21 ms |
| 第一次 search | 33–42 ms | 72–106 ms |
| search 往返（21 次中位數，含一次宿主非同步呼叫） | 0.8–0.9 ms | 11–20 ms |
| search 往返，沒有宿主呼叫 | 0.3 ms | 5.8–15.5 ms |
| 宿主呼叫往返（跨 isolate，每次） | 0.16–0.22 ms | 6.4–8.8 ms |
| 純 Dart isolate 往返（對照） | 0.035 ms | 1.8–8.2 ms |
| 1 個 runtime 的 RSS 增量 | −0.4–2.9 MB | 1.0–1.1 MB |
| 3 個 runtime 的 RSS 增量 | 4.6–9.0 MB | 3.1–3.4 MB |

判讀：Windows 上背景 isolate 幾乎沒有成本。Android 模擬器上每次跨 isolate 的來回是毫秒級，而且純 Dart 的
對照組本身就在 1.8–8.2 ms 之間跳，所以主要是模擬器上 isolate 訊息的延遲，不是 QuickJS；插件每多一次宿主
呼叫約多 7 ms。網路請求本身是幾十到幾百毫秒，對搜尋、解串流影響小；要準確的數字得在實機以 profile 模式量
（目前沒有實機）。記憶體：背景 isolate 與 QuickJS 合計每個插件約 1–3 MB。

### 主 isolate 版（已被取代，留作比較）

| 項目 | Windows（3 次） | Android 模擬器（3 次） |
|---|---|---|
| 第一次建立 runtime | 63–97 ms | 89–149 ms |
| 建立 runtime（空插件，9 次中位數） | 1.5–3.1 ms | 3.0–8.3 ms |
| 載入測試插件（9 次中位數） | 1.7–3.4 ms | 2.7–6.8 ms |
| 第一次 search | 53–133 ms | 108–184 ms |
| search 往返（含一次宿主非同步呼叫） | 1.1–2.2 ms | 2.4–3.2 ms |
| search 往返，沒有宿主呼叫 | 0.4–1.2 ms | 1.2–1.5 ms |
| 1 個 runtime 的 RSS 增量 | −1.4–2.9 MB | 1.2–1.3 MB |
| 3 個 runtime 的 RSS 增量 | 2.8–8.6 MB | 2.2–3.3 MB |

**發現並修正**（主 isolate 版時）：宿主非同步函式完成後原本以 `Timer.run` 執行 Promise 工作；Android 的 UI
isolate 上它要等下一輪訊息迴圈，search 往返中位數 16–31 ms。改成 `scheduleMicrotask` 後 2.4–3.2 ms。背景
isolate 版沿用 `scheduleMicrotask`。

## 5. 建置與相容性

- Android：flutter_js 的 `android/build.gradle` 把 Kotlin `jvmTarget` 寫死 1.8、沒設 Java 的 `compileOptions`，
  AGP 9.1 預設 Java 11，`compileDebugKotlin` 失敗（Inconsistent JVM Target Compatibility）。在
  `app/android/build.gradle.kts` 只對 `flutter_js` 子專案把 Java 設成 1.8 後建置成功。
- Android 原生庫 `libfastdev_quickjs_runtime.so` 來自 jitpack 的 `fast-development/android-js-runtimes`
  0.3.6（套件的 build.gradle 自己加了 jitpack repository）。
- Flutter 3.47.5 建置時警告 flutter_js「apply Kotlin Gradle Plugin (KGP)」，要遷移到 Built-in Kotlin；目前只是
  警告，之後的 Flutter 若改成錯誤，要等上游或自己 fork。
- 同步的無窮迴圈中斷不了（§1 的逾時列）：由 §6 的背景 isolate 與看門狗處理，卡住的執行緒仍回收不了。

## 6. 背景 isolate 與看門狗（擁有者 2026-09-30 決定；prd 擁有者決定 7、ADR 0014 補充）

- 每個插件一個 `Isolate.spawn` 的背景 isolate（`lib/plugins/runtime/plugin_worker.dart`），裡面是那個插件的
  QuickJS。主 isolate（`plugin_runtime.dart`）執行宿主 API 的網路、storage、憑證、log，以訊息回覆
  （`worker_protocol.dart`）；網域與插件 id 的檢查都在主 isolate。`crypto` 在背景 isolate 算。
- 原生庫：`DynamicLibrary.open` 是整個行程共用的；背景 isolate 裡 flutter_js 以檔名再開一次就拿到已載入的那
  份。`flutter test`（Windows）與 App（Windows dev 建置、Android 模擬器）都實測可以：所有 runtime 測試現在
  都在背景 isolate 跑 QuickJS。
- 看門狗：每次呼叫（含載入，從 spawn 完成起算）30 秒。到期時送 `Ping`，2 秒內收到 `Pong` 就是「在等東西」
  （例如慢的網路），這次呼叫以 `NetworkError` 失敗、插件照常；收不到就判定卡住：`PluginHealth.unresponsive`、
  進行中與之後的呼叫以 `UnexpectedError` 失敗（插件的 bug：不可重試、通用訊息）、`log.report`、
  `Isolate.kill(priority: immediate)`、停用到 App 重啟。背景 isolate 意外結束（`onError`／`onExit`）同樣處理。
- **與指示的差異**：指示是「逾時就標成沒有回應」。加了探測是因為呼叫的 30 秒也包含等網路（網路層的連線逾時
  10 秒、最多重試 2 次），只看逾時會把網路慢的插件停用到重啟；只有事件迴圈也不動（同步卡住）才停用。
- **剩下的限制**：`Isolate.kill` 要等 isolate 回到 Dart 的事件迴圈才生效，停在 QuickJS 原生碼裡的執行緒
  會一直佔著一個核心，直到行程結束。
- 實測（`flutter test`，Windows）：`search` 跑 `while(true){}`、逾時 500 ms、探測 300 ms：呼叫在期限後以
  `UnexpectedError` 失敗、插件轉成沒有回應；卡住期間主 isolate 的計時器照常觸發、另一個插件照常回應。
