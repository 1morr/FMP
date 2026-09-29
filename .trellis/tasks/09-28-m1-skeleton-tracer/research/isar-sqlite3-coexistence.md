# isar_community 與 sqlite3 共存探針（design.md §3 第 3.11 列）

日期：2026-09-29。探針在一次性 worktree（`agent-ac8d1954b63a5bfb0`，基於 `50399003`）裡跑，
沒有 commit、不合併。要回答的問題來自 ADR 0010 §後果：

- `isar_community` 與 `sqlite3` 兩套原生庫能不能在同一個 Flutter App 裡共存（Android、Windows）；
- Android 原生 `.so` 是否 16KB page size 對齊。

## 結論

| 問題 | Android | Windows |
|------|---------|---------|
| 兩庫同一 App 共存、各自開庫讀寫 | **可以**（debug、release 都跑通） | **可以**（release 跑通） |
| 建置衝突（重複符號／native asset／Gradle packaging） | 無 | 無 |
| 16KB 對齊 | **全部對齊**（見下表） | 不適用 |

ADR 0010 的「若衝突，legacy import 改成獨立一次性小程式」**不需要啟用**。

另有一個 ADR 沒預料到的限制：**`isar_community_generator` 3.3.2 無法進 `app/` 的 pub workspace**
（見「附帶發現」），M5 的 `legacy_import/` 需要另想 codegen 路徑。

## 使用的版本

| 項目 | 版本 |
|------|------|
| Flutter／Dart | 3.47.5（stable）／3.13.4 |
| `sqlite3` | 3.6.0（pub.dev 最新 3.x，2026-09-13 發佈） |
| └ 傳遞依賴 | `hooks` 2.2.0（由 2.0.2 升上來）、`code_assets` 1.2.1、`native_toolchain_c` 0.19.3、`record_use` 1.1.1（由 0.6.0 升上來） |
| └ 實際載入的 SQLite | 3.53.4（hook 預設走 `PrecompiledBinary`：下載預編譯檔並驗 hash，不在本機編譯） |
| `isar_community`／`isar_community_flutter_libs` | 3.3.2／3.3.2（pub.dev 最新，2026-03-23） |
| └ Isar core | `IsarCore using libmdbx: v0.13.8-temp-upstream-fix` |
| `isar_community_generator`（只在 workspace 外用） | 3.3.2，搭 `build_runner` 2.15.1、`analyzer` 10.2.0、`source_gen` 4.2.4 |
| Android NDK／build-tools | 28.2.13676358／36.0.0 |
| 模擬器 | `emulator-5554`，Android 17，x86_64，`getconf PAGE_SIZE` = **16384**（16KB 頁環境） |

## 探針內容

- `app/pubspec.yaml`：`flutter pub add sqlite3:^3.6.0 isar_community:3.3.2 isar_community_flutter_libs:3.3.2`。
- `app/lib/probe/probe_item.dart`：一個 `@collection class ProbeItem { Id id; late String name; }`；
  `probe_item.g.dart` 在 workspace 外的暫存 package 產生後複製進來。
- `app/lib/main_probe.dart`：啟動時
  1. `sqlite3.openInMemory()` → `select sqlite_version()`，建表、寫一列、讀回；
  2. `Isar.open([ProbeItemSchema], directory: <getTemporaryDirectory()>/isar_probe)`，寫一筆、`findAll()` 讀回；
  3. 兩個結果 `print('PROBE: ...')`、寫進 `Directory.systemTemp/fmp_probe_result.txt`，並顯示在畫面上（`package:material_ui`）。

## Android

### 建置

```
flutter build apk --flavor dev --debug   -t lib/main_probe.dart   # 71.6s  √ app-dev-debug.apk
flutter build apk --flavor dev --release -t lib/main_probe.dart   # 124.1s √ app-dev-release.apk (50.2MB)
```

release 用 `build.gradle.kts` 現有的 debug 簽名設定，不需額外處理。`-v` 重跑 release 後 grep
`duplicate|conflict|More than one file|pickFirst`：**零命中**。只看到下列警告，都不是這兩個套件造成的衝突：

