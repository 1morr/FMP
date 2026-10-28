# fmp_quickjs 的原始碼出處

`src/` 是照搬的第三方原始碼，**不要改**：要改行為就加新檔（同 `src/fmp_extras.c`），讓這裡和上游逐字相同。

- 上游：<https://github.com/fast-development/android-js-runtimes>，tag `0.3.6`（commit `0f72f7409ff610b33b0e09bd9460213f0e487bf0`），目錄 `quickjs/src/main/c/`。
- 這是 `flutter_js` 0.8.7 在 Android 依賴的 `com.github.fast-development.android-js-runtimes:fastdev-jsruntimes-quickjs:0.3.6`
  （`flutter_js` 的 `android/build.gradle`）的原始碼，Android 的 `libfastdev_quickjs_runtime.so` 就是它編出來的。
- QuickJS 版本 `2021-03-27`（上游 CMake 的 `CONFIG_VERSION`）。
- 取用日期：2026-10-28。
- 檔案：只取上游 CMake 編的四個 `.c`（`cutils.c`、`libregexp.c`、`libunicode.c`、`quickjs.c`）、橋接 `quickjs_runtime.cpp`，
  以及它們 include 的標頭。沒有取 `quickjs-libc.c`、`libbf.c`、`unicode_gen*`（上游 CMake 也不編）。
- 改動：無。

FMP 自己的檔：

- `src/fmp_extras.c`：補 `jsSetMemoryLimit`（`flutter_js` 的 `ffi.dart` 會查，橋接沒有）。
- `macos/Classes/*`：轉接檔，以 `#include` 編 `src/` 的檔（CocoaPods 只編 podspec 目錄裡的檔）。

升級 `flutter_js` 時：看它 Android 依賴的 `fastdev-jsruntimes-quickjs` 版本有沒有變，有就換成新 tag 的原始碼；
`test/symbols_test.dart` 會核對 `ffi.dart` 查的每個符號都在。
