import 'dart:io';

import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

/// macOS：`~/Library/Application Support/<bundle id>`（path_provider 的
/// application support；App 不開沙盒，ADR 0036）。
///
/// dev 與 prod 的 bundle id 不同，目錄本來就分開，Dart 端不再加 `-dev`。舊版從來沒有
/// 發行過 macOS，沒有舊資料位置要避開，所以不呼叫 [ensureOutsideLegacyData]。
final class MacosAppDataDirectory implements AppDataDirectory {
  MacosAppDataDirectory({required this._applicationSupportPath});

  final Future<String> Function() _applicationSupportPath;

  @override
  Future<Directory> resolve() async =>
      Directory(await _applicationSupportPath()).create(recursive: true);
}
