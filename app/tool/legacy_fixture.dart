// 把合成的舊版（Isar）資料庫寫到指定資料夾的 fmp_database.isar，給 M5 舊資料
// 匯入的實機驗證用（資料全是編造的，見 test/support/legacy_database.dart）。
//
// 在 app/ 執行：
//   dart run tool/legacy_fixture.dart <輸出資料夾> [--schema-version=<N>|none]
// 預設 schemaVersion 4（舊 App 跑完 migration 的狀態）；`none` 是沒有版本欄位
// 的 v0。資料夾已有 fmp_database.isar 時拒絕覆寫。
import 'dart:io';

import '../test/support/legacy_database.dart';
import '../test/support/libisar.dart';

Future<void> main(List<String> arguments) async {
  final positional = arguments.where((a) => !a.startsWith('--')).toList();
  if (positional.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/legacy_fixture.dart <output directory> '
      '[--schema-version=<N>|none]',
    );
    exitCode = 64;
    return;
  }
  int? schemaVersion = 4;
  for (final argument in arguments.where((a) => a.startsWith('--'))) {
    const prefix = '--schema-version=';
    if (!argument.startsWith(prefix)) {
      stderr.writeln('Unknown option: $argument');
      exitCode = 64;
      return;
    }
    final value = argument.substring(prefix.length);
    schemaVersion = value == 'none' ? null : int.tryParse(value);
    if (value != 'none' && schemaVersion == null) {
      stderr.writeln('Invalid schema version.');
      exitCode = 64;
      return;
    }
  }

  final directory = Directory(positional.single);
  if (File('${directory.path}/fmp_database.isar').existsSync()) {
    stderr.writeln('fmp_database.isar already exists; refusing to overwrite.');
    exitCode = 73;
    return;
  }
  await loadLibisarForTests();
  final file = await writeSyntheticLegacyDatabase(
    directory,
    schemaVersion: schemaVersion,
  );
  stdout.writeln('Wrote ${file.path}');
}
