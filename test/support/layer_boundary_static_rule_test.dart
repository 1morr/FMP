import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/` 內部的 import / export 目標。
///
/// 全庫的指令都是 `package:fmp/…` 形式（`always_use_package_imports` 加上
/// barrel 檔的手動收斂），所以只認這一種就夠了 —— 相對路徑一旦出現，
/// analyzer 會先擋下來。
/// 單雙引號都認：`prefer_single_quotes` 沒開，`import "package:fmp/…"` 合法，
/// 以前只認單引號時它會直接穿過這兩條規則。
/// 用 `[ \t]*` 而不是 `\s*`：後者會把前一行的換行一起吃掉，行號會少一。
final _fmpDirectivePattern = RegExp(
  r"""^[ \t]*(?:import|export)\s+(['"])package:fmp/([^'"]+)\1""",
  multiLine: true,
);

/// 規則 A：`lib/core/` 與 `lib/data/` 不得往上 import。
///
/// 這兩層是所有 feature 共同依賴的底座。它們一旦反向依賴某個 feature，
/// 那個 feature 就沒辦法單獨被搬動或刪除，而編譯器不會有任何抱怨。
const _lowerLayers = <String>['lib/core/', 'lib/data/'];

/// 唯一的具名例外。
///
/// `track_extensions.dart` 讀下載檔案是否存在來決定 `Track` 的顯示狀態。
/// 要修的是依賴方向（把「檔案存在嗎」倒過來由呼叫端傳入），不是檔案位置，
/// 所以本輪不動它 —— 但也不讓它變成無聲的先例。
const _lowerLayerExceptions = <String, String>{
  'lib/core/extensions/track_extensions.dart':
      'providers/download/file_exists_cache.dart',
};

/// 規則 B：跨 feature 的邊，快照。
///
/// feature 身分是 `lib/services/<name>/` 與 `lib/providers/<name>/` 的
/// `<name>` —— 兩個頂層目錄裝的是同一批 feature 的兩半，這裡把它們視為同一個。
///
/// 這是**快照不是白名單**：31 筆機械生成的「理由」會是橡皮圖章，而它要擋的
/// 只有一件事 —— 一條新的 feature 對 feature 的邊悄悄長出來。新增一筆時在該筆
/// 旁邊寫一行理由；移除耦合時也要把那一筆刪掉，否則快照會慢慢變成虛構。
const _knownFeatureEdges = <String>{
  'account -> media',
  'audio -> account',
  'audio -> download',
  'audio -> library',
  'audio -> lyrics',
  'audio -> network',
  // 排行榜要跟播放一樣帶登入狀態：B 站對匿名身分另有節流配額
  'cache -> account',
  'cache -> network',
  'download -> account',
  'download -> audio',
  'download -> library',
  'download -> lyrics',
  'download -> media',
  'download -> platform',
  'import -> account',
  // 歌單匯入的逐曲比對用搜尋層的 fan-out，兩邊共用同一份部分結果語意
  'import -> search',
  'library -> account',
  'library -> audio',
  'library -> download',
  'library -> import',
  'lyrics -> audio',
  'platform -> lyrics',
  'radio -> account',
  'radio -> audio',
  'search -> cache',
  'settings -> cache',
  'settings -> platform',
  'settings -> radio',
  'settings -> system',
  'system -> audio',
  'system -> backup',
  'system -> platform',
  'system -> update',
};

void main() {
  group('layer boundary', () {
    test('core and data do not import the layers above them', () {
      final offenders = <String>[];
      var scanned = 0;

      for (final file in _libDartFiles()) {
        final path = _posix(file.path);
        if (!_lowerLayers.any(path.startsWith)) continue;
        scanned++;
        offenders.addAll(upwardImportOffenders(path, file.readAsStringSync()));
      }

      // 掃描本身要有作用 —— 路徑寫錯時 offenders 也會是空的。
      expect(scanned, greaterThan(60));
      expect(offenders, isEmpty);
    });

    test('every named exception is still real', () {
      for (final entry in _lowerLayerExceptions.entries) {
        final file = File(entry.key);
        expect(
          file.existsSync(),
          isTrue,
          reason: '${entry.key} is excepted but no longer exists',
        );
        expect(
          file.readAsStringSync(),
          contains("package:fmp/${entry.value}"),
          reason:
              '${entry.key} no longer imports ${entry.value}; drop the exception',
        );
      }
    });

    test('no new edge between features', () {
      final sources = {
        for (final file in _libDartFiles())
          if (featureOf(_posix(file.path)) != null)
            _posix(file.path): file.readAsStringSync(),
      };
      final edges = featureEdges(sources);

      expect(sources.length, greaterThan(100));
      expect(
        edges.difference(_knownFeatureEdges),
        isEmpty,
        reason:
            'new feature-to-feature coupling; add it with a reason if intended',
      );
      expect(
        _knownFeatureEdges.difference(edges),
        isEmpty,
        reason: 'coupling is gone; drop the stale snapshot entries',
      );
    });

    test('the upward import rule catches a synthetic offender', () {
      const source = '''
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/data/models/track.dart';
''';
      expect(
        upwardImportOffenders('lib/data/repositories/example.dart', source),
        ['lib/data/repositories/example.dart:1 imports services/audio/'],
      );
    });

    test('the upward import rule ignores comments and order, not quotes', () {
      const clean = '''
// import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
''';
      const doubleQuoted = '''
import "package:fmp/data/models/track.dart";
import "package:fmp/providers/audio/audio_providers.dart";
''';

      expect(
        upwardImportOffenders('lib/data/repositories/example.dart', clean),
        isEmpty,
      );
      expect(
        upwardImportOffenders(
          'lib/data/repositories/example.dart',
          doubleQuoted,
        ),
        ['lib/data/repositories/example.dart:2 imports providers/audio/'],
      );
    });

    test('a new feature edge shows up, a same-feature import does not', () {
      const radio = '''
import 'package:fmp/services/audio/audio_provider.dart';
''';
      const radioWithLyrics = '''
import 'package:fmp/services/lyrics/lyrics_service.dart';
import 'package:fmp/services/audio/audio_provider.dart';
''';
      const sameFeature = '''
// import 'package:fmp/services/library/playlist_service.dart';
import "package:fmp/services/audio/audio_provider.dart";
''';

      expect(featureEdges({'lib/services/radio/x.dart': radio}), {
        'radio -> audio',
      });
      expect(featureEdges({'lib/services/radio/x.dart': radioWithLyrics}), {
        'radio -> audio',
        'radio -> lyrics',
      });
      expect(
        featureEdges({'lib/providers/audio/x.dart': sameFeature}),
        isEmpty,
      );
    });

    test('an excepted file reports nothing', () {
      const source =
          "import 'package:fmp/providers/download/file_exists_cache.dart';";
      expect(
        upwardImportOffenders(
          'lib/core/extensions/track_extensions.dart',
          source,
        ),
        isEmpty,
      );
    });
  });
}

/// `path` 屬於哪個 feature；不在 `services/` 或 `providers/` 底下就回 null。
String? featureOf(String path) {
  final parts = path.split('/');
  if (parts.length < 4) return null;
  if (parts[1] != 'services' && parts[1] != 'providers') return null;
  return parts[2];
}

/// 這些檔案 import 出去的 feature 對 feature 邊（`from -> to`）。
Set<String> featureEdges(Map<String, String> sourcesByPath) => {
  for (final MapEntry(key: path, value: source) in sourcesByPath.entries)
    for (final match in _fmpDirectivePattern.allMatches(source))
      if ((featureOf(path), featureOf('lib/${match.group(2)}')) case (
        final String from,
        final String to,
      ) when from != to)
        '$from -> $to',
};

/// [path] 這個底層檔案裡，違反規則 A 的每一行。
List<String> upwardImportOffenders(String path, String source) {
  final allowed = _lowerLayerExceptions[path];
  final offenders = <String>[];

  for (final match in _fmpDirectivePattern.allMatches(source)) {
    final target = match.group(2)!;
    if (!target.startsWith('services/') && !target.startsWith('providers/')) {
      continue;
    }
    if (allowed != null && target == allowed) continue;
    final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    final segments = target.split('/');
    offenders.add('$path:$line imports ${segments[0]}/${segments[1]}/');
  }
  return offenders;
}

Iterable<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where((file) => !file.path.endsWith('.g.dart'));

String _posix(String path) => path.replaceAll(r'\', '/');
