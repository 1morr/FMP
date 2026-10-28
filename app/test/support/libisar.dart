import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:isar_community/isar.dart';

/// 讓裸 `flutter test` 載入得到 Isar 的原生庫（舊資料匯入的測試開舊庫用）。
///
/// `isar_community_flutter_libs` 3.3.2 把 `libisar` 放在套件的 `windows/libisar.dll`
/// 與 `linux/libisar.so`；flutter_tester 的搜尋路徑裡沒有它們，所以以 pub cache
/// 裡的絕對路徑載入（key 是 `dart:ffi` 的 [Abi]，`Isar.initializeIsarCore` 不
/// 下載：`download` 預設 false）。找不到或載入失敗就拋錯，不跳過：CI（Linux）
/// 要真的跑到 Isar。macOS 用套件的 `macos/libisar.dylib`（universal），key 依主機架構。
Future<void> loadLibisarForTests() async {
  final String relative;
  final Abi abi;
  if (Platform.isWindows) {
    relative = 'windows/libisar.dll';
    abi = Abi.windowsX64;
  } else if (Platform.isLinux) {
    relative = 'linux/libisar.so';
    abi = Abi.linuxX64;
  } else if (Platform.isMacOS) {
    relative = 'macos/libisar.dylib';
    abi = Abi.current();
  } else {
    return;
  }
  final library = File.fromUri(_isarFlutterLibsRoot().resolve(relative));
  if (!library.existsSync()) {
    throw StateError('libisar not found: ${library.path}');
  }
  await Isar.initializeIsarCore(libraries: {abi: library.path});
}

/// `isar_community_flutter_libs` 在 pub cache 裡的根目錄，從
/// `.dart_tool/package_config.json` 讀（`flutter test` 的工作目錄是 app/）。
Uri _isarFlutterLibsRoot() {
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (package) => package['name'] == 'isar_community_flutter_libs',
  );
  final root = configFile.absolute.uri.resolve(package['rootUri'] as String);
  return root.path.endsWith('/') ? root : Uri.parse('$root/');
}
