import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';

import 'database_catalog.dart';
import 'database_migration.dart';

const String fmpDatabaseName = 'fmp_database';
const String fmpDatabaseDirectoryName = AppConstants.appName;
const String fmpDatabaseFileName = '$fmpDatabaseName.isar';
const String fmpDatabaseLockFileName = '$fmpDatabaseFileName.lock';

@visibleForTesting
Future<void> runDatabaseMigrationForTesting(Isar isar) =>
    runDatabaseMigration(isar);

String _resolveFmpDatabaseDirectoryPath(String documentsPath) {
  return p.join(documentsPath, fmpDatabaseDirectoryName);
}

@visibleForTesting
String resolveFmpDatabaseDirectoryPathForTesting(String documentsPath) {
  return _resolveFmpDatabaseDirectoryPath(documentsPath);
}

Future<Directory> _ensureFmpDatabaseDirectory(Directory documentsDir) async {
  final databaseDir = Directory(
    _resolveFmpDatabaseDirectoryPath(documentsDir.path),
  );

  if (!await databaseDir.exists()) {
    await databaseDir.create(recursive: true);
  }

  await _moveLegacyFmpDatabaseFiles(documentsDir, databaseDir);
  return databaseDir;
}

@visibleForTesting
Future<Directory> ensureFmpDatabaseDirectoryForTesting(Directory documentsDir) {
  return _ensureFmpDatabaseDirectory(documentsDir);
}

Future<Directory> resolveFmpDatabaseDirectory() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  return _ensureFmpDatabaseDirectory(documentsDir);
}

Future<void> _moveLegacyFmpDatabaseFiles(
  Directory documentsDir,
  Directory databaseDir,
) async {
  const fileNames = [
    fmpDatabaseFileName,
    fmpDatabaseLockFileName,
  ];

  for (final fileName in fileNames) {
    final legacyFile = File(p.join(documentsDir.path, fileName));
    if (!await legacyFile.exists()) {
      continue;
    }

    final targetFile = File(p.join(databaseDir.path, fileName));
    if (await targetFile.exists()) {
      continue;
    }

    await _moveFile(legacyFile, targetFile);
  }
}

Future<void> _moveFile(File source, File target) async {
  try {
    await source.rename(target.path);
  } on FileSystemException {
    await source.copy(target.path);
    await source.delete();
  }
}

Future<Isar> openFmpDatabase() async {
  final existing = Isar.getInstance(fmpDatabaseName);
  if (existing != null) {
    return existing;
  }

  final databaseDir = await resolveFmpDatabaseDirectory();
  return Isar.open(
    fmpDatabaseSchemas,
    directory: databaseDir.path,
    name: fmpDatabaseName,
    // Isar 的默认值是 1024 MiB（isar 3.1.0+1 的 Isar.defaultMaxSizeMiB）。
    // 这里曾经写 64，比默认值小 16 倍，而写满之后 Isar 直接抛错、FMP 没有
    // 任何溢出处理 —— 对一个会随使用时间单调增长的播放历史 / 下载记录库来说
    // 是迟早会踩到的上限。maxSizeMiB 是 mmap 的地址空间上限而非预分配，
    // 调大不会立刻占用磁盘。
    maxSizeMiB: 2048,
    compactOnLaunch: const CompactCondition(
      minFileSize: 8 * 1024 * 1024,
      minRatio: 2.0,
    ),
  );
}

final databaseProvider = FutureProvider<Isar>((ref) async {
  // 尝试复用 _preloadThemeSettings() 已打开的实例
  final isar = await openFmpDatabase();

  // 数据迁移和初始化（包含 PlayQueue 创建）
  await runDatabaseMigration(isar);

  return isar;
});

/// 数据库是否已初始化
final isDatabaseReadyProvider = Provider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  return db.hasValue;
});
