import 'dart:io';

import 'steps.dart';

/// drift 資料庫的原始檔與它的快照目錄（`build.yaml` 的 `databases`）。
const databaseSource = 'lib/data/database.dart';
const snapshotDir = 'drift_schemas/app_database';

/// 閘門的 schema 快照檢查（plan〈測試策略〉）：`drift_dev schema dump` 出目前的
/// schema，要跟 [snapshotDir] 裡版本最高的快照一字不差（`make-migrations`
/// 也是逐字比對）。改了表卻沒加版本、跑 `make-migrations`，這步就紅。
///
/// 「`schemaVersion` 等於最新快照的版本」由 `test/drift/` 的升級測試守，
/// 兩者合起來，版本加了卻沒產生快照也會紅。
CheckStep schemaSnapshotStep({
  required Directory app,
  required Shell shell,
  required StringSink out,
}) {
  return CheckStep('schema snapshot (drift)', () async {
    final temp = Directory.systemTemp.createTempSync('fmp_schema_');
    try {
      final current = File('${temp.path}/current.json');
      final code = await shell.run('dart', [
        'run',
        'drift_dev',
        'schema',
        'dump',
        databaseSource,
        current.path,
      ], workingDirectory: app);
      if (code != 0) return false;

      final latest = _latestSnapshot(Directory('${app.path}/$snapshotDir'));
      if (latest == null) {
        out.writeln(
          'No schema snapshot in $snapshotDir/. '
          'Run `dart run drift_dev make-migrations`.',
        );
        return false;
      }
      if (current.readAsStringSync() == latest.file.readAsStringSync()) {
        return true;
      }
      out.writeln(
        'The schema in $databaseSource differs from '
        '$snapshotDir/drift_schema_v${latest.version}.json. '
        'Bump schemaVersion, then run `dart run drift_dev make-migrations` '
        'and add the migration step (plan〈測試策略〉).',
      );
      return false;
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}

({int version, File file})? _latestSnapshot(Directory dir) {
  if (!dir.existsSync()) return null;
  final pattern = RegExp(r'drift_schema_v(\d+)\.json$');
  ({int version, File file})? latest;
  for (final file in dir.listSync().whereType<File>()) {
    final match = pattern.firstMatch(file.path);
    if (match == null) continue;
    final version = int.parse(match.group(1)!);
    if (latest == null || version > latest.version) {
      latest = (version: version, file: file);
    }
  }
  return latest;
}
