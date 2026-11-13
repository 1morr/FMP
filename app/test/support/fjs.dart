import 'dart:convert';
import 'dart:io';

import 'package:fjs/fjs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';

bool _loaded = false;

/// 讓 `flutter test`（Mac 主機）用得了真的 fjs 引擎（brief 事實 K19）。
///
/// App 裡由各平台的建置把原生庫打包進去；主機上的測試沒有那一步，所以從
/// pub cache 裡 fjs 附的 xcframework 解出 macOS 的動態庫，放在
/// `build/test_fjs/<版本>/`，再交給 [LibFjs.init]。每個測試檔是自己的
/// isolate，各呼叫一次；同時跑的測試檔可能同時解壓，所以先解到暫存目錄再
/// 改名。
Future<void> loadFjsForTests() async {
  if (_loaded) return;
  if (!Platform.isMacOS) {
    throw UnsupportedError('fjs host tests only run on macOS (plan〈開發環境與閘門〉)');
  }
  final root = _fjsPackageRoot();
  final version = root.path.split('-').last;
  final target = Directory('build/test_fjs/$version');
  final library = File(
    '${target.path}/fjs.xcframework/macos-arm64_x86_64/fjs.framework/fjs',
  );
  if (!library.existsSync()) {
    target.parent.createSync(recursive: true);
    final temp = target.parent.createTempSync('unzip_');
    final result = Process.runSync('unzip', [
      '-q',
      '${root.path}/darwin/fjs/Binaries/fjs.xcframework.zip',
      '-d',
      temp.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('unzip fjs.xcframework failed: ${result.stderr}');
    }
    try {
      temp.renameSync(target.path);
    } on FileSystemException {
      // 別的測試檔先解好了。
      temp.deleteSync(recursive: true);
    }
  }
  await LibFjs.init(externalLibrary: ExternalLibrary.open(library.path));
  _loaded = true;
}

Directory _fjsPackageRoot() {
  final file = File('.dart_tool/package_config.json');
  final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  for (final package in config['packages'] as List<dynamic>) {
    final {'name': String name, 'rootUri': String rootUri} =
        package as Map<String, dynamic>;
    // rootUri 可以是絕對的 file: URI，也可以相對於 package_config.json。
    if (name == 'fjs') {
      return Directory.fromUri(file.absolute.uri.resolve(rootUri));
    }
  }
  throw StateError('fjs is not in .dart_tool/package_config.json');
}