- `WARNING: The option setting 'android.builtInKotlin=false' is deprecated.`、`'android.newDsl=false' is deprecated.`（`:app` 既有）
- `w: Deprecated 'org.jetbrains.kotlin.android' plugin usage`：`:app`、`:isar_community_flutter_libs`、`:jni`、`:jni_flutter` 各一次（AGP 9 內建 Kotlin 的遷移提示）
- `CMake project not found, skipping support Android 15 16k page size migration.`（Flutter 工具的資訊行，App 沒有自己的 CMake）

`isar_community_flutter_libs` 的 `android/build.gradle` 仍寫 `classpath 'com.android.tools.build:gradle:8.6.0'`、
`compileSdkVersion 35`，在本專案的 AGP 下照樣能建置，沒有報錯。

### APK 內的原生庫（`unzip -l`，release）

```
lib/arm64-v8a/   libapp.so 3146632  libdartjni.so 131400  libflutter.so 11747864  libisar.so 1125656  libsqlite3.so 1732360
lib/armeabi-v7a/ libapp.so 3506760  libdartjni.so  81600  libflutter.so  8615900  libisar.so  914460  libsqlite3.so 1713736
lib/x86_64/      libapp.so 3277704  libdartjni.so 116792  libflutter.so 13051424  libisar.so 1258072  libsqlite3.so 1709544
```

debug APK 沒有 `libapp.so`（JIT），另多一個 `arm64-v8a/libVkLayer_khronos_validation.so`（Flutter debug 自帶）。
`libsqlite3.so` 由 `sqlite3` 的 build hook 產出、經 Flutter 的 native assets 流程打包；`libisar.so` 由
`isar_community_flutter_libs` 帶入。`libdartjni.so` 來自既有依賴鏈上的 `jni` 1.0.3，不是本探針新增的。

兩個庫匯出符號互不重疊（`llvm-nm -D --defined-only`：`libisar.so` 93 個匯出、其中含 `sqlite` 的 0 個；
`libsqlite3.so` 含 `mdbx` 的 0 個），各自是獨立 `.so`，沒有符號搶用。

### 執行（模擬器，16KB 頁）

```
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-dev-debug.apk
adb -s emulator-5554 shell monkey -p com.personal.fmp.dev -c android.intent.category.LAUNCHER 1
adb -s emulator-5554 logcat -d | grep PROBE:
```

debug：

```
I flutter : PROBE: sqlite OK version=3.53.4 row=hello-sqlite
I flutter : PROBE: isar OK version=3.3.2 count=1 row=hello-isar
I flutter : PROBE: wrote /data/user/0/com.personal.fmp.dev/code_cache/fmp_probe_result.txt
```

release（同樣安裝後 `am start -n com.personal.fmp.dev/com.personal.fmp.MainActivity`）：

```
I flutter : IsarCore using libmdbx: v0.13.8-temp-upstream-fix
I flutter : PROBE: sqlite OK version=3.53.4 row=hello-sqlite
I flutter : PROBE: isar OK version=3.3.2 count=1 row=hello-isar
```

沒有 `UnsatisfiedLinkError`、`dlopen` 失敗或 FATAL。兩張截圖都顯示兩行 OK（留在探針 worktree 的
`probe_android_debug.png`、`probe_android_release.png`，不合併）。模擬器頁大小是 16384，所以這同時是
16KB 頁上的實際載入測試。

### 16KB 對齊

ZIP 對齊（`build-tools/36.0.0/zipalign -c -P 16 -v 4 <apk>`）：debug、release 兩個 APK 的所有 `.so` 都是
`(OK)`，結尾 `Verification successful`。

ELF LOAD segment 對齊（`ndk/28.2.13676358/.../llvm-readelf -lW`，取每個 `LOAD` 的 `Align`；
≥ 0x4000 即符合 16KB）：

