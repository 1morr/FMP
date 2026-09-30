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
