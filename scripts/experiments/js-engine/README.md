# 實驗：JS 引擎（M0 票 03）

插件要跑在哪個 JS 引擎：`fjs` 或 `flutter_js`（加自編 QuickJS）。標準照 brief §17：四平台同一引擎、能中斷無窮迴圈、能設記憶體上限、支援 async；另測 JS await Dart 提供的 async 函式，並量引擎與 isolate 的配置（plan §1.1）。

實驗程式可丟棄，但留在這裡：換 Flutter 或套件版本時照〈怎麼跑〉重量。

## 結果（2026-11-11）

環境：Flutter 3.47.5（Dart 3.13.4），macOS 27.0.1（Xcode 27.1），iOS 27.1 模擬器，Android 模擬器 API 37（`Medium_Phone_API_37.0`，1 核），Windows 11（`winpc`，Build 26200）。全部是 debug 建置，時間只供比較。

| 候選 | 平台 | 同一引擎 | 中斷無窮迴圈 | 記憶體上限 | Dart await Promise | JS await Dart async | isolate 配置 | 卡住不拖累其他引擎 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fjs 3.3.2 | Android | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| fjs 3.3.2 | iOS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| fjs 3.3.2 | macOS | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| fjs 3.3.2 | Windows | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| flutter_js 0.8.7 | Android | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| flutter_js 0.8.7 | iOS（自編 QuickJS） | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| flutter_js 0.8.7 | macOS（自編 QuickJS） | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| flutter_js 0.8.7 | Windows | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |

前五欄是票的標準（四項加 async 宿主呼叫），後兩欄是 isolate 配置的量測。每格的細節在 `results/<候選>-<平台>.json`；`python3 summarize.py results/*.json` 印出來，`--table` 印上表（結果寫的版本和 probe 的 `pubspec.lock` 不同時會警告）。

### fjs 3.3.2

- **引擎**：四平台都是 rquickjs 包的 QuickJS-NG（JS 的 stack 格式是 QuickJS 的）。Android、Windows 由 Cargokit 從 Rust 原始碼編；iOS、macOS 走 SwiftPM，用 pub 套件裡附的上游預編譯 `darwin/fjs/Binaries/fjs.xcframework.zip`（約 20 MB），沒有在本機編，也沒核對它和 crate 是同一份原始碼編的。
- **中斷**：沒有單次呼叫的中斷，只能 `engine.close()`。量了三種迴圈：頂層 `while(true){}`、`await` 之後的迴圈、`setTimeout` 回呼裡的迴圈。跑 500 ms 後 close，三種的行程 CPU 都從每秒約 1000 ms 掉到 0–90 ms（Android 模擬器底噪較高），證明原生執行緒上的迴圈真的停了；close 本身 ≤ 2 ms。前兩種的 eval 以 `CANCELLED_ERROR` 結束；timer 那種 eval 早就回來了，被中斷的回呼變成「未處理的背景錯誤」，`close()` 會把它拋出來（`Unhandled JavaScript background error: Error: interrupted`），呼叫端要接住。引擎關掉就報廢，新建的引擎正常。
- **記憶體上限**：`JsEngineRuntimeOptions(memoryLimit:)` 設 32 MiB，配置迴圈在 JS 裡拿到可捕捉的 `InternalError: out of memory`，同一個引擎之後還能用。
- **async**：`eval` 直接等 Promise 完成（42）。宿主函式只有單一 bridge：JS 端 `fjs.bridge_call(value)` 回 Promise，Dart 端拿到一個值自己分派；實驗包成 `hostDelay(ms, value)`，JS await 到 Dart Future 的結果（`pong!`）。
- **isolate**：JS 跑在 fjs 的 Rust 執行緒上，Dart 端的呼叫都是 async，主 isolate 最長停頓 10–35 ms（量測用的 timer 是 10 ms）。建一個引擎 ≤ 17 ms。背景 isolate 各自 `LibFjs.init()` 後也能用，但不需要。
- **全行程只有 2 條 JS 執行緒**：所有引擎共用一個 tokio runtime，`libfjs/src/runtime/executor.rs` 寫死 `worker_threads(2)`，不能設定。實測：1 個引擎卡在無窮迴圈時，別的引擎照常建立與執行；2 個以上卡住時，連新建引擎都 5 秒內回不來。同時 `close()` 卡住的引擎後立刻恢復（≤ 2 ms）。4 個引擎同時跑 CPU 工作約花 1 個的 2–2.5 倍時間（Android 模擬器只有 1 核，約 3 倍）。
- **沙箱面**：只開 `timers`、`console` 兩個內建模組時，JS 看到的 `fetch`、`XMLHttpRequest`、`WebSocket`、`require`、`process` 都是 `undefined`。fjs 帶有 llrt 的 `fs`、`net`、`child_process`、`fetch` 等模組，建立引擎時指名才會開。
- Windows 的 CPU 工作比其他平台慢約 10 倍（4.5 秒對 0.3 秒）：debug 建置下 Cargokit 用 Rust 的 debug profile 編，Windows 上差距特別大。不影響標準的判定。

### flutter_js 0.8.7（加自編 QuickJS）