| 庫 | 來源 | arm64-v8a | x86_64 | armeabi-v7a | 16KB 對齊 |
|----|------|-----------|--------|-------------|-----------|
| `libsqlite3.so` | `sqlite3` build hook（預編譯下載） | 0x4000 | 0x4000 | 0x4000 | 是 |
| `libisar.so` | `isar_community_flutter_libs` 3.3.2 | 0x4000 | 0x4000 | 0x4000 | 是 |
| `libflutter.so` | Flutter engine | 0x10000 | 0x10000 | 0x10000 | 是 |
| `libapp.so`（僅 release） | Dart AOT | 0x10000 | 0x10000 | 0x4000 | 是 |
| `libdartjni.so` | `jni` 1.0.3 | 0x4000 | 0x4000 | 0x4000 | 是 |
| `libVkLayer_khronos_validation.so`（僅 debug） | Flutter debug | 0x10000 | — | — | 是 |

debug 與 release 同一個庫的數值相同。16KB 要求只針對 64 位元 ABI（arm64-v8a、x86_64），32 位元欄僅供參考。

## Windows

```
flutter build windows --flavor dev --release -t lib/main_probe.dart   # 228.2s √ build\windows\x64\dev\runner\Release\fmp.exe
```

建置輸出沒有 warning／`LNK`／duplicate。產物目錄：

```
fmp.exe 91648   flutter_windows.dll 21274112   libisar.dll 996352
isar_community_flutter_libs_plugin.dll 86528   sqlite3.dll 1709056   dartjni.dll 58368
```

執行 `fmp.exe`（視窗標題 `FMP Dev`），8 秒後讀 `%TEMP%\fmp_probe_result.txt`：

```
PROBE: sqlite OK version=3.53.4 row=hello-sqlite
PROBE: isar OK version=3.3.2 count=1 row=hello-isar
written=2026-09-29T14:17:32.571851
```

之後 `Stop-Process` 關掉。`sqlite3.dll` 與 `libisar.dll` 各自獨立、檔名不撞。

## 附帶發現：Isar codegen 進不了 workspace

```
flutter pub add --dev isar_community_generator:3.3.2 build_runner --dry-run
Because fmp_lints depends on analyzer 13.3.0 and isar_community_generator >=3.3.2 depends on
analyzer >=8.0.0 <11.0.0, isar_community_generator >=3.3.2 is forbidden.
```

`isar_community_generator` 3.3.2 是 pub.dev 最新版，上界 `analyzer <11`；`app/` 的 workspace 因
`fmp_lints` 釘 `analyzer` 13.3.0（ADR 0015）。本探針改在 workspace 外的獨立 package 跑
`dart run build_runner build`（analyzer 10.2.0，會警告 `SDK language version 3.13.0 is newer than
analyzer language version 3.12.0`，但仍成功產出），再把 `.g.dart` 複製進 `app/lib/probe/`，執行期完全正常。
舊 App 的 `.g.dart` 沒有進版控（`git ls-files 'lib/**/*.g.dart'` 為空），所以 M5 做 `legacy_import/`
時要選一條路：

- 在 workspace 外產生舊 schema 的 `.g.dart` 後提交進 `app/lib/legacy_import/`（舊 schema 已凍結，
  產生一次即可；本探針證實此路可行）；或
- 等 generator 放寬 analyzer 上界。

這不影響 ADR 0010 的共存結論，但 M5 開工前應在 ADR 0010 或 M5 設計裡記一筆。

## 若日後出現衝突

本次沒有衝突，備援不用啟動。若未來某次升級（例如 `sqlite3` hook 改變打包方式、Isar fork 換新 core）
讓兩庫在同一行程衝突，ADR 0010 的備援是把 legacy import 拆成由新 App 啟動的獨立一次性小程式：
主 App 不再依賴 `isar_community`，由另一個只含 Isar 與舊 secure storage 的程式讀舊資料、輸出中介格式給
主 App 匯入。代價是多一份中介格式與其驗證；在 Android 上，同一行程內的另一個 isolate 共用已載入的原生庫、
隔離不了衝突，所以小程式至少要跑在另一個行程。
