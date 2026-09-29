import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/source_plugin.dart';

// 開發入口：啟動時從指定的路徑安裝一個插件，給還沒有選檔 UI（PR 12）與插件頁
// （M3）的這段期間，以及 dev 的實機驗證用（ADR 0027）。
//
// 只在 dev flavor 生效，prod 不讀參數與環境變數（[devPluginPath]）：這條路徑跳過
// ADR 0014 §決定 6 要求的安裝前確認（能力、網域、「以你的登入身分存取」的
// 警告），而命令列參數、Android 的 intent extra（`dart_entrypoint_args`）與
// 環境變數都能由別的程式帶入。正式版的安裝只經使用者看過確認的 UI。

/// 命令列參數：`--fmp-dev-plugin=<安裝檔路徑>`。
const devPluginArgumentPrefix = '--fmp-dev-plugin=';

/// 環境變數（Windows 的 `flutter run` 會傳給 App）。參數優先。
const devPluginEnvironmentVariable = 'FMP_DEV_PLUGIN';

/// 從 [arguments] 與 [environment] 找開發入口要安裝的路徑；沒有、或 [flavor]
/// 不是 dev 就是 `null`。
String? devPluginPath(
  AppFlavor flavor,
  List<String> arguments,
  Map<String, String> environment,
) {
  if (flavor != AppFlavor.dev) return null;
  for (final argument in arguments) {
    if (argument.startsWith(devPluginArgumentPrefix)) {
      final path = argument.substring(devPluginArgumentPrefix.length);
      if (path.isNotEmpty) return path;
    }
  }
  final path = environment[devPluginEnvironmentVariable];
  return path == null || path.isEmpty ? null : path;
}

/// 開發入口要安裝的路徑。`main()` 以 [devPluginPath] override；預設 `null`。
final devPluginPathProvider = Provider<String?>((ref) => null);

/// 開發入口：安裝 [devPluginPathProvider] 指的檔案；沒有路徑時是 `null`。失敗
/// 經 `log.report` 記下並以 `AppError` 結束。
final devPluginInstallProvider = FutureProvider<SourcePlugin?>((ref) async {
  final path = ref.watch(devPluginPathProvider);
  if (path == null) return null;
  final log = ref.watch(logProvider);
  try {
    final plugin = await ref
        .watch(pluginInstallerProvider)
        .installBytes(await File(path).readAsBytes());
    log.info(
      'Installed a plugin from the development entry',
      tag: 'plugins',
      fields: {'pluginId': plugin.manifest.id},
    );
    return plugin;
  } on Object catch (error, stackTrace) {
    final appError = AppError.wrap(error, stackTrace);
    log.report(
      'Failed to install the development plugin',
      appError,
      tag: 'plugins',
    );
    throw appError;
  }
});
