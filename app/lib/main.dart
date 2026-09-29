import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/database_error_app.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/app/unsupported_platform_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/uncaught_errors.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/platform.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final flavor = AppFlavor.parse(appFlavor);
  final platform = AppPlatform.current(flavor);
  // 沒有資料目錄的平台不啟動資料層，也沒有 log 檔（能力宣告 dataDirectory 為假）。
  final directory = await platform.dataDirectory?.resolve();
  final redactor = Redactor();
  final log = Log(
    redactor: redactor,
    minimumLevel: buildDefaultLogLevel,
    file: directory == null
        ? null
        : LogFile(Directory(p.join(directory.path, logDirectoryName))),
  );
  routeUncaughtErrors(log, PlatformDispatcher.instance);
  log.info(
    'App started',
    tag: 'app',
    fields: {
      'flavor': flavor.name,
      'buildMode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    },
  );

  if (directory == null) {
    runApp(appProviderScope(child: UnsupportedPlatformApp(flavor: flavor)));
    return;
  }
  // 開不起來就只顯示錯誤頁，不在半開的資料庫上啟動（ADR 0010 §決定 3）。
  final AppDatabase database;
  try {
    database = await openAppDatabase(directory);
  } on Object catch (error, stackTrace) {
    log.error(
      'Failed to open the database',
      tag: 'data',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(
      appProviderScope(
        child: DatabaseErrorApp(flavor: flavor, error: error),
      ),
    );
    return;
  }
  // 開好的資料庫與資料目錄只從這裡注入，其他地方不自己開。
  runApp(
    appProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        dataDirectoryProvider.overrideWithValue(directory),
        logProvider.overrideWithValue(log),
        redactorProvider.overrideWithValue(redactor),
        // 插件的開發入口只在 dev（devPluginPath 在 prod 回 null；理由見
        // dev_plugin_entry.dart）。
        devPluginPathProvider.overrideWithValue(
          devPluginPath(flavor, arguments, Platform.environment),
        ),
      ],
      child: FmpApp(flavor: flavor),
    ),
  );
}
