import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/core/json_shape.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/plugin_host.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'package:fmp/plugins/health/checks.dart';

import 'package:fmp/core/network/fixture/fixture.dart';

import 'plugin_harness.dart';

// `lib/plugins/types/fmp-plugin.d.ts` 是給插件作者的介面說明。這裡以一個只
// 認得那個檔案寫法的小解析器，比對它與 Dart 端實際的欄位表、宿主 API 與
// 列舉；檔案結構改了，先改解析器再改比對。

// 換行統一成 LF：Windows 的 checkout 可能是 CRLF，變異案例以 `\n` 比對。
final _dts = File('lib/plugins/types/fmp-plugin.d.ts')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

/// Dart 端有欄位表的 interface。契約檢查的格式（checks.json、fixture）由
/// 契約執行器解碼。
final _shapes = <String, JsonShape>{
  ...manifestShapes,
  ...sourceDtoShapes,
  ...hostApiShapes,
  ...checkShapes,
  ...fixtureShapes,
};

/// 沒有 JSON 欄位表的 interface：宿主 API 由執行中的 runtime 比對，其他是
/// 說明用的型別。
const _apiInterfaces = {
  'FmpHost',
  'FmpHttp',
  'FmpCrypto',
  'FmpStorage',
  'FmpCredentials',
  'FmpLog',
  'FmpError',
  'FmpPluginExports',
};

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// 每個 interface 的成員：名稱 → 是否必填（沒有 `?`）。
Map<String, Map<String, bool>> _interfaces(String dts) {
  final source = _withoutComments(dts);
  final result = <String, Map<String, bool>>{};
  for (final match in RegExp(r'interface\s+(\w+)\s*\{').allMatches(source)) {
    var depth = 1;
    var end = match.end;
    while (depth > 0) {
      final char = source[end++];
      if (char == '{') depth++;
      if (char == '}') depth--;
    }
    final body = source.substring(match.end, end - 1);
    result[match[1]!] = {
      for (final statement in body.split(';'))
        if (RegExp(r'^(?:readonly\s+)?(\w+)(\?)?\s*[:(]')
                .firstMatch(statement.trim())
            case final member?)
          member[1]!: member[2] == null,
    };
  }
  return result;
}

/// `type Name = 'a' | 'b';` 的字串值。
Set<String> _union(String dts, String name) {
  final source = _withoutComments(dts);
  final match = RegExp('type\\s+$name\\s*=([^;]*);').firstMatch(source);
  if (match == null) return {};
  return {
    for (final value in RegExp("'([^']*)'").allMatches(match[1]!)) value[1]!,
  };
}

/// d.ts 與 Dart 欄位表的差異；一致時是空的。
List<String> _shapeDifferences(String dts) {
  final interfaces = _interfaces(dts);
  final differences = <String>[];
  for (final MapEntry(key: name, value: shape) in _shapes.entries) {
    final members = interfaces[name];
    if (members == null) {
      differences.add('$name is missing from the d.ts');
    } else if (!_sameShape(members, shape)) {
      differences.add('$name: d.ts $members, Dart $shape');
    }
  }
  for (final name in interfaces.keys) {
    if (!_shapes.containsKey(name) && !_apiInterfaces.contains(name)) {
      differences.add('$name has no Dart shape');
    }
  }
  return differences;
}

