import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:isar/isar.dart';

/// 提供原生 Isar 動態庫的 package 名稱。
///
/// `flutter test` 跑在桌面 VM 上，Flutter 的 plugin 註冊機制不會發生，所以動態庫
/// 必須手動指給 [Isar.initializeIsarCore]。整個測試套件裡只有這一份定義知道那個庫
/// 來自哪個 package、叫什麼檔名 —— 換套件時只要改這裡。
const String _isarLibsPackage = 'isar_flutter_libs';

/// 各平台的動態庫檔名。Windows 與其他平台的命名慣例不同，且會隨 package 改變。
const Map<String, String> _isarLibraryFile = {
  'windows': 'windows/isar.dll',
  'linux': 'linux/libisar.so',
  'macos': 'macos/libisar.dylib',
};

/// 在測試進程裡載入 Isar 原生核心。
///
/// 可以重複呼叫：[Isar.initializeIsarCore] 內部有 `_isarInitialized` 短路，第二次
/// 之後是 no-op。所以每個測試檔在自己的 `setUpAll` 裡呼叫是安全的。
Future<void> initializeIsarForTests() async {
  await Isar.initializeIsarCore(
    libraries: {Abi.current(): await resolveIsarLibraryPath()},
  );
}

/// 解析 Isar 原生庫在本機 pub cache 裡的絕對路徑。
Future<String> resolveIsarLibraryPath() async {
  final relativePath = _isarLibraryFile[Platform.operatingSystem];
  if (relativePath == null) {
    throw UnsupportedError(
      'Unsupported platform for Isar tests: ${Platform.operatingSystem}',
    );
  }
  final packageDir = await _resolvePackageDirectory(_isarLibsPackage);
  return '${packageDir.path}/$relativePath';
}

Future<Directory> _resolvePackageDirectory(String packageName) async {
  final dartToolDir = Directory('${Directory.current.path}/.dart_tool');
  final packageConfigFile = File('${dartToolDir.path}/package_config.json');
  if (!await packageConfigFile.exists()) {
    throw StateError(
      'Could not find .dart_tool/package_config.json for test package '
      'resolution. Run `flutter pub get` first.',
    );
  }

  final packageConfig =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != packageName) continue;
    // rootUri 是相對於 .dart_tool/ 的，要先 resolve 再轉檔案路徑。
    return Directory(
      dartToolDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
  }

  throw StateError('Package "$packageName" is not in package_config.json');
}
