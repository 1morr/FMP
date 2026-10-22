// 舊版（Isar）資料庫的筆數統計：只印每個 collection 的筆數與 schemaVersion，
// 不印任何內容（M5 舊資料匯入的事前確認用）。
//
// 參數是一份舊資料庫**副本**的路徑（先自己複製一份，不要指向舊 App 正在用的
// 檔案）。讀取器還會再複製一次到暫存目錄、開那一份、讀完刪除。
//
// 在 app/ 執行：dart run tool/legacy_counts.dart <副本路徑>/fmp_database.isar
import 'dart:io';

import 'package:fmp/legacy_import/legacy_database_reader.dart';

import '../test/support/libisar.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/legacy_counts.dart <copy of fmp_database.isar>',
    );
    exitCode = 64;
    return;
  }
  final database = File(arguments.single);
  if (!database.existsSync()) {
    stderr.writeln('File not found.');
    exitCode = 66;
    return;
  }

  await loadLibisarForTests();
  final workRoot = await Directory.systemTemp.createTemp('fmp-legacy-counts');
  try {
    final snapshot = await LegacyDatabaseReader(log: (_, _) {})
        .read(database, workRoot);
    for (final MapEntry(:key, :value) in snapshot.counts.entries) {
      stdout.writeln('$key: $value');
    }
    stdout.writeln('schemaVersion: ${snapshot.storedSchemaVersion ?? 'none'}');
  } on LegacyReadException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    await workRoot.delete(recursive: true);
  }
}
