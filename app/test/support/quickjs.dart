import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// 讓裸 `flutter test` 載入得到 QuickJS 的原生庫。
///
/// flutter_js 0.8.7 在測試裡（`FLUTTER_TEST=true`）以檔名開原生庫：Windows 開
/// `quickjs_c_bridge.dll`，Linux 開 `LIBQUICKJSC_TEST_PATH` 或
/// `libquickjs_c_bridge_plugin.so`（`lib/quickjs/ffi.dart` 的 `_qjsLib`）。
/// flutter_tester 的搜尋路徑裡沒有它們，README 的做法是先建置桌面版再改
/// `PATH`／設環境變數。這裡改成先以絕對路徑載入套件內附的預先編譯檔
/// （`windows/shared/`、`linux/shared/`），之後以檔名開就拿到同一份：
///
/// - Windows：同名的 DLL 已經載入時，LoadLibrary 直接用它（Dynamic-Link
///   Library Search Order）；
/// - Linux：dlopen 會比對已載入物件的 SONAME，那個檔的 SONAME 就是
///   `libquickjs_c_bridge_plugin.so`。
///
/// 兩個平台找不到或載入失敗就拋錯，不跳過：CI（Linux）要真的跑到 QuickJS。
/// macOS 的 flutter_js 走 JavaScriptCore，App 在 macOS 也還沒支援，不處理。
void loadQuickJsForTests() {
  final String relative;
  if (Platform.isWindows) {
    relative = 'windows/shared/quickjs_c_bridge.dll';
  } else if (Platform.isLinux) {
    relative = 'linux/shared/libquickjs_c_bridge_plugin.so';
  } else {
    return;
  }
  final library = File.fromUri(_flutterJsRoot().resolve(relative));
  if (!library.existsSync()) {
    throw StateError('QuickJS library not found: ${library.path}');
  }
  DynamicLibrary.open(library.path);
}

/// flutter_js 在 pub cache 裡的根目錄，從 `.dart_tool/package_config.json`
/// 讀（`flutter test` 的工作目錄是 app/，也就是 workspace 根）。
Uri _flutterJsRoot() {
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (package) => package['name'] == 'flutter_js',
  );
  final root = configFile.absolute.uri.resolve(package['rootUri'] as String);
  return root.path.endsWith('/') ? root : Uri.parse('$root/');
}