bool _sameShape(Map<String, bool> a, Map<String, bool> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

void main() {
  test('interfaces match the Dart JSON shapes', () {
    expect(_shapeDifferences(_dts), isEmpty);
  });

  group('the comparison', () {
    test('catches a missing field', () {
      final mutated = _dts.replaceFirst('  uploader?: string | null;\n', '');

      expect(mutated, isNot(_dts));
      expect(_shapeDifferences(mutated), [startsWith('TrackSummary:')]);
    });

    test('catches a field that became optional', () {
      final mutated = _dts.replaceFirst(
        '  hasMore: boolean;',
        '  hasMore?: boolean;',
      );

      expect(_shapeDifferences(mutated), [startsWith('SearchPage:')]);
    });

    test('catches an interface without a Dart shape', () {
      final mutated =
          '$_dts\nexport interface LyricsPage { lines: string[]; }\n';

      expect(_shapeDifferences(mutated), ['LyricsPage has no Dart shape']);
    });

    test('ignores comments, layout and member order', () {
      final reformatted = _dts
          .replaceAll('\n  ', '\n\t\t')
          .replaceFirst(
            '  sourceId: string;\n  cid?: number | null;',
            '  // extra: string;\n  /* hidden: number; */ cid?: number | null; '
                'sourceId: string;',
          );

      expect(reformatted, isNot(_dts));
      expect(_shapeDifferences(reformatted), isEmpty);
    });
  });

  test('FmpHost matches the fmp object the prelude builds', () async {
    final runtime = await PluginHarness().runtime('''
export function shape() {
  const out = {};
  for (const key of Object.keys(fmp)) {
    out[key] = typeof fmp[key] === 'object' ? Object.keys(fmp[key]).sort() : typeof fmp[key];
  }
  return out;
}
''');
    final interfaces = _interfaces(_dts);
    final host = interfaces['FmpHost']!;
    final hostTypes = {
      for (final match in RegExp(
        r'readonly\s+(\w+):\s*(Fmp\w+);',
      ).allMatches(_withoutComments(_dts)))
        match[1]!: match[2]!,
    };

    final actual = await runtime.invoke('shape', null) as Map;

    expect(actual.keys.toSet(), host.keys.toSet());
    expect(actual['apiVersion'], 'number');
    for (final MapEntry(key: member, value: type) in hostTypes.entries) {
      expect(
        actual[member],
        (interfaces[type]!.keys.toList()..sort()),
        reason: 'fmp.$member vs $type',
      );
    }
  });

  test('the capability union matches PluginCapability', () {
    expect(_union(_dts, 'FmpCapability'), {
      for (final capability in PluginCapability.values) capability.wireName,
    });
  });

  test(
    'the login unions match LoginMethod, LoginRefresh and LoginQrStatus',
    () {
      expect(_union(_dts, 'FmpLoginMethod'), {
        for (final method in LoginMethod.values) method.wireName,
      });
      expect(_union(_dts, 'FmpLoginRefresh'), {
        for (final refresh in LoginRefresh.values) refresh.wireName,
      });
      expect(_union(_dts, 'LoginQrStatus'), {
        for (final status in LoginQrStatus.values) status.wireName,
      });
      // 變異：多一個值就對不上。
      expect(
        _union(
          _dts.replaceFirst("'qr' | 'webView'", "'qr' | 'passkey' | 'webView'"),
          'FmpLoginMethod',
        ),
        isNot({for (final method in LoginMethod.values) method.wireName}),
      );
    },
  );

  test('the live room statuses match LiveRoomStatus', () {
    expect(_union(_dts, 'LiveRoomStatus'), {
      for (final status in LiveRoomStatus.values) status.wireName,
    });
    // 變異：少一個值就對不上。
    expect(
      _union(_dts.replaceFirst(" | 'offline'", ''), 'LiveRoomStatus'),
      isNot({for (final status in LiveRoomStatus.values) status.wireName}),
    );
  });

  test('the live exports match LiveExports and the d.ts exports', () {
    final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

    expect(exports.containsAll(LiveExports.all), isTrue);
    // 變異：d.ts 少一個匯出就對不上。
    final mutated = _interfaces(
      _dts.replaceFirst('  liveStatus?(', '  liveStatusRenamed?('),
    )['FmpPluginExports']!.keys.toSet();
    expect(mutated.containsAll(LiveExports.all), isFalse);
  });

  test('the mix export is named after the capability in the d.ts', () {
    final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

    expect(exports.contains(PluginCapability.mix.wireName), isTrue);
    // 變異：d.ts 少了 mix 匯出就對不上。
    final mutated = _interfaces(
      _dts.replaceFirst('  mix?(', '  mixRenamed?('),
    )['FmpPluginExports']!.keys.toSet();
    expect(mutated.contains(PluginCapability.mix.wireName), isFalse);
  });

  test('the multiPart export is named after the capability in the d.ts', () {
    final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

    expect(exports.contains(PluginCapability.multiPart.wireName), isTrue);
    // 變異：d.ts 少了 multiPart 匯出就對不上。
    final mutated = _interfaces(
      _dts.replaceFirst('  multiPart?(', '  multiPartRenamed?('),
    )['FmpPluginExports']!.keys.toSet();
    expect(mutated.contains(PluginCapability.multiPart.wireName), isFalse);
  });

  test('the trackDetail export is named after the capability in the d.ts', () {
    final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

    expect(exports.contains(PluginCapability.trackDetail.wireName), isTrue);
    // 變異：d.ts 少了 trackDetail 匯出就對不上。
    final mutated = _interfaces(
      _dts.replaceFirst('  trackDetail?(', '  trackDetailRenamed?('),
    )['FmpPluginExports']!.keys.toSet();
    expect(mutated.contains(PluginCapability.trackDetail.wireName), isFalse);
  });

  test(
    'the importPlaylist exports match ImportPlaylistExports and the d.ts',
    () {
      final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

      expect(exports.containsAll(ImportPlaylistExports.all), isTrue);
      // 變異：d.ts 少一個匯出就對不上。
      for (final (original, renamed) in [
        ('  playlistFromUrl?(', '  playlistFromUrlRenamed?('),
        ('  importPlaylist?(', '  importPlaylistRenamed?('),
      ]) {
        final mutated = _interfaces(
          _dts.replaceFirst(original, renamed),
        )['FmpPluginExports']!.keys.toSet();
        expect(mutated.containsAll(ImportPlaylistExports.all), isFalse);
      }
      // 無關的格式變動（縮排）不影響。
      expect(_dts, contains('  playlistFromUrl?('));
      final reindented = _interfaces(
        _dts.replaceFirst('  playlistFromUrl?(', '\t\tplaylistFromUrl?('),
      )['FmpPluginExports']!.keys.toSet();
      expect(reindented.containsAll(ImportPlaylistExports.all), isTrue);
    },
  );

  test('the importPlaylist page fields match between the d.ts and Dart', () {
    expect(sourceDtoShapes['PlaylistPage']!['cursor'], isFalse);
    expect(_interfaces(_dts)['PlaylistPage']!['cursor'], isFalse);
    expect(sourceDtoShapes['PlaylistPage']!['items'], isTrue);
    expect(_interfaces(_dts)['RemotePlaylistItem']!['track'], isTrue);
    expect(_interfaces(_dts)['PlaylistIdRef']!['playlistId'], isTrue);
    expect(_interfaces(_dts)['PlaylistMixSeedRef']!['mixSeed'], isTrue);
    // 變異：d.ts 把 items 改成選填、少了 total、或 track 改成選填，欄位表比對就紅。
    for (final (original, mutated) in [
      ('  items: RemotePlaylistItem[];', '  items?: RemotePlaylistItem[];'),
      ('  total?: number | null;\n', ''),
      ('  track: TrackSummary;', '  track?: TrackSummary;'),
      ('  mixSeed: MixSeed;', '  mixSeed?: MixSeed;'),
    ]) {
      expect(_dts, contains(original));
      expect(
        _shapeDifferences(_dts.replaceFirst(original, mutated)),
        isNotEmpty,
        reason: original,
      );
    }
    // 無關的變動（多一行說明）不影響。
    expect(
      _shapeDifferences(
        _dts.replaceFirst(
          '  total?: number | null;',
          '  /** 說明 */\n  total?: number | null;',
        ),
      ),
      isEmpty,
    );
  });

  test('the charts exports match ChartsExports and the d.ts', () {
    final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

    expect(exports.containsAll(ChartsExports.all), isTrue);
    // 變異：d.ts 少一個匯出就對不上。
    for (final (original, renamed) in [
      ('  chartList?(', '  chartListRenamed?('),
      ('  chart?(', '  chartRenamed?('),
    ]) {
      expect(_dts, contains(original));
      final mutated = _interfaces(
        _dts.replaceFirst(original, renamed),
      )['FmpPluginExports']!.keys.toSet();
      expect(mutated.containsAll(ChartsExports.all), isFalse, reason: original);
    }
    // 無關的格式變動（縮排）不影響。
    final reindented = _interfaces(
      _dts.replaceFirst('  chartList?(', '\t\tchartList?('),
    )['FmpPluginExports']!.keys.toSet();
    expect(reindented.containsAll(ChartsExports.all), isTrue);
  });

  test('the charts fields match between the d.ts and Dart', () {
    expect(sourceDtoShapes['ChartList']!['charts'], isTrue);
    expect(sourceDtoShapes['ChartRef']!['title'], isTrue);
    expect(sourceDtoShapes['ChartPage']!['tracks'], isTrue);
    expect(_interfaces(_dts)['ChartQuery']!['chartId'], isTrue);
    expect(checkShapes['FmpChecks']!['charts'], isFalse);
    // 變異：d.ts 把 charts 或 tracks 改成選填、chartId 改成選填、少了 FmpChecks 的 charts，
    // 欄位表比對就紅。
    for (final (original, mutated) in [
      ('  charts: ChartRef[];', '  charts?: ChartRef[];'),
      ('  tracks: TrackSummary[];', '  tracks?: TrackSummary[];'),
      (
        '  title: string;\n}\n\n/** chart 的輸入',
        '  title?: string;\n}\n\n/** chart 的輸入',
      ),
      ('  charts?: FmpChartsCheck | null;\n', ''),
    ]) {
      expect(_dts, contains(original));
      expect(
        _shapeDifferences(_dts.replaceFirst(original, mutated)),
        isNotEmpty,
        reason: original,
      );
    }
    // 無關的變動（多一行說明）不影響。
    expect(
      _shapeDifferences(
        _dts.replaceFirst(
          '  tracks: TrackSummary[];',
          '  /** 說明 */\n  tracks: TrackSummary[];',
        ),
      ),
      isEmpty,
    );
  });

  test('the libraryRead exports match LibraryReadExports and the d.ts', () {
    final exports = _interfaces(_dts)['FmpPluginExports']!.keys.toSet();

    // libraryLiveRooms 是選填匯出，d.ts 也要宣告（型別與匯出表一致）。
    expect(exports.containsAll(LibraryReadExports.all), isTrue);
    // 變異：d.ts 少一個匯出就對不上。
    for (final (original, renamed) in [
      ('  libraryPlaylists?(', '  libraryPlaylistsRenamed?('),
      ('  libraryLiveRooms?(', '  libraryLiveRoomsRenamed?('),
    ]) {
      expect(_dts, contains(original));
      final mutated = _interfaces(
        _dts.replaceFirst(original, renamed),
      )['FmpPluginExports']!.keys.toSet();
      expect(
        mutated.containsAll(LibraryReadExports.all),
        isFalse,
        reason: original,
      );
    }
    // 無關的格式變動（縮排）不影響。
    final reindented = _interfaces(
      _dts.replaceFirst('  libraryPlaylists?(', '		libraryPlaylists?('),
    )['FmpPluginExports']!.keys.toSet();
    expect(reindented.containsAll(LibraryReadExports.all), isTrue);
  });

  test('the libraryRead fields match between the d.ts and Dart', () {
    expect(sourceDtoShapes['LibraryPlaylistPage']!['playlists'], isTrue);
    expect(sourceDtoShapes['LibraryPlaylist']!['writable'], isTrue);
    expect(sourceDtoShapes['LibraryPlaylist']!['trackCount'], isFalse);
    expect(sourceDtoShapes['LibraryPlaylistsQuery']!['cursor'], isFalse);
    expect(checkShapes['FmpChecks']!['libraryRead'], isFalse);
    expect(checkShapes['FmpLibraryReadCheck']!['requiresLogin'], isTrue);
    // 變異：writable 或 requiresLogin 改成選填、cursor 改成必填、少了 FmpChecks 的
    // libraryRead，欄位表比對就紅。
    for (final (original, mutated) in [
      ('  writable: boolean;\n}', '  writable?: boolean;\n}'),
      (
        '  requiresLogin: true;\n  /** 見 FmpChecks。 */\n  mutates?: true | null;\n}\n\nexport interface FmpSearchCheck',
        '  requiresLogin?: true;\n  /** 見 FmpChecks。 */\n  mutates?: true | null;\n}\n\nexport interface FmpSearchCheck',
      ),
      (
        '  cursor?: string | null;\n}\n\n/** libraryPlaylists 的回傳值',
        '  cursor: string | null;\n}\n\n/** libraryPlaylists 的回傳值',
      ),
      ('  libraryRead?: FmpLibraryReadCheck | null;\n', ''),
    ]) {
      expect(_dts, contains(original));
      expect(
        _shapeDifferences(_dts.replaceFirst(original, mutated)),
        isNotEmpty,
        reason: original,
      );
    }
    // 無關的變動（多一行說明）不影響。
    expect(
      _shapeDifferences(
        _dts.replaceFirst(
          '  playlists: LibraryPlaylist[];',
          '  /** 說明 */\n  playlists: LibraryPlaylist[];',
        ),
      ),
      isEmpty,
    );
  });

  test('partIndex and parentTitle match between the d.ts and Dart', () {
    expect(sourceDtoShapes['TrackSummary']!['partIndex'], isFalse);
    expect(sourceDtoShapes['TrackSummary']!['parentTitle'], isFalse);
    expect(_interfaces(_dts)['TrackSummary']!['partIndex'], isFalse);
    expect(_interfaces(_dts)['TrackSummary']!['parentTitle'], isFalse);
    // 變異：d.ts 把其中一個改成必填、或少了一個，欄位表比對就紅。
    for (final (original, mutated) in [
      ('  partIndex?: number', '  partIndex: number'),
      ('  parentTitle?: string', '  parentTitle: string'),
      ('  parentTitle?: string | null;\n', ''),
    ]) {
      expect(_dts, contains(original));
      expect(
        _shapeDifferences(_dts.replaceFirst(original, mutated)),
        isNotEmpty,
        reason: original,
      );
    }
    // 無關的變動（改寫說明）不影響。
    expect(_dts, contains('/** 分 P 曲目所屬影片的標題'));
    expect(
      _shapeDifferences(_dts.replaceFirst('/** 分 P 曲目所屬影片的標題', '/** 影片的標題')),
      isEmpty,
    );
  });

  test('the stat kinds match TrackStatKind', () {
    final expected = {for (final kind in TrackStatKind.values) kind.wireName};

    expect(_union(_dts, 'TrackStatKind'), expected);
    // 變異：d.ts 少一種、或多一種，比對就紅。
    expect(
      _union(_dts.replaceFirst("\n  | 'coin';", ';'), 'TrackStatKind'),
      isNot(expected),
    );
    expect(
      _union(
        _dts.replaceFirst("| 'coin';", "| 'coin' | 'tip';"),
        'TrackStatKind',
      ),
      isNot(expected),
    );
    // 無關的格式變動（多一個空白）不影響。
    expect(
      _union(_dts.replaceFirst("| 'coin';", "|   'coin';"), 'TrackStatKind'),
      expected,
    );
  });

  test('the trackDetail fields match between the d.ts and Dart', () {
    expect(_interfaces(_dts)['TrackStat']!['count'], isTrue);
    expect(sourceDtoShapes['TrackDetail']!['stats'], isFalse);
    expect(_interfaces(_dts)['TrackDetail']!['stats'], isFalse);
    // 變異：d.ts 把 TrackStat.count 改成選填，欄位表比對就紅。
    expect(
      _shapeDifferences(
        _dts.replaceFirst('  count: number;', '  count?: number;'),
      ),
      isNotEmpty,
    );
  });

  test('partCount and the part fields match between the d.ts and Dart', () {
    expect(sourceDtoShapes['TrackSummary']!['partCount'], isFalse);
    expect(_interfaces(_dts)['TrackSummary']!['partCount'], isFalse);
    expect(sourceDtoShapes['MultiPartItem']!['durationMs'], isFalse);
    expect(_interfaces(_dts)['MultiPartItem']!['index'], isTrue);
    // 變異：d.ts 把 partCount 改成必填、或少了分 P 的 index，欄位表比對就紅。
    expect(
      _shapeDifferences(
        _dts.replaceFirst('  partCount?: number', '  partCount: number'),
      ),
      isNotEmpty,
    );
    expect(
      _shapeDifferences(_dts.replaceFirst('  index: number;\n', '')),
      isNotEmpty,
    );
  });

  test('the cursor of a mix batch is optional in the d.ts and the shape', () {
    expect(sourceDtoShapes['MixBatch']!['cursor'], isFalse);
    expect(_interfaces(_dts)['MixBatch']!['cursor'], isFalse);
    // 變異：d.ts 把 cursor 改成必填，欄位表比對就紅。
    expect(
      _shapeDifferences(
        _dts.replaceFirst(
          '  cursor?: string | null;\n}',
          '  cursor: string | null;\n}',
        ),
      ),
      isNotEmpty,
    );
  });

  test('every error name maps to the AppError of that name', () {
    final names = _union(_dts, 'FmpErrorName');

    expect(names, hasLength(10));
    for (final name in names) {
      expect(
        structuredScriptError(
          pluginId: 'p',
          fmpError: name,
          reason: 'region',
        ).typeName,
        name,
      );
    }
  });

  test('the audio qualities match AudioQuality', () {
    expect(_union(_dts, 'FmpAudioQuality'), {
      for (final quality in AudioQuality.values) audioQualityWireName(quality),
    });
    // 變異：少一個值就對不上。
    expect(
      _union(_dts.replaceFirst(" | 'low'", ''), 'FmpAudioQuality'),
      isNot({
        for (final quality in AudioQuality.values)
          audioQualityWireName(quality),
      }),
    );
  });

  test('the Unavailable reasons match UnavailableReason', () {
    expect(_union(_dts, 'FmpUnavailableReason'), {
      for (final reason in UnavailableReason.values)
        unavailableReasonWireName(reason),
    });
  });
}