- **引擎**：套件預設的 `getJavascriptRuntime()` 在 iOS、macOS 回 `JavascriptCoreRuntime`（實測 stack 格式是 JSC 的），Android、Windows 回 `QuickJsRuntime2`。實驗一律直接用 `QuickJsRuntime2`；iOS、macOS 的 QuickJS 由 `probe_flutter_js/packages/fmp_quickjs` 編進 App（上一輪的做法，原始碼和 flutter_js 在 Android 用的 android-js-runtimes 0.3.6 逐檔相同，見它的 `SOURCE.md`）。這樣四平台都是 QuickJS 2021-03-27，但 Android 是 jitpack 下載的 `.so`、Windows 是套件 repo 裡 2021 年提交的 `quickjs_c_bridge.dll`，只有 Apple 是自己編的。
- **中斷**：失敗，四平台一致。`QuickJsRuntime2(timeout: 500)` 不會中斷（3.7 秒後還在跑）：橋接 `quickjs_runtime.cpp` 有裝 interrupt handler，但比較的起點 `op->start` 從來沒有被設值。退路是放在背景 isolate 再 `Isolate.kill(priority: immediate)`：isolate 3 秒內沒有結束，行程 CPU 維持每秒約 1000 ms，原生執行緒一直空轉到行程結束。
- **記憶體上限**：Android、Windows 失敗：`QuickJsRuntime2(memoryLimit:)` 第一次 evaluate 時拋 `Failed to lookup symbol 'jsSetMemoryLimit'`，套件附的二進位沒有這個符號。iOS、macOS 通過，只因為自編版另外補了這個符號（`fmp_extras.c`）。
- **async**：套件文件沒寫，但 `QuickJsRuntime2` 繼承了 flutter_qjs 的轉換：JS 回傳的 Promise 在 Dart 端是 Future，傳進 JS 的 Dart 函式回傳 Future 時在 JS 端是 Promise。要自己定時呼叫 `executePendingJob()` 推進 job queue。`evaluate` 是同步 FFI 呼叫，CPU 工作會卡住呼叫它的 isolate（實測主 isolate 停頓 = 工作時間），所以每個插件要放自己的背景 isolate。各 isolate 的 runtime 互不影響：4 個卡在無窮迴圈時，另一個 isolate 照常算出 1+2（但卡住的那幾條殺不掉）。
- **公平性**：表上的 ❌ 是套件現況。要讓 flutter_js 過，得四平台都自編 QuickJS（換掉 jitpack 的 `.so` 與 repo 裡的 dll），並自己修橋接的 interrupt 與補 `jsSetMemoryLimit`，等於自己維護一套 QuickJS 綁定；flutter_js 只剩 Dart 包裝。
- **其他實測到的問題**：Android 建置失敗於 Kotlin（jvmTarget 1.8）與 Java（11）不一致，要在 App 的 `gradle.properties` 加 `kotlin.jvm.target.validation.mode=warning` 才建得過（上游 #191）。macOS 上 `dispose()` 套件預設的 JavaScriptCore runtime 之後，套件的 Promise 輪詢 timer 還會對它 evaluate，行程 SIGSEGV。

## 檔案

| 路徑 | 內容 |
| --- | --- |
| `probe_common/` | 兩個候選共用的測項（JS 腳本、計時、主 isolate 停頓、行程 CPU 時間）與 App 進入點 |
| `probe_fjs/`、`probe_flutter_js/` | 各一個 Flutter App，啟動就跑全部測項，結果寫到畫面、log 與 `<暫存目錄>/js-engine-probe-<候選>.json`，跑完結束行程 |
| `run.sh` | macOS、iOS 模擬器、Android 模擬器：建置、執行、取回結果 |
| `run-windows.sh`、`windows/` | Windows：同步到 `winpc`，以排程工作在桌面工作階段建置與執行，取回結果 |
| `summarize.py` | 印結果細節或總表 |
| `results/*.json` | 上表的原始結果。原始 log（`raw-*`）含本機路徑，不提交 |

## 怎麼跑

```bash
cd scripts/experiments/js-engine
./run.sh fjs macos
IOS_DEVICE=<模擬器 UDID> ./run.sh fjs ios          # 預設 booted
./run.sh fjs android                               # adb 唯一的裝置，或設 ANDROID_SERIAL
./run-windows.sh fjs                               # VERBOSE=1 讓 flutter build 加 -v
# 把 fjs 換成 flutter_js 測另一個候選
python3 summarize.py --table results/*.json
```

需要：

- Flutter 3.47.5；Xcode 與開著的 iOS 模擬器；開著的 Android 模擬器。
- fjs 在 Android 與 Windows 從原始碼編 Rust：主機要有 rustup，Rust ≥ 1.95（fjs 的 `rust-version`）。第一次建置會下載 crate、Android 會自動裝 Rust target，要幾分鐘。
- **Windows 的 rustup default host 要是 `x86_64-pc-windows-msvc`**。Cargokit 以 `rustup run stable` 建置，default host 是 `-gnu` 時會拿 gnu 工具鏈，`libloading` 要 MinGW 的 `dlltool.exe` 而失敗。`winpc` 原本是 gnu，2026-11-11 已用 `rustup set default-host x86_64-pc-windows-msvc` 改成 msvc（改回：把 msvc 換成 gnu）。
- `winpc`：ssh 主機別名、預設 shell 是 PowerShell、擁有者已登入桌面（排程工作用互動登入）。遠端目錄是 `%USERPROFILE%\fmpx\js-engine`。

量測說明：

- **中斷**：無窮迴圈跑 500 ms 後中斷；接著比較「迴圈在跑時」與「中斷後」各 1 秒的行程 CPU 時間（`getrusage`／`GetProcessTimes`），少了至少半顆核心才算原生執行緒真的停了。只看 Dart 端的 Future 有沒有回來不夠：Future 可以先回來而原生執行緒還在跑。
- **記憶體上限**：32 MiB 上限；配置總量封頂在約 256 MB，沒被擋住時回 `not limited`，不會讓行程被系統殺掉而拿不到結果。
- Android 不用 `flutter test`：同一台機器上別的 session 重啟 adb daemon 時，`flutter test` 會判「did not complete」，但裝置上的 App 其實跑完了。所以 App 自己跑完寫檔，主機事後輪詢 logcat、用 `run-as` 取檔。
