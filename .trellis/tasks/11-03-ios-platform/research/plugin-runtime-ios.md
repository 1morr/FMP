# Research: 插件執行環境在 iOS（flutter_js 0.8.7 + fmp_quickjs / QuickJS）

- **Query**: iOS 上插件 runtime 用什麼引擎、怎麼把 `fmp_quickjs` 的 QuickJS 編進 App 讓 `DynamicLibrary.process()` 找得到符號、背景時 JS 能不能跑、記憶體與執行緒限制。
- **Scope**: mixed（讀 repo 與 pub cache 原始碼；在 iOS 模擬器與 `--no-codesign` 真機建置上實測；Apple 文件）
- **Date**: 2026-11-04
- 證據標記：**實測**（我跑了並讀回結果）、**文件**（附連結）、**原始碼**（附檔案與行）。
- 實驗位置：`<scratchpad>/ios-runtime/`（`probe/` 是最小 Flutter 專案；`fmp_quickjs_ios/` 是 `app/packages/fmp_quickjs` 的複本，加上 `ios/` podspec 與 `ios/Classes/` 轉接檔）。repo 內沒有改任何檔案。

## 結論先講

1. **iOS 預設引擎是 JavaScriptCore，但 FMP 不走那條路**：`getJavascriptRuntime()` 在非 Android／Windows／Linux 時回 `JavascriptCoreRuntime`（原始碼）。FMP 的 `plugin_worker.dart` 直接繼承 `QuickJsRuntime2`，不呼叫 `getJavascriptRuntime()`（原始碼），所以 iOS 要靠 `fmp_quickjs` 把 QuickJS 編進 App。
2. **`fmp_quickjs` 加一個 iOS 入口就能用（實測）**：`pubspec.yaml` 的 `flutter.plugin.platforms` 加 `ios: ffiPlugin: true`、新增 `ios/fmp_quickjs.podspec` 與 `ios/Classes/*` 轉接檔（內容與 `macos/` 同，podspec 只換 `s.dependency 'Flutter'`、`s.platform = :ios, '13.0'`）。在 iPhone 模擬器（arm64）跑：`DynamicLibrary.process().lookup` 55 個符號全部找得到，`QuickJsRuntime2().evaluate('1+2+"x"')` 回 `3x`，配置 100 萬個物件正常。
3. **預設的 `use_frameworks!`（動態 framework）不用任何額外設定**；**改成靜態連結（`use_frameworks! :linkage => :static` 或不用 `use_frameworks!`）會全部找不到（55／55 missing，實測）**，因為沒有任何東西引用 `quickjs_runtime.cpp.o`，linker 不把它拉進來。用 `-Wl,-u,_jsNewRuntime -Wl,-u,_jsSetMemoryLimit`（podspec 的 `user_target_xcconfig`）可救：debug 模擬器 55／55 找得到並能跑，release 真機建置 `nm` 55／55 都在（實測）。
4. **iOS 禁止 JIT 對 QuickJS 沒影響**：QuickJS 是 bytecode 直譯器，原始碼裡沒有 `MAP_JIT`／`mprotect`／`PROT_EXEC`（原始碼，grep 過 `app/packages/fmp_quickjs/src`）。
5. **背景**：沒有 `UIBackgroundModes: audio` 時，App 進背景後 Dart isolate 與 JS 一起被凍結（模擬器實測：背景 28 秒內沒有任何 tick，回前景才繼續）。有 `audio` 且 audio session 在播放時，行程持續執行，插件 isolate 可以解析下一首網址（文件；本次沒有在實機實測，見「沒查到」）。

## 1. flutter_js 在 iOS 的引擎與 FMP 怎麼選

### Files Found

