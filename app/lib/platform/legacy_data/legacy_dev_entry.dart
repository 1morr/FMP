import 'package:fmp/core/app_flavor.dart';

// 開發入口：dev flavor 讀一份舊資料的副本，不讀真實的舊資料位置（M5 design §8.1）。
//
// 只在 dev 生效，prod 不讀參數與環境變數（[legacyDirectoryPath]）：同 `--fmp-dev-plugin`，
// 命令列參數、Android 的 intent extra 與環境變數都能由別的程式帶入，而這條路會把指定資料夾
// 的內容匯成這個 App 的資料。資料夾落在真實的舊資料位置（`<文件>\FMP`、
// `%APPDATA%\com.personal\fmp`、`com.personal.fmp` 的沙盒）時 `AppPlatform` 拒絕。

/// 命令列參數：`--fmp-legacy-dir=<資料夾>`。
const legacyDirectoryArgumentPrefix = '--fmp-legacy-dir=';

/// 環境變數（Windows 的 `flutter run` 會傳給 App）。參數優先。
const legacyDirectoryEnvironmentVariable = 'FMP_LEGACY_DIR';

/// 從 [arguments] 與 [environment] 找舊資料副本的資料夾；沒有、或 [flavor] 不是 dev 就是
/// `null`。
String? legacyDirectoryPath(
  AppFlavor flavor,
  List<String> arguments,
  Map<String, String> environment,
) {
  if (flavor != AppFlavor.dev) return null;
  for (final argument in arguments) {
    if (argument.startsWith(legacyDirectoryArgumentPrefix)) {
      final path = argument.substring(legacyDirectoryArgumentPrefix.length);
      if (path.isNotEmpty) return path;
    }
  }
  final path = environment[legacyDirectoryEnvironmentVariable];
  return path == null || path.isEmpty ? null : path;
}
