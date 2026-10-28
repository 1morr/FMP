/// 測試用：在 macOS 主機上把 `src/` 編成 dylib（ADR 0036 §決定 1）。
///
/// App 不 import 這個檔：App 裡的 QuickJS 由 podspec 編進行程。`flutter test` 跑在主機的
/// flutter_tester 裡，沒有那個 framework，所以測試先以這裡編出的 dylib `DynamicLibrary.open`，
/// flutter_js 在 macOS 的 `DynamicLibrary.process()` 就找得到符號。
library;

import 'dart:io';

/// 編進 dylib 的原始碼（相對於套件根），同 podspec 的 `macos/Classes/` 轉接的那些。
const hostSources = [
  'src/quickjs/cutils.c',
  'src/quickjs/libregexp.c',
  'src/quickjs/libunicode.c',
  'src/quickjs/quickjs.c',
  'src/fmp_extras.c',
  'src/quickjs_runtime.cpp',
];

/// 同 podspec 的 `pod_target_xcconfig`。
const _defines = ['-DCONFIG_VERSION="2021-03-27"', '-DQUICKJS=1'];
const _cFlags = ['-O2', '-Wno-error=int-conversion', '-Wno-everything'];

/// 把 [packageRoot]（`fmp_quickjs` 的根目錄）的原始碼編成 dylib，放在
/// `<cacheRoot>/<原始碼雜湊>/libfmp_quickjs.dylib`，回傳它的路徑。已經有同一份雜湊的就不重編。
///
/// 只在 macOS 主機用：要 `xcrun clang`，別的平台 `xcrun` 不在，會拋 [ProcessException]。只編主機的架構。
/// 先編在暫存目錄再改名：`flutter test` 同時跑好幾個測試檔，每個行程都會呼叫這裡，改名讓別的行程只看得到
/// 完整的檔。編不出來就拋 [StateError]（含 clang 的輸出），不默默跳過。
String buildHostLibrary({
  required Directory packageRoot,
  required Directory cacheRoot,
}) {
  final sources = [
    for (final relative in hostSources) File('${packageRoot.path}/$relative'),
  ];
  final target = Directory('${cacheRoot.path}/${_hash(packageRoot)}');
  final library = File('${target.path}/libfmp_quickjs.dylib');
  if (library.existsSync()) return library.path;

  cacheRoot.createSync(recursive: true);
  final work = cacheRoot.createTempSync('build-');
  try {
    final include = '${packageRoot.path}/src/quickjs';
    final objects = <String>[];
    for (final source in sources) {
      final object = '${work.path}/${_basename(source.path)}.o';
      final isCpp = source.path.endsWith('.cpp');
      _run('xcrun', [
        if (isCpp) 'clang++' else 'clang',
        '-c',
        if (isCpp) '-std=c++17',
        ..._defines,
        ..._cFlags,
        '-I$include',
        source.path,
        '-o',
        object,
      ]);
      objects.add(object);
    }
    final built = '${work.path}/libfmp_quickjs.dylib';
    _run('xcrun', ['clang++', '-dynamiclib', ...objects, '-o', built]);
    final staged = Directory('${work.path}/out')..createSync();
    File(built).renameSync('${staged.path}/libfmp_quickjs.dylib');
    try {
      staged.renameSync(target.path);
    } on FileSystemException {
      // 別的行程先編好了：用它的。
      if (!library.existsSync()) rethrow;
    }
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
  return library.path;
}

void _run(String executable, List<String> arguments) {
  final result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      'fmp_quickjs host build failed: $executable ${arguments.join(' ')}\n'
      '${result.stdout}${result.stderr}',
    );
  }
}

String _basename(String path) => path.substring(path.lastIndexOf('/') + 1);

/// `src/` 底下每個檔（含標頭）的路徑與內容，加上編譯旗標的 FNV-1a（64 位元，VM 的整數乘法
/// 自然以 2^64 取餘）。只用來分辨快取，不需要密碼學雜湊。
String _hash(Directory packageRoot) {
  var hash = 0xcbf29ce484222325;
  void add(List<int> bytes) {
    for (final byte in bytes) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
  }

  add([..._defines, ..._cFlags].join(' ').codeUnits);
  final src = Directory('${packageRoot.path}/src');
  final files = src.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    add(file.path.substring(src.path.length).codeUnits);
    add(file.readAsBytesSync());
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}