| File Path | Description |
|---|---|
| `<pub-cache>/flutter_js-0.8.7/lib/flutter_js.dart:25-50` | `getJavascriptRuntime()`：`Platform.isAndroid`→`QuickJsRuntime2`；Windows、Linux→`QuickJsRuntime2`；其餘（iOS、macOS）→`JavascriptCoreRuntime` |
| `<pub-cache>/flutter_js-0.8.7/lib/quickjs/ffi.dart:116-131` | `_qjsLib`：iOS、macOS 都落到最後的 `DynamicLibrary.process()`；Android 才 `DynamicLibrary.open('libfastdev_quickjs_runtime.so')` |
| `<pub-cache>/flutter_js-0.8.7/ios/flutter_js.podspec` | 只有 `Classes/*`（Swift 的 JSC 橋接）；`s.platform = :ios, '8.0'`；`pod_target_xcconfig` 有 `'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64'`；**沒有 QuickJS** |
| `app/lib/plugins/runtime/plugin_worker.dart:1-80, 173-188` | 唯一 import `flutter_js` 的檔案；`_QuickJs extends QuickJsRuntime2`，覆寫 `init()` 回 `this`（不裝 `console`／`setTimeout`／`fetch`）；**不傳 `memoryLimit`**，`stackSize` 用預設 1 MB |
| `app/packages/fmp_quickjs/pubspec.yaml` | 目前只宣告 `macos: ffiPlugin: true` |
| `app/packages/fmp_quickjs/macos/fmp_quickjs.podspec` | 編譯旗標與 define（`CONFIG_VERSION`、`QUICKJS=1`、`-Wno-everything`、`c++17`、`s.library = 'c++'`） |
| `app/packages/fmp_quickjs/macos/Classes/*.c(pp)` | 各一行 `#include "../../src/..."` 的轉接檔 |
| `app/packages/fmp_quickjs/test/symbols_test.dart` | `@TestOn('mac-os')`；以 regex 從 `ffi.dart` 抽出 `lookup`／`lookupFunction` 的名稱（現在 55 個），對 `nm -gU` 的輸出 |
| `app/ios/Podfile`（未追蹤） | `use_frameworks!`（動態），沒有 `platform :ios`；`IPHONEOS_DEPLOYMENT_TARGET = 15.0`（pbxproj 9 處） |
| `docs/adr/0036-macos-platform.md` §決定 1 | 「iOS 平台任務沿用同一個套件」 |

### 做法（實測的最小改動，複本在 scratchpad）

```ruby
# ios/fmp_quickjs.podspec（與 macos 的差異）
s.dependency 'Flutter'
s.platform = :ios, '13.0'     # app 是 15.0；套件宣告要 <= app
```
```yaml
# pubspec.yaml
flutter:
  plugin:
    platforms:
      ios:
        ffiPlugin: true
```

- `quickjs_runtime.cpp` 與 `fmp_extras.c` 的匯出宣告是 `__attribute__((visibility("default"))) __attribute__((used))`（原始碼：`quickjs_runtime.cpp:15`、`fmp_extras.c`），動態 framework 建置時全數匯出（`nm -gU fmp_quickjs.framework/fmp_quickjs | grep -c ' _js'` = 73，含 flutter_js 沒查的）。
- Flutter 對 `flutter_js`、`fmp_quickjs` 都印 "do not support Swift Package Manager"（實測）；與 macOS 一樣一定有 Podfile（`app/AGENTS.md` § App 身分已寫）。

## 2. 實測：符號找得到的條件

環境：Xcode 27.1、Flutter 3.47.5、CocoaPods 1.17.0、iPhone 17 模擬器（iOS 27.0）。查的清單：`flutter_js` 0.8.7 的 `ffi.dart` 用 `symbols_test.dart` 同一個 regex 抽出 55 個。

