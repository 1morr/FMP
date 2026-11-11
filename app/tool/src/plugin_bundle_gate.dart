import 'dart:io';

import 'steps.dart';

/// 插件原始碼的目錄（相對 `app/`），`npm` 在這裡跑。
const pluginsDir = 'plugins';

/// 閘門的打包產物檢查（ADR 0038、plan §4）：`npm ci` 照 lockfile 裝好
/// esbuild 與 TypeScript，`npm run build -- --outdir <暫存目錄>`（型別檢查
/// 加 esbuild）從原始碼重建每個插件，再和提交的 `plugins/<id>/dist/` 逐
/// 位元組比對。改了插件原始碼卻沒重建、沒提交產物，這步就紅。
CheckStep pluginBundleStep({
  required Directory app,
  required Shell shell,
  required StringSink out,
}) {
  return CheckStep('plugin bundles (esbuild)', () async {
    final plugins = Directory('${app.path}/$pluginsDir');
    if (await shell.run('npm', [
          'ci',
          '--no-audit',
          '--no-fund',
        ], workingDirectory: plugins) !=
        0) {
      return false;
    }
    final temp = Directory.systemTemp.createTempSync('fmp_plugins_');
    try {
      if (await shell.run('npm', [
            'run',
            'build',
            '--',
            '--outdir',
            temp.path,
          ], workingDirectory: plugins) !=
          0) {
        return false;
      }
      final stale = <String>[];
      for (final id in _pluginIds(plugins)) {
        final rebuilt = _files(Directory('${temp.path}/$id/dist'));
        final committed = _files(Directory('${plugins.path}/$id/dist'));
        for (final name in {...rebuilt.keys, ...committed.keys}) {
          if (!_sameBytes(rebuilt[name], committed[name])) {
            stale.add('$pluginsDir/$id/dist/$name');
          }
        }
      }
      if (stale.isEmpty) return true;
      out.writeln(
        'These plugin bundles do not match their sources: '
        '${(stale..sort()).join(', ')}. '
        'Run `npm run build` in app/$pluginsDir and commit dist/.',
      );
      return false;
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}

/// 有 `manifest.json` 的子目錄就是插件。
List<String> _pluginIds(Directory plugins) => [
  for (final dir in plugins.listSync().whereType<Directory>())
    if (File('${dir.path}/manifest.json').existsSync())
      dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
]..sort();

/// [dir] 底下的檔案，key 是相對路徑。
Map<String, List<int>> _files(Directory dir) => {
  if (dir.existsSync())
    for (final file in dir.listSync(recursive: true).whereType<File>())
      file.path.substring(dir.path.length + 1): file.readAsBytesSync(),
};

bool _sameBytes(List<int>? a, List<int>? b) {
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
