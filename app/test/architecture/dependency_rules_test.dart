import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dependency_rules.dart';

/// architecture〈依賴規則〉 的依賴規則，掃 `lib/` 底下所有手寫的 Dart 檔。
///
/// 下面的變異驗證兩個方向都要有：造一個違規，規則要紅；改無關的格式、
/// 命名或註解，規則不能紅。
void main() {
  test('lib/ follows the dependency rules', () {
    final violations = checkDependencyRules(readLibSources(Directory('lib')));
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  group('turns red on', () {
    void expectViolation(Map<String, String> files, Rule rule) {
      final violations = checkDependencyRules(files, packages: _packages);
      expect(
        violations.map((v) => v.rule),
        contains(rule),
        reason: 'expected $rule, got $violations',
      );
    }

    test('ui importing data', () {
      expectViolation({
        'ui/home/home_page.dart': "import 'package:fmp/data/database.dart';",
      }, Rule.uiReachesData);
    });

    test('ui importing data through a relative path', () {
      expectViolation({
        'ui/home/home_page.dart': "import '../../data/database.dart';",
      }, Rule.uiReachesData);
    });

    test('ui exporting data', () {
      expectViolation({
        'ui/home/home_page.dart': "export 'package:fmp/data/database.dart';",
      }, Rule.uiReachesData);
    });

    test('ui importing plugin internals', () {
      expectViolation({
        'ui/search/search_page.dart':
            "import 'package:fmp/plugins/src/js_engine.dart';",
      }, Rule.uiReachesPluginInternals);
    });

    test('drift outside data/', () {
      expectViolation({
        'library/playlists.dart': "import 'package:drift/drift.dart';",
      }, Rule.dataPackageOutsideData);
    });

    test('a platform package outside platform/', () {
      expectViolation({
        'playback/now_playing.dart':
            "import 'package:audio_service/audio_service.dart';",
      }, Rule.platformPackageOutsidePlatform);
    });

    test('a platform package in ui/', () {
      expectViolation({
        'ui/player/player_page.dart':
            "import 'package:audio_service/audio_service.dart';",
      }, Rule.platformPackageOutsidePlatform);
    });

    test('an audio player package in ui/', () {
      expectViolation({
        'ui/player/player_page.dart':
            "import 'package:just_audio/just_audio.dart';",
      }, Rule.platformPackageOutsidePlatform);
    });

    test('an audio player package in another module', () {
      expectViolation({
        'library/preview.dart': "import 'package:media_kit/media_kit.dart';",
      }, Rule.platformPackageOutsidePlatform);
    });

    test('an audio player package in playback/ outside backends/', () {
      expectViolation({
        'playback/queue.dart': "import 'package:just_audio/just_audio.dart';",
      }, Rule.platformPackageOutsidePlatform);
    });

    test('another platform package in playback/backends/', () {
      expectViolation({
        'playback/backends/just_audio_backend.dart':
            "import 'package:audio_service/audio_service.dart';",
      }, Rule.platformPackageOutsidePlatform);
    });

    test('Platform.isXxx outside platform/', () {
      expectViolation({
        'playback/backend.dart': '''
import 'dart:io';
bool get useMpv => Platform.isWindows;
''',
      }, Rule.platformCheckOutsidePlatform);
    });

    test('a prefixed Platform.isXxx outside platform/', () {
      expectViolation({
        'core/paths.dart': '''
import 'dart:io' as io;
bool get mac => io.Platform.isMacOS;
''',
      }, Rule.platformCheckOutsidePlatform);
    });

    test('a source id compared with ==', () {
      expectViolation({
        'library/refresh.dart': '''
bool slow(String sourceId) => sourceId == 'bilibili';
''',
      }, Rule.sourceIdBranch);
    });

    test('a source id compared with != in another case', () {
      expectViolation({
        'library/refresh.dart': '''
bool fast(String sourceId) => "YouTube" != sourceId;
''',
      }, Rule.sourceIdBranch);
    });

    test('a source id as a switch case', () {
      expectViolation({
        'playback/quality.dart': '''
int bitrate(String sourceId) {
  switch (sourceId) {
    case 'netease':
      return 320;
  }
  return 128;
}
''',
      }, Rule.sourceIdBranch);
    });

    test('a source id in a switch expression', () {
      expectViolation({
        'playback/quality.dart': '''
int bitrate(String sourceId) => switch (sourceId) {
  'youtube' => 160,
  _ => 128,
};
''',
      }, Rule.sourceIdBranch);
    });

    test('a source id in an if-case', () {
      expectViolation({
        'lyrics/match.dart': '''
void pick(String id) {
  if (id case 'lrclib') return;
}
''',
      }, Rule.sourceIdBranch);
    });

    test('the logging package outside core/log/', () {
      expectViolation({
        'plugins/host.dart': "import 'package:logger/logger.dart';",
      }, Rule.logPackageOutsideLogFacade);
    });

    test('the logging package elsewhere in core/', () {
      expectViolation({
        'core/net/client.dart': "import 'package:logger/logger.dart' as lg;",
      }, Rule.logPackageOutsideLogFacade);
    });

    test('the JS engine or HTTP client outside plugins/', () {
      expectViolation({
        'playback/lyrics_script.dart': "import 'package:fjs/fjs.dart';",
      }, Rule.pluginPackageOutsidePlugins);
      expectViolation({
        'ui/search/search_page.dart': "import 'package:fjs/fjs.dart' as js;",
      }, Rule.pluginPackageOutsidePlugins);
      expectViolation({
        'ui/search/search_page.dart': "import 'package:dio/dio.dart';",
      }, Rule.pluginPackageOutsidePlugins);
      expectViolation({
        'core/net/client.dart': "import 'package:dio/dio.dart' show Dio;",
      }, Rule.pluginPackageOutsidePlugins);
    });

    test('an unclassified package', () {
      expectViolation({
        'core/net.dart': "import 'package:left_pad/left_pad.dart';",
      }, Rule.unclassifiedPackage);
    });
  });

  group('stays green on', () {
    void expectClean(Map<String, String> files) {
      final violations = checkDependencyRules(files, packages: _packages);
      expect(violations, isEmpty, reason: violations.join('\n'));
    }

    test('ui importing a module, domain and the plugins public library', () {
      expectClean({
        'ui/search/search_page.dart': '''
import "package:fmp/library/playlists.dart";
import 'package:fmp/domain/track.dart' show Track;
import 'package:fmp/plugins/plugins.dart';
import '../../playback/queue.dart';
''',
      });
    });

    test('an import split over several lines with combinators', () {
      expectClean({
        'ui/x/renamed_page.dart': '''
import 'package:fmp/library/playlists.dart'
    show
        Playlist,
        PlaylistRepository
    hide Unused;
''',
      });
    });

    test('drift inside data/', () {
      expectClean({
        'data/database.dart': "import 'package:drift/drift.dart';",
        'data/tables/tracks.dart': "import 'package:drift/drift.dart' as d;\nclass T extends d.Table {}",
      });
    });

    test('a platform package and Platform.isXxx inside platform/', () {
      expectClean({
        'platform/media_controls.dart': '''
import 'dart:io';
import 'package:audio_service/audio_service.dart';
bool get windows => Platform.isWindows;
''',
      });
    });

    test('the audio player packages in playback/backends/', () {
      expectClean({
        'playback/backends/just_audio_backend.dart':
            "import 'package:just_audio/just_audio.dart';",
        'playback/backends/media_kit_backend.dart':
            "import 'package:media_kit/media_kit.dart' as mk;",
        'platform/audio_backend_choice.dart':
            "import 'package:just_audio/just_audio.dart';",
      });
    });

    test('Platform.isXxx and source ids that only appear in comments', () {
      expectClean({
        'playback/backend.dart': '''
/// Never branch on Platform.isWindows here; ask platform/ instead.
// if (sourceId == 'bilibili') is what we must not write.
/* switch (id) { case 'netease': } */
void play() {}
''',
      });
    });

    test('source ids used as data rather than as a branch', () {
      expectClean({
        'plugins/bundled.dart': '''
const bundledPluginDirs = ['bilibili', 'youtube', 'netease', 'lrclib'];
final log = 'loaded bilibili plugin';
bool other(String a) => a == 'bilibili-legacy';
''',
      });
    });

    test('the logging package inside core/log/', () {
      expectClean({
        'core/log/log.dart': '''
import 'package:logger/logger.dart' as lg;
final printer = lg.LogfmtPrinter();
''',
        'core/log/sinks/file_sink.dart':
            "import 'package:logger/logger.dart' show AdvancedFileOutput;",
      });
    });

    test('the JS engine and HTTP client anywhere inside plugins/', () {
      expectClean({
        'plugins/src/js_engine.dart': "import 'package:fjs/fjs.dart';",
        'plugins/src/deep/engine_pool.dart':
            "import 'package:fjs/fjs.dart' show JsEngine;",
        'plugins/src/host_network.dart':
            "import 'package:dio/dio.dart' as http;",
      });
    });

    test('other Platform members outside platform/', () {
      expectClean({
        'core/env.dart': '''
import 'dart:io';
final sep = Platform.pathSeparator;
''',
      });
    });
  });
}

const _packages = {
  'flutter': PackageScope.anywhere,
  'fmp': PackageScope.anywhere,
  'drift': PackageScope.dataOnly,
  'audio_service': PackageScope.platformOnly,
  'just_audio': PackageScope.audioBackend,
  'media_kit': PackageScope.audioBackend,
  'logger': PackageScope.logFacade,
  'fjs': PackageScope.pluginsOnly,
  'dio': PackageScope.pluginsOnly,
};