| 配置 | 目標 | 結果 | 證據 |
|---|---|---|---|
| 動態 framework（Podfile 預設 `use_frameworks!`）debug | 模擬器，執行期 `DynamicLibrary.process().lookup` | 55／55 找得到；eval 正確 | log：`PROBE symbols=55 missing=[]`、`eval=3x`、`alloc=1000000` |
| 動態 framework release `--no-codesign` | 真機 arm64，`nm -gU Runner.app/Frameworks/fmp_quickjs.framework/fmp_quickjs` | 73 個 `_js*`，含 `_jsNewRuntime`、`_jsSetMemoryLimit`；strip 沒有剝掉 | `nm` |
| 靜態（`:linkage => :static`）debug | 模擬器，執行期 lookup | **55／55 missing**；`QuickJsRuntime2()` 拋 `Failed to lookup symbol 'jsNewRuntime': dlsym(RTLD_DEFAULT, jsNewRuntime): symbol not found` | log；`Runner.debug.dylib` 無 `_js*`，`Frameworks/` 只剩 `App`、`Flutter` |
| 靜態 release `--no-codesign` | `nm Runner.app/Runner` | 0 個 `_js*` | `nm` |
| 靜態 ＋ podspec `user_target_xcconfig: OTHER_LDFLAGS = $(inherited) -Wl,-u,_jsNewRuntime -Wl,-u,_jsSetMemoryLimit` debug | 模擬器 | 55／55；eval 正確 | log |
| 同上 release `--no-codesign` | `nm -gU Runner` | 66 個 `_js*`，55 個目標符號全在（逐一比對 `comm`，無缺） | `nm` |

重點：

- 靜態失敗的原因是 **linker 沒把 `.o` 拉進來**（`-ObjC` 只拉含 ObjC class 的 object；C／C++ 的 `.o` 沒人引用就不載入），不是 dead strip：debug 配置（沒開 dead strip）也同樣失敗。生成的 `Pods-Runner.debug.xcconfig` 是 `OTHER_LDFLAGS = $(inherited) -ObjC -l"c++" -framework "JavaScriptCore" -framework "flutter_js" -framework "fmp_quickjs"`（實測）。
- `-u` 只需列每個 `.o` 的一個符號：`quickjs_runtime.cpp.o` 含所有 `js*` 包裝，`fmp_extras.c.o` 含 `jsSetMemoryLimit`。`-u` 的符號是 release 的 dead strip 根，沒有被剝掉（實測）。這是為靜態保險用；現行 Podfile 是動態，不需要。
- 沒試 `-all_load`／`-force_load`：前者會把所有靜態庫整個拉進來（含 Flutter 外掛），沒有必要；`-u` 已足夠。
- `flutter_js` 的 podspec 寫 `VALID_ARCHS[sdk=iphonesimulator*] = x86_64`，但本機建出的模擬器 Runner 是 `x86_64 arm64` fat，在 arm64 模擬器上正常跑（實測）。CI 的 macOS runner 是 arm64，沒有觀察到問題；若將來 Xcode 開始遵守 VALID_ARCHS，這是第一個要看的地方。
- 把 macOS 的 CI 檢查搬到 iOS 的形式：`nm -gU build/ios/iphoneos/Runner.app/Frameworks/fmp_quickjs.framework/fmp_quickjs | grep -q ' _jsNewRuntime$'`（`flutter build ios --release --no-codesign` 之後，實測可行）。現有 `app-build-ios`（`ci.yml:468-498`）只建置，沒有這步。
- `symbols_test.dart` 是 `@TestOn('mac-os')`，在 Mac 主機以 clang 編 dylib，對 iOS 沒有額外資訊；iOS 靠 `nm` 檢查即可。

## 3. 記憶體、執行緒、背景

### 記憶體

- **App 目前不設 QuickJS 記憶體上限**（`_QuickJs` 沒傳 `memoryLimit`；`QuickJsRuntime2` 有該參數，`quickjs_runtime2.dart:38,53,130-131`，大於 0 就呼叫 `jsSetMemoryLimit`）。`fmp_extras.c` 補了這個符號，iOS 上能用：`memoryLimit: 16 MB` 後迴圈配置 100 位元組字串，約 112,615 個後停止，`catch` 到的值是 `null`（QuickJS 2021 的 OOM 例外沒有 message），`isError=false`；runtime 之後維持 OOM 狀態（再 eval 回 `InternalError: out of memory`）（實測，模擬器）。
- JS 呼叫堆疊：`QuickJsRuntime2` 預設 1 MB（`stackSize`，`jsSetMaxStackSize`）；插件在背景 isolate 的執行緒上跑，這個上限是 QuickJS 自己算的，不是執行緒大小（原始碼）。本次實測第二項（遞迴 1e6 層）因為前一項已讓 runtime OOM 而沒有得到乾淨的數字，**沒有實測遞迴深度**。
- **iOS 的行程記憶體上限（jetsam）**：Apple 沒有公布固定數字，依機型與系統壓力而定（一般認知，本次沒有查到 Apple 的官方數字；`os_proc_available_memory()` 可在執行期讀剩餘額度）。`com.apple.developer.kernel.increased-memory-limit` 一類 capability 與付費帳號綁在一起；免費帳號的 capability 表沒有它（Apple 能力表只列 "Increased Debugging Memory Limit" 給 ADP，見 signing 報告）。本次沒有測 jetsam 閾值。
- 同一行程：iOS 沒有行程隔離，插件的 QuickJS 與 Dart heap、音訊緩衝共用同一個 jetsam 預算。

