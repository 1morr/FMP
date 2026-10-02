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
        "import [!'package:window_manager/window_manager.dart'!];\n",
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
        "import [!'package:media_kit_libs_windows_audio/media_kit_libs_windows_audio.dart'!];\n",
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
    // 名稱相似但不同系列（不是 `<鍵>_` 開頭）的套件不算。
    await assertLints(
      'lib/playback/playback_controller.dart',
      "import 'package:media_kitchen/media_kitchen.dart';\n"
          "import 'package:just_audiobook/just_audiobook.dart';\n",
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

  Future<void> test_mentionsInCommentsAndStrings() => assertLints(
    'lib/ui/page.dart',
    "// import 'package:drift/drift.dart';\n"
        "const text = \"import 'package:dio/dio.dart';\";\n",
  );
}
