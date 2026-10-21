import 'dart:convert';

import 'package:fmp/data/database/backup_format.dart';

/// 資料層測試用的 [BackupPluginReader]：只讀 `manifest_json` 欄，不認得腳本標頭。真正的規則
/// （標頭與列要一致）在 `lib/app/backup.dart` 的 `readBackupPlugin`，由 `backup_test.dart` 測。
BackupPlugin? lenientBackupReader({
  required String id,
  required String version,
  required String manifestJson,
  required String script,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(manifestJson);
  } on FormatException {
    decoded = null;
  }
  var name = id;
  var hosts = const <String>[];
  if (decoded is Map<String, Object?>) {
    if (decoded['name'] case final String value when value.isNotEmpty) {
      name = value;
    }
    if (decoded['allowedHosts'] case final List<Object?> list) {
      hosts = [
        for (final host in list)
          if (host is String) host,
      ];
    }
  }
  return BackupPlugin(id: id, name: name, version: version, hosts: hosts);
}
