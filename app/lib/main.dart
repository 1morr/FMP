import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/database_error_app.dart';
import 'package:fmp/app/first_launch_import.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/app/legacy_import.dart';
import 'package:fmp/app/legacy_import_app.dart';
import 'package:fmp/app/licenses.dart';
import 'package:fmp/app/startup_diagnostics.dart';
import 'package:fmp/app/unsupported_platform_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/uncaught_errors.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/import/import_summary.dart';
import 'package:fmp/data/import/legacy_import_failed.dart';
import 'package:fmp/data/import/legacy_imports_repository.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/legacy_import/legacy_importer.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/app_restart/app_restart.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/legacy_data/legacy_data_locator.dart';
import 'package:fmp/platform/legacy_data/legacy_dev_entry.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/platform.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/platform/share/share.dart';
import 'package:fmp/platform/url_opener/url_opener.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerLicenses();
  final flavor = AppFlavor.parse(appFlavor);
  // dev 的舊資料副本（`--fmp-legacy-dir`）；prod 一律是 null（理由見 legacy_dev_entry.dart）。
  final legacyDirectory = legacyDirectoryPath(
    flavor,
    arguments,
    Platform.environment,
  );
  var platform = AppPlatform.current(flavor, legacyDirectory: legacyDirectory);
  // 沒有資料目錄的平台不啟動資料層，也沒有 log 檔（能力宣告 dataDirectory 為假）。
  final directory = await platform.dataDirectory?.resolve();
  // 資料目錄與之後的路徑在 log 檔與診斷包都是 `~\…`，不帶使用者名稱；要在寫第一筆 log 之前
  // 登記（M3 design §12.4）。
  final redactor = Redactor()
    ..registerHomeDirectory(platform.appInfo?.homeDirectory);
  final log = Log(
    redactor: redactor,
    // 這個建置的預設層級；「開發者」組的值由 FmpApp 讀出來之後套用（ADR 0025 §決定 1）。
    minimumLevel: buildDefaultLogLevel,
    file: directory == null
        ? null
        : LogFile(Directory(p.join(directory.path, logDirectoryName))),
  );
  routeUncaughtErrors(log, PlatformDispatcher.instance);
  // 實機驗證以這一筆確認是哪個 flavor、資料在哪（沒有身分頁了）。資料目錄的路徑可能含使用者
  // 名稱，門面遮蔽時已把家目錄換成 `~`。
  log.info(
    'App started',
    tag: 'app',
    fields: {
      'flavor': flavor.name,
      'dataDirectory': ?directory?.path,
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
  // 記憶體裡解碼好的圖片：大小由平台宣告，不開放設定（ADR 0016 §決定 4）。
  if (platform.capabilities.cache case final sizes?) {
    PaintingBinding.instance.imageCache
      ..maximumSize = sizes.memoryImages
      ..maximumSizeBytes = sizes.memoryImageBytes;
  }
  final diagnostics = StartupDiagnostics(
    flavor: flavor,
    redactor: redactor,
    logFile: log.file,
    fileDialogs: platform.fileDialogs,
  );
  // 首次啟動（沒有 fmp.db）且找得到舊版資料：先匯入（M5 design §3.1）。
  final legacyImport = LegacyImporter(
    dataDirectory: directory,
    log: log,
    locator: platform.legacyDataLocator!,
    secureStorage: platform.secureStorage!,
    importOutputDevice:
        platform.capabilities.playback?.outputDeviceSelection ?? false,
    fontChoices: platform.capabilities.fontChoices,
  );
  await cleanLegacyImportLeftovers(directory, log);
  var failedCredentials = const <String>{};
  if (needsFirstLaunchImport(directory)) {
    failedCredentials = await _importLegacyData(
      legacyImport: legacyImport,
      directory: directory,
      flavor: flavor,
      platform: platform,
      log: log,
      diagnostics: diagnostics,
    );
  }
  // 開不起來就只顯示錯誤頁，不在半開的資料庫上啟動（ADR 0010 §決定 3）；頁面有「重試」。
  final database = await _openDatabase(
    directory: directory,
    flavor: flavor,
    platform: platform,
    log: log,
    diagnostics: diagnostics,
  );
  // 換上資料庫之後寫憑證失敗的平台：補記進匯入紀錄，結果對話框才會說要重新登入。
  if (failedCredentials.isNotEmpty) {
    try {
      await LegacyImportsRepository(database)
          .addReloginPlatforms(failedCredentials);
    } on Object catch (error, stackTrace) {
      log.error(
        'Failed to record the credentials that need signing in again',
        tag: 'legacy-import',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  // 版本號與平台名稱：「關於」的版本列與 Debug 頁的概覽讀它（M3 design §12.1）。
  final appInfo = await platform.appInfo!.read();
  // 系統媒體控制在資料庫開好之後初始化；失敗就宣告為沒有，App 照常啟動。
  platform = await platform.withMediaControls(
    log: log,
    onFailure: (error, stackTrace) => log.error(
      'Failed to start the system media controls',
      tag: 'platform',
      error: error,
      stackTrace: stackTrace,
    ),
  );
  // 開好的資料庫與資料目錄只從這裡注入，其他地方不自己開。
  runApp(
    appProviderScope(
      key: const ValueKey('app'),
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        appFlavorProvider.overrideWithValue(flavor),
        legacyImportProvider.overrideWithValue(legacyImport),
        appInfoProvider.overrideWithValue(appInfo),
        dataDirectoryProvider.overrideWithValue(directory),
        logProvider.overrideWithValue(log),
        redactorProvider.overrideWithValue(redactor),
        platformCapabilitiesProvider.overrideWithValue(platform.capabilities),
        networkInterfacesProvider.overrideWithValue(platform.networkInterfaces),
        fileDialogsProvider.overrideWithValue(platform.fileDialogs),
        loginWebViewProvider.overrideWithValue(platform.loginWebView),
        urlOpenerProvider.overrideWithValue(platform.urlOpener),
        fileSharerProvider.overrideWithValue(platform.fileSharer),
        appRestarterProvider.overrideWithValue(platform.restarter!),
        systemMediaControlsProvider.overrideWithValue(platform.mediaControls),
        // 憑證的唯一存放處；有資料目錄的平台（Android、Windows）都有。
        secureStorageProvider.overrideWithValue(platform.secureStorage!),
        // 快取目錄只交給快取模組開（cacheStoreProvider）；開不起來 App 照常。
        cacheDirectoryProvider.overrideWithValue(platform.cacheDirectory!),
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

/// 開資料庫；開不起來就顯示 [DatabaseErrorApp]，「重試」再開一次，直到開成功才返回。
Future<AppDatabase> _openDatabase({
  required Directory directory,
  required AppFlavor flavor,
  required AppPlatform platform,
  required Log log,
  required StartupDiagnostics diagnostics,
}) async {
  Future<AppDatabase> open() async {
    try {
      return await openAppDatabase(directory);
    } on Object catch (error, stackTrace) {
      log.error(
        'Failed to open the database',
        tag: 'data',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  try {
    return await open();
  } on Object catch (error) {
    final opened = Completer<AppDatabase>();
    runApp(
      appProviderScope(
        key: const ValueKey('database-error'),
        child: DatabaseErrorApp(
          flavor: flavor,
          error: error,
          fontFallback: platform.capabilities.fontFallback,
          onRetry: () async => opened.complete(await open()),
          onExport: diagnostics.canExport
              ? (error) =>
                    diagnostics.export(kind: 'databaseOpen', error: error)
              : null,
        ),
      ),
    );
    return opened.future;
  }
}

/// 首次啟動：找舊版資料，找到就顯示 [LegacyImportApp] 並匯入。回傳換上資料庫之後寫憑證失敗的
/// 插件 id。沒有舊資料、找不到、或使用者選「以空白資料啟動」時返回空集合，由呼叫端照舊建空庫。
Future<Set<String>> _importLegacyData({
  required LegacyImport legacyImport,
  required Directory directory,
  required AppFlavor flavor,
  required AppPlatform platform,
  required Log log,
  required StartupDiagnostics diagnostics,
}) async {
  final LegacySource? source;
  try {
    source = await legacyImport.locate();
  } on Object catch (error, stackTrace) {
    // 例如 dev 的 `--fmp-legacy-dir` 指到真實的舊資料位置：拒絕，照空資料啟動。
    log.error(
      'Failed to look for the legacy data',
      tag: 'legacy-import',
      error: error,
      stackTrace: stackTrace,
    );
    return const {};
  }
  if (source == null) return const {};
  log.info('Legacy data found; importing', tag: 'legacy-import');
  final finished = Completer<Set<String>>();
  ImportSummary? stagedSummary;
  runApp(
    appProviderScope(
      key: const ValueKey('legacy-import'),
      child: LegacyImportApp(
        flavor: flavor,
        fontFallback: platform.capabilities.fontFallback,
        run: (progress) async {
          // 「重試」再跑一次：上一次的摘要不能帶進這一次的診斷。
          stagedSummary = null;
          try {
            final imported = await importOnFirstLaunch(
              legacy: legacyImport,
              source: source!,
              target: File(p.join(directory.path, databaseFileName)),
              log: log,
              progress: progress,
              onStaged: (summary) => stagedSummary = summary,
            );
            finished.complete(imported.failedCredentials);
          } on LegacyImportFailed catch (error, stackTrace) {
            // `LegacyImportFailed.toString` 不帶原因，原因只在這裡進 log（診斷包靠它）。轉換步驟的
            // 例外訊息可能帶著舊資料的值（曲名、歌單名），只記型別；其他步驟的原因是檔案、SQLite
            // 與讀取器的例外，路徑由門面遮成 `~`。
            final cause = error.cause;
            final logCause = error.step != LegacyImportStep.convert;
            log.error(
              'Importing the legacy data failed',
              tag: 'legacy-import',
              error: logCause ? cause ?? error : error,
              stackTrace: stackTrace,
              fields: {
                'step': error.step.name,
                'reason': error.reason,
                if (cause != null) 'causeType': '${cause.runtimeType}',
              },
            );
            rethrow;
          } on Object catch (error, stackTrace) {
            log.error(
              'Importing the legacy data failed',
              tag: 'legacy-import',
              error: error,
              stackTrace: stackTrace,
            );
            rethrow;
          }
        },
        onStartBlank: () async {
          log.info('Starting with empty data', tag: 'legacy-import');
          finished.complete(const {});
        },
        onExport: diagnostics.canExport
            ? (error, step) => diagnostics.export(
                kind: 'legacyImport',
                error: error,
                step: step?.name,
                details: {
                  if (stagedSummary case final summary?)
                    ...summaryDiagnostics(summary),
                },
              )
            : null,
      ),
    ),
  );
  return finished.future;
}
