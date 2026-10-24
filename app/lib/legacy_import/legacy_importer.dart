import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/app/legacy_import.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/staging_import.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/legacy_import/legacy_account_converter.dart';
import 'package:fmp/legacy_import/legacy_backup_reader.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_database_reader.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:fmp/platform/legacy_data/legacy_credential_reader.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';

const _tag = 'legacy-import';

/// 暫存庫與讀取器的工作目錄放的目錄名，在資料目錄底下。啟動時整個清掉（[cleanLegacyImportLeftovers]）。
const legacyImportDirectoryName = 'legacy-import';

/// 舊資料匯入的流程（[LegacyImport] 的實作，M5 design §3.1）：讀舊資料庫與舊憑證 → 轉換 →
/// 寫暫存庫 → 驗證；換上之後寫憑證。
///
/// 每一步失敗都轉成 [LegacyImportFailed]（`step` 是失敗的那一步）；失敗時暫存檔已刪、
/// 舊檔沒動。log 只寫步驟、筆數與插件 id，不寫值。
final class LegacyImporter implements LegacyImport {
  LegacyImporter({
    required this._dataDirectory,
    required Log log,
    required this._locator,
    required this._secureStorage,
    required this._importOutputDevice,
    this._fontChoices = const [],
    LegacyDatabaseReader? reader,
    this._backupReader = const LegacyBackupReader(),
    StagingImport? staging,
  }) : _log = log,
       _reader =
           reader ??
           LegacyDatabaseReader(
             log: (message, fields) =>
                 log.info(message, tag: _tag, fields: fields),
           ),
       _staging = staging ?? StagingImport(log);

  final Directory _dataDirectory;
  final Log _log;
  final LegacyDataLocator _locator;
  final SecureStorage _secureStorage;

  /// 平台支援選輸出裝置時才把舊的輸出裝置設定帶過來（`PlaybackSupport.outputDeviceSelection`）。
  final bool _importOutputDevice;

  /// 目前平台外觀設定可選的字型（`PlatformCapabilities.fontChoices`）。
  final List<String> _fontChoices;
  final LegacyDatabaseReader _reader;
  final LegacyBackupReader _backupReader;
  final StagingImport _staging;

  Directory get _workRoot =>
      Directory(p.join(_dataDirectory.path, legacyImportDirectoryName));

  @override
  Future<LegacySource?> locate() => _locator.locate(log: _log);

  @override
  Future<LegacyStaged> stage(
    LegacySource source, {
    void Function(LegacyImportStep step)? progress,
    AppDatabase? replacing,
  }) async {
    progress?.call(LegacyImportStep.read);
    final LegacySnapshot snapshot;
    final Map<String, LegacyCredentialRead> credentialReads;
    try {
      await _workRoot.create(recursive: true);
      snapshot = await _reader.read(source.database, _workRoot);
      credentialReads = await source.credentialReader.read(
        legacyCredentialKeys.values.toList(),
      );
    } on Object catch (error) {
      throw LegacyImportFailed(
        LegacyImportStep.read,
        'Reading the legacy data failed',
        cause: error,
      );
    }

    return _convertAndWrite(
      snapshot,
      source: LegacyImportSource.database,
      credentialReads: credentialReads,
      progress: progress,
      replacing: replacing,
    );
  }

  @override
  Future<LegacyStaged> stageBackup(
    Uint8List bytes, {
    void Function(LegacyImportStep step)? progress,
    AppDatabase? replacing,
  }) async {
    progress?.call(LegacyImportStep.read);
    final ({LegacySnapshot snapshot, int version}) parsed;
    try {
      parsed = _backupReader.read(bytes);
    } on LegacyBackupRejected {
      rethrow;
    } on Object catch (error) {
      throw LegacyImportFailed(
        LegacyImportStep.read,
        'Reading the legacy backup failed',
        cause: error,
      );
    }
    return _convertAndWrite(
      parsed.snapshot,
      source: LegacyImportSource.backup,
      backupVersion: parsed.version,
      progress: progress,
      replacing: replacing,
    );
  }