### 執行緒

- 插件 worker 是 `Isolate.spawn` 的背景 isolate（`plugin_worker.dart`），每個 isolate 一條 Dart 執行緒；QuickJS runtime 是該 isolate 內 FFI 同步呼叫，沒有額外執行緒（原始碼）。模擬器上 `Platform.numberOfProcessors = 12`。iOS 不限制背景 isolate 的 FFI 呼叫（實測：`Isolate.spawn` 內建立 `QuickJsRuntime2` 並週期 evaluate 成功）。
- 看門狗在主 isolate 用 `Timer` 計時，逾時 `Isolate.kill`（`plugin_runtime.dart:459-460`）。行程被凍結時 Timer 一起凍結，所以背景凍結不會誤殺插件，但也代表凍結期間沒有 deadline。

### 背景

- 實測（模擬器，probe 沒有 `UIBackgroundModes`）：背景 isolate 每 2 秒 `evaluate('++c')`；`launch com.apple.Preferences` 切走後，tick 在 23:57:41 停止，回前景後 23:58:09 才繼續（`js=3` → `js=4`，28 秒空窗）。結論：**沒有背景模式時，App 進背景後 JS 與 Dart 一起被凍結，Timer 不跑**。
- `UIBackgroundModes` 的 `audio`（「Audio, AirPlay, and Picture in Picture」）加上啟用的 `AVAudioSession`（`.playback`）與正在播放，系統才讓行程持續執行（文件：[Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback)）。持續執行時 Dart isolate 與 FFI 照常跑，所以插件可以在背景解析下一首的網址；`app/ios/Runner/Info.plist` 現在沒有 `UIBackgroundModes`（grep 過）。
- 播放暫停、或 audio session 被中斷（來電、別的 App 搶走）之後，系統可以在幾秒內凍結行程；那時要回前景才能解析網址。這是文件層級的行為，沒有實機驗證。
- 模擬器的背景凍結行為與實機不完全相同（模擬器是 macOS 行程）；上面的「有 audio 時行程持續」那半沒有實測。

## 沒查到／不確定

- **實機行為**：沒有碰實體 iPhone，所以沒測「有 `audio` 背景模式時背景解析下一首」，也沒測 jetsam 的實際上限與熱／低電量模式的影響。這些要在實機驗證階段量。
- 沒測遞迴深度與 JS 堆疊上限（見上）。
- 沒對 `flutter_js` 的 `VALID_ARCHS` 做額外調查（只觀察到現行 Xcode 27.1 照樣建 arm64）。
- iOS 的 `app/ios/` 目前有未提交的 Podfile、Pods 與 pbxproj 變動（git status 的既有狀態，不是我改的），我沒有碰。
- AGENTS.md 提到「`ios/` 的還沒提交，產生的 Podfile 只對應三個模式」：靜態與動態的差異不影響這一點，flavor 的六個 configuration 對應是另一件事。

## Related Specs

- `docs/adr/0036-macos-platform.md` §決定 1、§決定 10
- `app/AGENTS.md` § App 身分（Podfile 與 flavor 段）、§ 插件
- `.trellis/tasks/archive/2026-11/10-28-macos-platform/research/plugin-runtime-macos.md`
