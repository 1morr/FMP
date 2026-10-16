import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/layer_imports.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(LayerImportsTest));
}

@reflectiveTest
class LayerImportsTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => LayerImports();

  // 報

  Future<void> test_relativeImportLeavingThePackage() => assertLints(
    'lib/ui/page.dart',
    "import [!'../../../lib/services/audio/audio_provider.dart'!];\n",
  );

  Future<void> test_relativeImportLeavingThePackageFromTest() => assertLints(
    'test/ui/page_test.dart',
    "import [!'../../../lib/main.dart'!];\n",
  );

  Future<void> test_fileUri() => assertLints(
    'lib/ui/page.dart',
    "import [!'file:///c/fmp/lib/x.dart'!];\n",
  );

  Future<void> test_dataPackageOutsideData() => assertLints(
    'lib/ui/page.dart',
    "import [!'package:drift/drift.dart'!];\n"
        "import [!'package:drift_flutter/drift_flutter.dart'!];\n"
        "import [!'package:sqlite3/sqlite3.dart'!];\n",
  );

  Future<void> test_platformPackageOutsidePlatform() => assertLints(
    'lib/settings/theme.dart',
    "import [!'package:path_provider/path_provider.dart'!];\n"
        "import [!'package:window_manager/window_manager.dart'!];\n"
        "import [!'package:smtc_windows/smtc_windows.dart'!];\n"
        "import [!'package:url_launcher/url_launcher.dart'!];\n"
        "import [!'package:share_plus/share_plus.dart'!];\n"
        "import [!'package:share_plus_platform_interface/share_plus_platform_interface.dart'!];\n"
        "import [!'package:audio_service_platform_interface/audio_service_platform_interface.dart'!];\n",
  );

  Future<void> test_ownerPackagesOutsideTheirDirectory() => assertLints(
    'lib/playback/controller.dart',
    "import [!'package:just_audio/just_audio.dart'!];\n"
        "import [!'package:dio/dio.dart'!];\n"
        "import [!'package:dio_cookie_manager/dio_cookie_manager.dart'!];\n"
        "import [!'package:cookie_jar/cookie_jar.dart'!];\n"
        "import [!'package:flutter_js/flutter_js.dart'!];\n"
        "import [!'package:isar_community/isar.dart'!];\n"
        "import [!'package:background_downloader/background_downloader.dart'!];\n",
  );

  // ADR 0018：兩個播放引擎只在後端實作目錄；控制器、平台層、UI 都不行。
  // media_kit 的 libs 套件（media_kit_libs_windows_audio）算在同一系列。
  // audio_session（Android 的音訊中斷，design §7.6）也只在後端目錄：控制器
  // 拿到的是後端轉好的事件。
  Future<void> test_playbackEnginesOutsideTheBackends() async {
    for (final path in [
      'lib/playback/playback_controller.dart',
      'lib/playback/backends_helpers.dart',
      'lib/platform/audio/audio_windows.dart',
      'lib/ui/player_bar/player_bar.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:just_audio/just_audio.dart'!];\n"
        "import [!'package:media_kit/media_kit.dart'!];\n"
        "import [!'package:media_kit_libs_windows_audio/media_kit_libs_windows_audio.dart'!];\n"
        "import [!'package:audio_session/audio_session.dart'!];\n",
      );
    }
  }

  // ADR 0018：AudioBackend 只給後端目錄、PlaybackSession 與組裝點；結束原因
  // 只給後端目錄與路由器。同前綴的 backends_helpers.dart、playback_session_x
  // 不算在允許清單內；別名、show、相對路徑、export 都一樣報。
  Future<void> test_restrictedPlaybackFilesFromOutside() async {
    for (final path in [
      'lib/playback/playback_controller.dart',
      'lib/playback/backends_helpers.dart',
      'lib/playback/playback_session_helpers.dart',
      'lib/ui/player/player_bar.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:test/playback/backends/audio_backend.dart'!];\n"
        "import [!'package:test/playback/backends/backend_rules.dart'!] as rules;\n",
      );
    }
    // 同一個測試裡每個路徑只寫一次：analyzer 會沿用第一次的解析結果。
    await assertLints(
      'lib/playback/queue_model.dart',
      "import [!'backends/audio_backend.dart'!] show AudioBackend;\n"
          "export [!'backends/backend_rules.dart'!];\n",
    );
    // 各自只准一邊：路由器不碰後端介面，PlaybackSession 不碰結束原因。
    await assertLints(
      'lib/playback/playback_event_router.dart',
      "import [!'package:test/playback/backends/audio_backend.dart'!];\n",
    );
    await assertLints(
      'lib/playback/playback_session.dart',
      "import [!'package:test/playback/backends/backend_rules.dart'!];\n",
    );
  }

  // ADR 0016：cache manager 只在快取模組，封面 widget 只在封面元件。同系列
  // （`cached_network_image_platform_interface`）一樣報；同前綴的
  // `lib/data/cache_helpers.dart`、`lib/ui/artwork_helpers.dart` 不在擁有的目錄裡。
  Future<void> test_imageCachePackagesOutsideTheirOwners() async {
    for (final path in [
      'lib/data/repositories/plugin_repository.dart',
      'lib/data/cache_helpers.dart',
      'lib/plugins/plugin_artwork.dart',
      'lib/ui/artwork_helpers.dart',
      'lib/ui/search/search_page.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:flutter_cache_manager/flutter_cache_manager.dart'!];\n"
        "import [!'package:cached_network_image/cached_network_image.dart'!];\n"
        "import [!'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'!];\n",
      );
    }
    // 各自只准一邊：快取模組不碰 widget，封面元件不碰 cache manager。
    await assertLints(
      'lib/data/cache/cache_store.dart',
      "import [!'package:cached_network_image/cached_network_image.dart'!];\n",
    );
    await assertLints(
      'lib/ui/artwork/artwork_image.dart',
      "import [!'package:flutter_cache_manager/flutter_cache_manager.dart'!];\n",
    );
  }

  // ADR 0016：快取目錄只經快取模組取得。平台層的其他檔案（能力宣告）、資料層的
  // 其他位置、同前綴的 `cache_directory_helpers.dart`、`lib/data/cache_helpers.dart`
  // 都報；別名、相對路徑、export 一樣報。
  Future<void> test_cacheDirectoryFromOutside() async {
    for (final path in [
      'lib/platform/platform_capabilities.dart',
      'lib/platform/cache_directory_helpers.dart',
      'lib/data/providers.dart',
      'lib/data/cache_helpers.dart',
      'lib/plugins/plugin_artwork.dart',
      'lib/ui/settings/settings_page.dart',
      'lib/main_helpers.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:test/platform/cache_directory/cache_directory.dart'!] as dir;\n",
      );
    }
    await assertLints(
      'lib/platform/connectivity/connectivity.dart',
      "import [!'../cache_directory/cache_directory.dart'!];\n"
          "export [!'package:test/platform/cache_directory/cache_directory.dart'!];\n",
    );
  }

  // M3 design §12.5：fixture 的錄製、重播與格式只給插件開發工具。registry、名稱相近的
  // `lib/plugins/devtools/`、介面、網路層的其他檔案都報；別名、相對路徑、export 一樣報。
  Future<void> test_fixtureFromOutside() async {
    for (final path in [
      'lib/plugins/plugin_registry.dart',
      'lib/plugins/devtools/x.dart',
      'lib/ui/debug/debug_page.dart',
      'lib/core/network/source_http_client.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:test/core/network/fixture/fixture.dart'!] as f;\n",
      );
    }
    await assertLints(
      'lib/ui/debug/debug_log.dart',
      "import [!'../../core/network/fixture/fixture.dart'!];\n"
          "export [!'package:test/core/network/fixture/fixture_adapters.dart'!];\n",
    );
  }

  Future<void> test_fixtureFromAllowedImporters() async {
    for (final path in [
      'lib/plugins/dev/case_runner.dart',
      'lib/core/network/fixture/fixture_adapters.dart',
      'test/plugins/contract/contract_runner.dart',
    ]) {
      await assertLints(
        path,
        "import 'package:test/core/network/fixture/fixture.dart';\n",
      );
    }
    // 名稱相近的別的檔案與目錄、註解與字串裡提到的不報。
    await assertLints(
      'lib/core/network/source_http_client.dart',
      "import 'package:test/core/network/fixture_helpers.dart';\n"
          "import 'package:test/core/network/fixtures/x.dart';\n"
          "// import 'package:test/core/network/fixture/fixture.dart';\n"
          "const text = \"import 'fixture/fixture.dart';\";\n",
    );
  }

  Future<void> test_legacyImportFromOutside() => assertLints(
    'lib/data/database.dart',
    "import [!'package:test/legacy_import/reader.dart'!];\n",
  );

  Future<void> test_coreImportsAnUpperLayer() => assertLints(
    'lib/core/errors/app_error.dart',
    "import [!'package:test/ui/toast/toast.dart'!];\n"
        "import [!'../../data/database.dart'!];\n"
        "import [!'package:test/settings/appearance.dart'!];\n",
  );

  Future<void> test_domainImportsPlayback() => assertLints(
    'lib/domain/track_key.dart',
    "import [!'package:test/playback/queue_model.dart'!];\n",
  );

  Future<void> test_dataImportsUi() =>
      assertLints('lib/data/database.dart', "import [!'../ui/page.dart'!];\n");

  // 設定、播放、插件都讀資料層（Notifier 讀 repository、佇列存檔、插件清單），
  // 資料層反過來 import 它們就是循環。
  Future<void> test_dataImportsAnUpperLayer() => assertLints(
    'lib/data/cache/cache_store.dart',
    "import [!'package:test/settings/network_settings.dart'!];\n"
        "import [!'../../playback/playback_controller.dart'!];\n"
        "import [!'package:test/plugins/plugin_registry.dart'!];\n",
  );

  // 播放層不認得介面：系統媒體控制的封面曾經從 `lib/ui/artwork/` 借
  // `pickArtwork`（M2 PR 16a，搬到 `lib/domain/`）。
  Future<void> test_playbackImportsUi() async {
    for (final path in [
      'lib/playback/playback_providers.dart',
      'lib/playback/backends/just_audio_backend.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:test/ui/artwork/artwork_image.dart'!] show pickArtwork;\n",
      );
    }
    await assertLints(
      'lib/playback/now_playing_publisher.dart',
      "import [!'../ui/shell/app_shell.dart'!];\n"
          "export [!'package:test/ui/toast/toast.dart'!];\n",
    );
  }

  // 排程器與電台（M3）：下層不認得它們，它們也不 import 介面；排程器另外不認得
  // 電台與插件（登記工作的人，不是被它呼叫的人）。
  Future<void> test_lowerLayersImportSchedulerOrRadio() async {
    await assertLints(
      'lib/core/network/network_status.dart',
      "import [!'package:test/scheduler/background_scheduler.dart'!];\n"
          "import [!'../../radio/radio_service.dart'!];\n",
    );
    await assertLints(
      'lib/domain/track_key.dart',
      "import [!'package:test/scheduler/background_scheduler.dart'!];\n",
    );
    await assertLints(
      'lib/data/repositories/scheduler_runs_repository.dart',
      "import [!'package:test/radio/radio_service.dart'!];\n"
          "import [!'../../scheduler/background_scheduler.dart'!];\n",
    );
  }

  Future<void> test_schedulerImportsUiRadioOrPlugins() async {
    await assertLints(
      'lib/scheduler/background_scheduler.dart',
      "import [!'package:test/ui/toast/toast.dart'!];\n"
          "import [!'../radio/radio_service.dart'!];\n"
          "import [!'package:test/plugins/plugin_registry.dart'!];\n",
    );
    await assertLints(
      'lib/radio/radio_status_job.dart',
      "import [!'package:test/ui/toast/toast.dart'!];\n",
    );
  }

  // 反方向與近似名稱不報：電台與介面讀排程器、排程器讀 core／data／app，
  // `scheduler_x`、`radio_x` 開頭的別的目錄不是它們。
  Future<void> test_schedulerNearMisses() async {
    await assertLints(
      'lib/scheduler/background_scheduler.dart',
      "import 'package:test/core/network/network_status.dart';\n"
          "import 'package:test/data/repositories/scheduler_runs_repository.dart';\n"
          "import 'package:test/app/app_lifecycle.dart';\n"
          "import 'package:test/ui_helpers/x.dart';\n"
          "// import 'package:test/ui/toast/toast.dart';\n",
    );
    await assertLints(
      'lib/radio/radio_near_miss.dart',
      "import 'package:test/scheduler/background_scheduler.dart';\n"
          "import 'package:test/plugins/plugin_registry.dart';\n"
          "import 'package:test/data/repositories/scheduler_runs_repository.dart';\n",
    );
    await assertLints(
      'lib/ui/radio/radio_page.dart',
      "import 'package:test/radio/radio_service.dart';\n"
          "import 'package:test/scheduler/background_scheduler.dart';\n",
    );
    await assertLints(
      'lib/core/network/network_status.dart',
      "import 'package:test/scheduler_extras/x.dart';\n"
          "import 'package:test/radio_extras/x.dart';\n",
    );
  }

  // 音樂庫（M4）：下層與排程器不認得它（背景工作與介面才呼叫它），它不 import 介面。
  Future<void> test_lowerLayersImportLibrary() async {
    await assertLints(
      'lib/core/network/network_status.dart',
      "import [!'package:test/library/playlist_refresher.dart'!];\n",
    );
    await assertLints(
      'lib/domain/playlist.dart',
      "import [!'../library/playlist_importer.dart'!];\n",
    );
    await assertLints(
      'lib/data/repositories/playlist_repository.dart',
      "import [!'package:test/library/playlist_refresher.dart'!];\n",
    );
    await assertLints(
      'lib/scheduler/background_scheduler.dart',
      "import [!'package:test/library/playlist_refresher.dart'!];\n",
    );
  }

  Future<void> test_libraryImportsUi() => assertLints(
    'lib/library/playlist_refresher.dart',
    "import [!'package:test/ui/toast/toast.dart'!];\n"
        "import [!'../ui/shell/app_shell.dart'!];\n",
  );

  // 反方向與近似名稱不報：介面讀音樂庫、音樂庫讀 core／data／plugins／scheduler／radio，
  // `ui/library/` 與 `library_x` 開頭的別的目錄不是它。
  Future<void> test_libraryNearMisses() async {
    await assertLints(
      'lib/library/playlist_refresher.dart',
      "import 'package:test/core/errors/app_error.dart';\n"
          "import 'package:test/data/repositories/playlist_repository.dart';\n"
          "import 'package:test/plugins/plugin_registry.dart';\n"
          "import 'package:test/scheduler/background_scheduler.dart';\n"
          "import 'package:test/radio/radio_service.dart';\n"
          "import 'package:test/ui_kit/widgets.dart';\n"
          "// import 'package:test/ui/toast/toast.dart';\n",
    );
    await assertLints(
      'lib/ui/library/library_page.dart',
      "import 'package:test/library/playlist_refresher.dart';\n",
    );
    await assertLints(
      'lib/core/network/network_status.dart',
      "import 'package:test/library_extras/x.dart';\n"
          "// import 'package:test/library/playlist_refresher.dart';\n",
    );
    await assertLints(
      'lib/library_extras/x.dart',
      "import 'package:test/ui/toast/toast.dart';\n",
    );
  }

  // 排行（M4）：下層與排程器不認得它，它不 import 介面與音樂庫；快取只經 `cache_store.dart`，
  // 不碰 `cache.db` 的表與資料庫類別。
  Future<void> test_lowerLayersImportCharts() async {
    await assertLints(
      'lib/core/network/network_status.dart',
      "import [!'package:test/charts/chart_cache.dart'!];\n",
    );
    await assertLints(
      'lib/domain/playlist.dart',
      "import [!'../charts/chart_jobs.dart'!];\n",
    );
    await assertLints(
      'lib/data/cache/cache_store.dart',
      "import [!'package:test/charts/chart_cache.dart'!];\n",
    );
    await assertLints(
      'lib/scheduler/background_scheduler.dart',
      "import [!'package:test/charts/chart_jobs.dart'!];\n",
    );
  }

  Future<void> test_chartsImportUiOrLibrary() => assertLints(
    'lib/charts/chart_jobs.dart',
    "import [!'package:test/ui/toast/toast.dart'!];\n"
        "import [!'../library/playlist_refresher.dart'!];\n",
  );

  Future<void> test_chartsImportCacheTables() => assertLints(
    'lib/charts/chart_cache.dart',
    "import [!'package:test/data/cache/cache_tables.dart'!];\n"
        "import [!'../data/cache/cache_database.dart'!];\n",
  );

  // 反方向與近似名稱不報：介面讀排行、排行讀 core／data／plugins／scheduler，經 `CacheStore`
  // 讀寫快取；`charts_x` 開頭的別的目錄、`cache_store_helpers.dart` 不是被擋的檔案。
  Future<void> test_chartsNearMisses() async {
    await assertLints(
      'lib/charts/chart_jobs.dart',
      "import 'package:test/core/errors/app_error.dart';\n"
          "import 'package:test/data/cache/cache_store.dart';\n"
          "import 'package:test/data/cache/cache_tables_helpers.dart';\n"
          "import 'package:test/data/repositories/chart_settings_repository.dart';\n"
          "import 'package:test/plugins/plugin_registry.dart';\n"
          "import 'package:test/scheduler/background_scheduler.dart';\n"
          "import 'package:test/radio/radio_service.dart';\n"
          "import 'package:test/ui_kit/widgets.dart';\n"
          "// import 'package:test/data/cache/cache_tables.dart';\n"
          "// import 'package:test/ui/toast/toast.dart';\n",
    );
    await assertLints(
      'lib/ui/home/chart_section.dart',
      "import 'package:test/charts/chart_cache.dart';\n",
    );
    await assertLints(
      'lib/data/cache/cache_store.dart',
      "import 'package:test/data/cache/cache_tables.dart';\n"
          "import 'package:test/charts_extras/x.dart';\n",
    );
    await assertLints(
      'lib/charts_extras/x.dart',
      "import 'package:test/ui/toast/toast.dart';\n"
          "import 'package:test/library/playlist_refresher.dart';\n"
          "import 'package:test/data/cache/cache_tables.dart';\n",
    );
  }

  // 反方向照常；名稱以 `ui` 開頭的別的目錄、`playback` 開頭的介面檔不報。
  Future<void> test_uiMayImportPlayback() async {
    await assertLints(
      'lib/ui/player/player_bar.dart',
      "import 'package:test/playback/playback_controller.dart';\n",
    );
    await assertLints(
      'lib/playback/queue_model.dart',
      "import 'package:test/ui_kit/widgets.dart';\n"
          "import '../domain/track_info.dart';\n",
    );
    await assertLints(
      'lib/playback_ui/page.dart',
      "import 'package:test/ui/toast/toast.dart';\n",
    );
  }

  Future<void> test_exportAndConditionalImport() => assertLints(
    'lib/ui/page.dart',
    "export [!'package:dio/dio.dart'!];\n"
        "import 'package:test/ui/a.dart'\n"
        "    if (dart.library.io) [!'package:path_provider/path_provider.dart'!];\n",
  );

  // 不報

  Future<void> test_ownerDirectoriesMayImport() async {
    await assertLints(
      'lib/data/database.dart',
      "import 'package:drift/drift.dart';\n"
          "import 'package:sqlite3/sqlite3.dart';\n",
    );
    await assertLints(
      'lib/platform/app_data_directory/app_data_directory.dart',
      "import 'package:path_provider/path_provider.dart';\n",
    );
    await assertLints(
      'lib/platform/media_controls/media_controls_windows.dart',
      "import 'package:smtc_windows/smtc_windows.dart' as smtc;\n"
          "import 'package:url_launcher/url_launcher.dart';\n",
    );
    await assertLints(
      'lib/playback/backends/just_audio_backend.dart',
      "import 'package:just_audio/just_audio.dart';\n",
    );
    await assertLints(
      'lib/core/network/http.dart',
      "import 'package:dio/dio.dart';\n"
          "import 'package:dio_cookie_manager/dio_cookie_manager.dart';\n"
          "import 'package:cookie_jar/cookie_jar.dart';\n",
    );
    await assertLints(
      'lib/legacy_import/reader.dart',
      "import 'package:isar_community/isar.dart';\n"
          "import 'package:test/legacy_import/schema.dart';\n",
    );
  }

  Future<void> test_playbackEnginesInTheBackends() async {
    await assertLints(
      'lib/playback/backends/media_kit_backend.dart',
      "import 'package:media_kit/media_kit.dart';\n"
          "import 'package:media_kit_libs_windows_audio/media_kit_libs_windows_audio.dart';\n"
          "import 'package:just_audio/just_audio.dart';\n",
    );
    await assertLints(
      'lib/playback/backends/just_audio_backend.dart',
      "import 'package:audio_session/audio_session.dart';\n"
          "import 'package:just_audio/just_audio.dart';\n",
    );
    // 名稱相似但不同系列（不是 `<鍵>_` 開頭）的套件不算。
    await assertLints(
      'lib/playback/playback_controller.dart',
      "import 'package:media_kitchen/media_kitchen.dart';\n"
          "import 'package:just_audiobook/just_audiobook.dart';\n"
          "import 'package:audio_sessions/audio_sessions.dart';\n",
    );
  }

  // ADR 0030：pub_semver 只在插件庫流程；同前綴的 pub_semver_x 算同系列，
  // 名稱相似但不同系列（pub_semvers）不算。
  Future<void> test_pubSemverOutsideThePluginRepository() async {
    for (final path in [
      'lib/plugins/plugin_registry.dart',
      'lib/plugins/repository_helpers/update.dart',
      'lib/ui/plugins/plugin_page.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:pub_semver/pub_semver.dart'!];\n"
        "import [!'package:pub_semver_extras/pub_semver_extras.dart'!];\n",
      );
    }
  }

  Future<void> test_pubSemverInThePluginRepository() async {
    await assertLints(
      'lib/plugins/repository/plugin_updates.dart',
      "import 'package:pub_semver/pub_semver.dart';\n",
    );
    await assertLints(
      'lib/plugins/plugin_registry.dart',
      "import 'package:pub_semvers/pub_semvers.dart';\n",
    );
  }

  // design §2.2：qr_flutter 只在 QR 登入畫面（lib/ui/accounts/）；名稱相似但不同
  // 系列（qr_flutters）不算。
  Future<void> test_qrFlutterOutsideTheAccountsPages() async {
    for (final path in [
      'lib/ui/settings/settings_page.dart',
      'lib/ui/accounts_extra/qr.dart',
      'lib/plugins/accounts/qr_login.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:qr_flutter/qr_flutter.dart'!];\n",
      );
    }
  }

  Future<void> test_qrFlutterInTheAccountsPages() async {
    await assertLints(
      'lib/ui/accounts/qr_login_dialog.dart',
      "import 'package:qr_flutter/qr_flutter.dart';\n",
    );
    await assertLints(
      'lib/ui/settings/settings_page.dart',
      "import 'package:qr_flutters/qr_flutters.dart';\n",
    );
  }

  // design §2.2：archive 只在診斷包的組裝（lib/app/diagnostics/）；名稱相似但不同系列
  // （archives）不算。
  Future<void> test_archiveOutsideTheDiagnostics() async {
    for (final path in [
      'lib/app/app_scope.dart',
      'lib/app/diagnostics_extra/zip.dart',
      'lib/ui/debug/debug_overview.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:archive/archive.dart'!];\n"
        "import [!'package:archive_io/archive_io.dart'!];\n",
      );
    }
  }

  Future<void> test_archiveInTheDiagnostics() async {
    await assertLints(
      'lib/app/diagnostics/diagnostics_zip.dart',
      "import 'package:archive/archive.dart';\n",
    );
    await assertLints(
      'lib/ui/debug/debug_overview.dart',
      "import 'package:archives/archives.dart';\n",
    );
  }

  // design §2.2：unorm_dart、string_similarity 只在評分核心（lib/core/matching/）；
  // 同前綴的目錄（matching_extra）不算評分核心，名稱相似但不同系列的套件不算。
  Future<void> test_matchingPackagesOutsideTheMatchingCore() async {
    for (final path in [
      'lib/core/redaction/redactor.dart',
      'lib/core/matching_extra/fold.dart',
      'lib/library/external_import.dart',
    ]) {
      await assertLints(
        path,
        "import [!'package:unorm_dart/unorm_dart.dart'!];\n"
        "import [!'package:string_similarity/string_similarity.dart'!];\n"
        "import [!'package:string_similarity_extras/extras.dart'!];\n",
      );
    }
  }

  Future<void> test_matchingPackagesInTheMatchingCore() async {
    await assertLints(
      'lib/core/matching/normalize.dart',
      "import 'package:unorm_dart/unorm_dart.dart';\n"
          "import 'package:string_similarity/string_similarity.dart';\n",
    );
    await assertLints(
      'lib/library/external_import.dart',
      "import 'package:unorms/unorms.dart';\n"
          "import 'package:string_similarityx/string_similarityx.dart';\n",
    );
  }

  Future<void> test_restrictedPlaybackFilesFromAllowedImporters() async {
    await assertLints(
      'lib/playback/playback_session.dart',
      "import 'package:test/playback/backends/audio_backend.dart';\n"
          "import 'backends/audio_backend.dart' as backend;\n",
    );
    await assertLints(
      'lib/playback/playback_providers.dart',
      "import 'package:test/playback/backends/audio_backend.dart';\n",
    );
    await assertLints(
      'lib/playback/playback_event_router.dart',
      "import 'package:test/playback/backends/backend_rules.dart';\n",
    );
    await assertLints(
      'lib/playback/backends/media_kit_backend.dart',
      "import 'package:test/playback/backends/audio_backend.dart';\n"
          "import 'backend_rules.dart';\n",
    );
    // 測試照既有規則不受依賴表限制（假後端、契約）。
    await assertLints(
      'test/playback/fake_audio_backend.dart',
      "import 'package:test/playback/backends/audio_backend.dart';\n"
          "import 'package:test/playback/backends/backend_rules.dart';\n",
    );
  }

  Future<void> test_imageCachePackagesInTheirOwners() async {
    await assertLints(
      'lib/data/cache/image_cache_manager.dart',
      "import 'package:flutter_cache_manager/flutter_cache_manager.dart';\n",
    );
    await assertLints(
      'lib/ui/artwork/artwork_image.dart',
      "import 'package:cached_network_image/cached_network_image.dart';\n"
          "import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';\n",
    );
    // 名稱相近、不是 `<鍵>_` 開頭的套件不算；測試不受依賴表限制。
    await assertLints(
      'lib/ui/search/search_page.dart',
      "import 'package:flutter_cache_managers/flutter_cache_managers.dart';\n"
          "import 'package:cached_network_images/cached_network_images.dart';\n",
    );
    await assertLints(
      'test/ui/artwork/artwork_image_test.dart',
      "import 'package:flutter_cache_manager/flutter_cache_manager.dart';\n"
          "import 'package:cached_network_image/cached_network_image.dart';\n",
    );
  }

  Future<void> test_cacheDirectoryFromAllowedImporters() async {
    await assertLints(
      'lib/platform/platform.dart',
      "import 'package:test/platform/cache_directory/cache_directory.dart';\n",
    );
    await assertLints(
      'lib/data/cache/cache_store.dart',
      "import 'package:test/platform/cache_directory/cache_directory.dart';\n",
    );
    await assertLints(
      'lib/main.dart',
      "import 'platform/cache_directory/cache_directory.dart';\n",
    );
    await assertLints(
      'test/data/cache/cache_store_test.dart',
      "import 'package:test/platform/cache_directory/cache_directory.dart';\n",
    );
    // 名稱相近的別的目錄與檔案、註解與字串裡提到的不報。
    await assertLints(
      'lib/settings/network_settings.dart',
      "import 'package:test/platform/cache_sizes/cache_sizes.dart';\n"
          "import 'package:test/platform/cache_directory.dart';\n"
          "import 'package:test/platform/cache_directory_names/names.dart';\n"
          "// import 'package:test/platform/cache_directory/cache_directory.dart';\n"
          "const text = \"import 'cache_directory/cache_directory.dart';\";\n",
    );
  }

  // 名稱相近的別的檔案（工廠 audio_backends.dart）、註解與字串裡提到的不報。
  Future<void> test_restrictedPlaybackFilesNearMisses() => assertLints(
    'lib/playback/playback_controller.dart',
    "import 'package:test/playback/backends/audio_backends.dart';\n"
        "import 'package:test/playback/backends/backend_rules_notes.dart';\n"
        "// import 'package:test/playback/backends/audio_backend.dart';\n"
        "const text = \"import 'backends/backend_rules.dart';\";\n",
  );

  Future<void> test_testsMayImportAnyPackage() => assertLints(
    'test/data/database_test.dart',
    "import 'package:drift/drift.dart';\n"
        "import 'package:test/legacy_import/reader.dart';\n",
  );

  Future<void> test_sameNamePrefixWithoutUnderscore() => assertLints(
    'lib/ui/page.dart',
    "import 'package:driftwood/driftwood.dart';\n"
        "import 'package:diox/diox.dart';\n",
  );

  Future<void> test_allowedDirections() => assertLints(
    'lib/ui/page.dart',
    "import 'dart:async';\n"
        "import 'package:test/core/errors/app_error.dart';\n"
        "import 'package:test/data/database.dart';\n"
        "import '../domain/track_key.dart';\n"
        "import 'toast/toast.dart';\n",
  );

  Future<void> test_dataMayImportDomain() => assertLints(
    'lib/data/database.dart',
    "import '../domain/track_key.dart';\n",
  );

  // 反方向照常；資料層裡名稱相近的檔案與目錄（`settings` 開頭但不是
  // `lib/settings/`）不報。
  Future<void> test_upperLayersMayImportData() async {
    await assertLints(
      'lib/settings/network_settings.dart',
      "import 'package:test/data/providers.dart';\n"
          "import '../data/repositories/network_settings_repository.dart';\n",
    );
    await assertLints(
      'lib/data/cache/cache_store.dart',
      "import 'package:test/data/repositories/network_settings_repository.dart';\n"
          "import 'package:test/settings_backup/backup.dart';\n"
          "import 'package:test/platform/platform_capabilities.dart';\n",
    );
  }

  Future<void> test_mentionsInCommentsAndStrings() => assertLints(
    'lib/ui/page.dart',
    "// import 'package:drift/drift.dart';\n"
        "const text = \"import 'package:dio/dio.dart';\";\n",
  );
}