  /// 讀完之後的共同部分：轉換 → 寫暫存庫 → 驗證。[replacing] 給了就在它的副本上取代
  /// （設定頁），否則寫全新的庫（首次啟動）。
  Future<LegacyStaged> _convertAndWrite(
    LegacySnapshot snapshot, {
    required LegacyImportSource source,
    required void Function(LegacyImportStep step)? progress,
    required AppDatabase? replacing,
    int? backupVersion,
    Map<String, LegacyCredentialRead>? credentialReads,
  }) async {
    progress?.call(LegacyImportStep.convert);
    final LegacyConversion conversion;
    // 毫秒精度：資料庫存毫秒，驗證比對才一致。
    final now = DateTime.fromMillisecondsSinceEpoch(
      clock.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    try {
      conversion = const LegacyConverter().convert(
        snapshot,
        source: source,
        backupVersion: backupVersion,
        now: now,
        importOutputDevice: _importOutputDevice,
        fontChoices: _fontChoices,
        credentials: credentialReads,
      );
    } on Object catch (error) {
      throw LegacyImportFailed(
        LegacyImportStep.convert,
        'Converting the legacy data failed',
        cause: error,
      );
    }

    final stamp = now.toIso8601String().replaceAll(RegExp('[:.]'), '');
    final file = File(p.join(_workRoot.path, 'staging-$stamp.db'));
    progress?.call(LegacyImportStep.write);
    ReplacedStaging? replaced;
    if (replacing == null) {
      await _staging.write(conversion.bundle, file, importedAt: now);
    } else {
      replaced = await _staging.writeReplacing(
        conversion.bundle,
        file,
        importedAt: now,
        current: replacing,
      );
    }
    progress?.call(LegacyImportStep.verify);
    await _staging.verify(conversion.bundle, file, replaced: replaced);
    final kept = replaced?.keptAccountPluginIds ?? const <String>{};
    _log.info(
      'Legacy data staged',
      tag: _tag,
      fields: {
        'source': source.name,
        'replacing': replacing != null,
        'credentialPlatforms': [
          for (final id in conversion.credentials.keys)
            if (!kept.contains(id)) id,
        ],
        'keptAccountPlatforms': kept.toList(),
        'reloginPlatforms': conversion.bundle.record.summary.reloginPlatforms,
      },
    );
    return LegacyStaged(
      file: file,
      credentials: conversion.credentials,
      summary: replaced?.summary ?? conversion.bundle.record.summary,
      keptAccountPluginIds: kept,
    );
  }

  @override
  Future<Set<String>> writeCredentials(
    LegacyStaged staged, {
    required Set<String> loggedInPluginIds,
  }) async {
    final failed = <String>{};
    for (final MapEntry(key: pluginId, value: credentials)
        in staged.credentials.entries) {
      if (loggedInPluginIds.contains(pluginId)) continue;
      try {
        await CredentialStore.writeImported(
          _secureStorage,
          pluginId,
          credentials,
        );
      } on Object catch (error) {
        // 錯誤的內容不寫（可能帶著值）：只記插件 id 與例外的型別。
        _log.warning(
          'Writing an imported credential failed',
          tag: _tag,
          fields: {'pluginId': pluginId, 'errorType': '${error.runtimeType}'},
        );
        failed.add(pluginId);
      }
    }
    return failed;
  }
}

/// 啟動時清掉 `<資料目錄>/legacy-import/` 裡殘留的工作目錄與暫存庫（上次匯入中途結束留下的）。
/// 刪不掉只記 log，不擋啟動。回傳刪了幾個項目。
Future<int> cleanLegacyImportLeftovers(Directory dataDirectory, Log log) async {
  final directory = Directory(
    p.join(dataDirectory.path, legacyImportDirectoryName),
  );
  if (!directory.existsSync()) return 0;
  var count = 0;
  try {
    await for (final entity in directory.list(followLinks: false)) {
      try {
        await entity.delete(recursive: true);
        count++;
      } on FileSystemException catch (error) {
        log.warning(
          'Deleting a legacy import leftover failed',
          tag: _tag,
          fields: {'errorType': '${error.runtimeType}'},
        );
      }
    }
  } on FileSystemException catch (error) {
    log.warning(
      'Listing the legacy import leftovers failed',
      tag: _tag,
      fields: {'errorType': '${error.runtimeType}'},
    );
  }
  return count;
}
