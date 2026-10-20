import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'plugin_harness.dart';

// `libraryWrite` 能力（ADR 0032 §決定 4、6）：三個必要匯出、必須同時宣告 `libraryRead`、輸入的
// JSON、回傳值的驗證（`results` 與輸入同長、`status` union、`error` 只在 `failed` 且與插件拋出
// 的結構化錯誤走同一個轉換）、`requiresLogin` 與 `mutates` 都必填的案例形狀。fmp-test 的假實作由
// test_plugin_bundle_test.dart 守。

const _exports = '''
export function createPlaylist(query) { return { playlistId: 'new-' + query.title }; }
export function addToPlaylist(query) {
  return { results: query.tracks.map((t) => ({ status: 'added' })) };
}
export function removeFromPlaylist(query) {
  return { results: query.items.map((i) => ({ status: 'removed' })) };
}
''';

const _libraryRead =
    'export function libraryPlaylists() { return { playlists: [] }; }';

const _both = ['libraryRead', 'libraryWrite'];

Future<ScriptSourcePlugin> _load(
  String body, {
  List<String> capabilities = _both,
}) => PluginHarness().load(
  pluginSource(
    '$_libraryRead\n$body',
    capabilities: capabilities,
    allowedHosts: ['example.test'],
  ),
);

AddToPlaylistQuery _add([int count = 1]) => AddToPlaylistQuery(
  playlistId: 'p1',
  tracks: [for (var i = 0; i < count; i++) AddTrackRef(sourceId: 's$i')],
);

RemoveFromPlaylistQuery _remove([int count = 1]) => RemoveFromPlaylistQuery(
  playlistId: 'p1',
  items: [for (var i = 0; i < count; i++) RemoveItemRef(sourceId: 's$i')],
);

void main() {
  group('exports and capabilities', () {
    test('a libraryWrite plugin exports the three functions', () async {
      final plugin = await _load(_exports);

      expect(
        plugin.manifest.requiredExports,
        containsAll(LibraryWriteExports.all),
      );
      expect(LibraryWriteExports.all, {
        'createPlaylist',
        'addToPlaylist',
        'removeFromPlaylist',
      });
      // 能力名稱本身不是匯出。
      expect(plugin.manifest.requiredExports, isNot(contains('libraryWrite')));
    });

    for (final missing in LibraryWriteExports.all) {
      test('declaring libraryWrite without $missing is Unsupported', () {
        final others = [
          for (final name in LibraryWriteExports.all)
            if (name != missing) 'export function $name() {}',
        ];

        expect(_load(others.join('\n')), throwsA(isA<Unsupported>()));
      });
    }

    test('exporting a write function without declaring it is Unsupported', () {
      expect(
        _load(
          'export function addToPlaylist() {}',
          capabilities: ['libraryRead'],
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('libraryWrite without libraryRead is Unsupported at load', () {
      // 控制組：同樣的腳本宣告了 libraryRead 就能載入（上面第一個測試）。
      expect(
        PluginHarness().load(
          pluginSource(_exports, capabilities: ['libraryWrite']),
        ),
        throwsA(isA<Unsupported>()),
      );
    });

    test('the manifest rule is checked by the manifest alone', () {
      const body =
          '"id": "a", "name": "A", "version": "1", "author": "x", '
          '"apiVersion": 1, "allowedHosts": ["example.test"]';

      expect(
        () => PluginManifest.parse('{$body, "capabilities": ["libraryWrite"]}'),
        throwsA(isA<Unsupported>()),
      );
      expect(
        PluginManifest.parse(
          '{$body, "capabilities": ["libraryRead", "libraryWrite"]}',
        ).capabilities,
        {PluginCapability.libraryRead, PluginCapability.libraryWrite},
      );
    });

    test('calling the plugin without the capability is Unsupported', () async {
      final plugin = await _load('', capabilities: ['libraryRead']);

      await expectLater(
        plugin.addToPlaylist(_add()),
        throwsA(isA<Unsupported>()),
      );
      await expectLater(
        plugin.removeFromPlaylist(_remove()),
        throwsA(isA<Unsupported>()),
      );
      await expectLater(
        plugin.createPlaylist(CreatePlaylistQuery(title: 'x')),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('inputs reach the plugin as documented', () {
    test('createPlaylist trims the title', () async {
      final plugin = await _load(_exports);

      final result = await plugin.createPlaylist(
        CreatePlaylistQuery(title: '  Mine  '),
      );

      expect(result.playlistId, 'new-Mine');
    });

    test('an empty or blank title is rejected before the call', () {
      for (final title in ['', '   ']) {
        expect(
          () => CreatePlaylistQuery(title: title),
          throwsArgumentError,
          reason: '"$title"',
        );
      }
    });

    test('tracks and items carry only the fields that are set', () async {
      // 插件看到的輸入不對就丟 UnexpectedError（呼叫端會收到 UnexpectedError 而不是結果）。
      final plugin = await _load('''
export function createPlaylist() {}
export function addToPlaylist(query) {
  const want = '{"playlistId":"p","tracks":[{"sourceId":"a"},{"sourceId":"b","cid":3}]}';
  if (JSON.stringify(query) !== want) throw { fmpError: 'UnexpectedError', message: JSON.stringify(query) };
  return { results: query.tracks.map(() => ({ status: 'added' })) };
}
export function removeFromPlaylist(query) {
  const want = '{"playlistId":"p","items":[{"sourceId":"a"},{"sourceId":"b","cid":3,"remoteItemId":"r"}]}';
  if (JSON.stringify(query) !== want) throw { fmpError: 'UnexpectedError', message: JSON.stringify(query) };
  return { results: query.items.map(() => ({ status: 'removed' })) };
}
''');

      final added = await plugin.addToPlaylist(
        AddToPlaylistQuery(
          playlistId: 'p',
          tracks: [
            AddTrackRef(sourceId: 'a'),
            AddTrackRef(sourceId: 'b', cid: 3),
          ],
        ),
      );
      final removed = await plugin.removeFromPlaylist(
        RemoveFromPlaylistQuery(
          playlistId: 'p',
          items: [
            RemoveItemRef(sourceId: 'a'),
            RemoveItemRef(sourceId: 'b', cid: 3, remoteItemId: 'r'),
          ],
        ),
      );

      expect(added.results, hasLength(2));
      expect(removed.results, hasLength(2));
      // 變異：多給一個欄位，插件看到的輸入就不同。
      await expectLater(
        plugin.addToPlaylist(
          AddToPlaylistQuery(
            playlistId: 'p',
            tracks: [
              AddTrackRef(sourceId: 'a'),
              AddTrackRef(sourceId: 'b'),
            ],
          ),
        ),
        throwsA(isA<UnexpectedError>()),
      );
    });

    test('empty ids, empty lists and negative cids are App bugs', () {
      expect(
        () => AddToPlaylistQuery(
          playlistId: '',
          tracks: [AddTrackRef(sourceId: 'a')],
        ),
        throwsArgumentError,
      );
      expect(
        () => AddToPlaylistQuery(playlistId: 'p', tracks: const []),
        throwsArgumentError,
      );
      expect(() => AddTrackRef(sourceId: ''), throwsArgumentError);
      expect(() => AddTrackRef(sourceId: 'a', cid: -1), throwsArgumentError);
      expect(
        () => RemoveFromPlaylistQuery(playlistId: 'p', items: const []),
        throwsArgumentError,
      );
      expect(
        () => RemoveItemRef(sourceId: 'a', remoteItemId: ''),
        throwsArgumentError,
      );
    });
  });

  group('createPlaylist returned values', () {
    Future<Object> create(String result) async {
      final plugin = await _load('''
export function createPlaylist() { return $result; }
export function addToPlaylist() {}
export function removeFromPlaylist() {}
''');
      return plugin
          .createPlaylist(CreatePlaylistQuery(title: 'x'))
          .then<Object>((value) => value, onError: (Object error) => error);
    }

    test('a playlistId is accepted', () async {
      final result = await create("{ playlistId: 'p9' }");

      expect((result as CreatePlaylistResult).playlistId, 'p9');
    });

    for (final (description, result) in [
      ('an empty playlistId', "{ playlistId: '' }"),
      ('a blank playlistId', "{ playlistId: '  ' }"),
      ('a missing playlistId', '{}'),
      ('an unknown field', "{ playlistId: 'p', x: 1 }"),
      ('a number playlistId', '{ playlistId: 3 }'),
      ('undefined', 'undefined'),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await create(result), isA<ParseError>());
      });
    }
  });

  group('addToPlaylist returned values', () {
    Future<Object> add(String result, {int tracks = 1}) async {
      final plugin = await _load('''
export function createPlaylist() {}
export function addToPlaylist() { return $result; }
export function removeFromPlaylist() {}
''');
      return plugin
          .addToPlaylist(_add(tracks))
          .then<Object>((value) => value, onError: (Object error) => error);
    }

    test('every status is read, in the order of the input', () async {
      final result = await add(
        "{ results: [{ status: 'added' }, { status: 'alreadyPresent' },"
        " { status: 'failed' }] }",
        tracks: 3,
      ) as AddToPlaylistResponse;

      expect(
        [for (final r in result.results) r.status],
        [
          LibraryWriteStatus.added,
          LibraryWriteStatus.alreadyPresent,
          LibraryWriteStatus.failed,
        ],
      );
      expect(result.results.last.error, isNull);
    });

    for (final (description, result, tracks) in [
      ('fewer results than tracks', "{ results: [{ status: 'added' }] }", 2),
      (
        'more results than tracks',
        "{ results: [{ status: 'added' }, { status: 'added' }] }",
        1,
      ),
      ('no results for one track', '{ results: [] }', 1),
      ('a missing results field', '{}', 1),
      ('a status of the other call', "{ results: [{ status: 'removed' }] }", 1),
      ('notPresent', "{ results: [{ status: 'notPresent' }] }", 1),
      ('an unknown status', "{ results: [{ status: 'done' }] }", 1),
      ('a missing status', '{ results: [{}] }', 1),
      (
        'an error on an added result',
        "{ results: [{ status: 'added', error: { fmpError: 'NetworkError' } }] }",
        1,
      ),
      (
        'an error on an alreadyPresent result',
        "{ results: [{ status: 'alreadyPresent', "
            "error: { fmpError: 'NetworkError' } }] }",
        1,
      ),
      (
        'an error without fmpError',
        "{ results: [{ status: 'failed', error: { message: 'x' } }] }",
        1,
      ),
      (
        'an error with an unknown field',
        "{ results: [{ status: 'failed', error: { fmpError: 'NetworkError', x: 1 } }] }",
        1,
      ),
      (
        'a string retryAfterSeconds',
        "{ results: [{ status: 'failed', "
            "error: { fmpError: 'RateLimited', retryAfterSeconds: '5' } }] }",
        1,
      ),
      (
        'an unknown field on a result',
        "{ results: [{ status: 'added', x: 1 }] }",
        1,
      ),
      ('undefined', 'undefined', 1),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await add(result, tracks: tracks), isA<ParseError>());
      });
    }

    test('a failed result may carry no error', () async {
      final result = await add(
        "{ results: [{ status: 'failed' }] }",
      ) as AddToPlaylistResponse;

      expect(result.results.single.error, isNull);
    });
  });

  group('removeFromPlaylist returned values', () {
    Future<Object> remove(String result, {int items = 1}) async {
      final plugin = await _load('''
export function createPlaylist() {}
export function addToPlaylist() {}
export function removeFromPlaylist() { return $result; }
''');
      return plugin
          .removeFromPlaylist(_remove(items))
          .then<Object>((value) => value, onError: (Object error) => error);
    }

    test('every status is read, in the order of the input', () async {
      final result = await remove(
        "{ results: [{ status: 'removed' }, { status: 'notPresent' },"
        " { status: 'failed' }] }",
        items: 3,
      ) as RemoveFromPlaylistResponse;

      expect(
        [for (final r in result.results) r.status],
        [
          LibraryWriteStatus.removed,
          LibraryWriteStatus.notPresent,
          LibraryWriteStatus.failed,
        ],
      );
    });

    for (final (description, result, items) in [
      ('fewer results than items', "{ results: [{ status: 'removed' }] }", 2),
      ('no results', '{ results: [] }', 1),
      ('a status of the other call', "{ results: [{ status: 'added' }] }", 1),
      ('alreadyPresent', "{ results: [{ status: 'alreadyPresent' }] }", 1),
      (
        'an error on a removed result',
        "{ results: [{ status: 'removed', error: { fmpError: 'NetworkError' } }] }",
        1,
      ),
      (
        'an error on a notPresent result',
        "{ results: [{ status: 'notPresent', "
            "error: { fmpError: 'NetworkError' } }] }",
        1,
      ),
    ]) {
      test('rejects $description as ParseError', () async {
        expect(await remove(result, items: items), isA<ParseError>());
      });
    }
  });

  // 結果裡的 error 與插件拋出的結構化錯誤是同一個轉換（`structuredScriptError`）：同樣的
  // 值，兩條路徑得到同一個類別與同樣的欄位。
  group('a failed result error', () {
    Future<AppError?> resultError(String error) async {
      final plugin = await _load('''
export function createPlaylist() {}
export function addToPlaylist() {
  return { results: [{ status: 'failed', error: $error }] };
}
export function removeFromPlaylist() {}
''');
      final response = await plugin.addToPlaylist(_add());
      return response.results.single.error;
    }

    Future<AppError> thrownError(String error) async {
      final plugin = await _load('''
export function createPlaylist() {}
export function addToPlaylist() { throw $error; }
export function removeFromPlaylist() {}
''');
      try {
        await plugin.addToPlaylist(_add());
      } on AppError catch (caught) {
        return caught;
      }
      fail('expected the call to throw');
    }

    for (final error in [
      "{ fmpError: 'NetworkError' }",
      "{ fmpError: 'RateLimited', retryAfterSeconds: 5 }",
      "{ fmpError: 'Unavailable', reason: 'region' }",
      "{ fmpError: 'Unavailable' }",
      "{ fmpError: 'NotFound', message: 'gone' }",
      "{ fmpError: 'CredentialInvalid' }",
      "{ fmpError: 'NoSuchError' }",
    ]) {
      test('$error converts like a thrown error', () async {
        final inResult = await resultError(error);
        final thrown = await thrownError(error);

        expect(inResult, isNotNull);
        expect(inResult.runtimeType, thrown.runtimeType);
        expect(inResult!.retryAfter, thrown.retryAfter);
        expect(inResult.pluginId, thrown.pluginId);
        expect(
          inResult is Unavailable ? inResult.reason : null,
          thrown is Unavailable ? thrown.reason : null,
        );
      });
    }

    test('keeps the fields that matter to the user', () async {
      final rate = await resultError(
        "{ fmpError: 'RateLimited', retryAfterSeconds: 5 }",
      );
      final region = await resultError(
        "{ fmpError: 'Unavailable', reason: 'region' }",
      );

      expect(rate, isA<RateLimited>());
      expect(rate!.retryAfter, const Duration(seconds: 5));
      expect(region, isA<Unavailable>());
      expect((region! as Unavailable).reason, UnavailableReason.region);
      expect(region.pluginId, 'plugin-a');
    });

    test('an unknown name is an UnexpectedError, not a thrown error', () async {
      final error = await resultError("{ fmpError: 'NoSuchError' }");

      expect(error, isA<UnexpectedError>());
    });
  });

  group('the libraryWrite check', () {
    PluginCheck check(String body) =>
        parseChecks('{"libraryWrite": $body}').single;

    const valid =
        '{"input": {"playlistId": "p1", "tracks": [{"sourceId": "a"}, '
        '{"sourceId": "b", "cid": 2}]}, "expect": {"minItems": 2, '
        '"nonEmpty": ["status"]}, "requiresLogin": true, "mutates": true}';

    test('requires a login and mutates, and the input is the query', () {
      final parsed = check(valid);

      expect(parsed.capability, PluginCapability.libraryWrite);
      expect(parsed.requiresLogin, isTrue);
      expect(parsed.mutates, isTrue);
      final query = parsed.input as AddToPlaylistQuery;
      expect(query.playlistId, 'p1');
      expect(
        [for (final t in query.tracks) (t.sourceId, t.cid)],
        [('a', null), ('b', 2)],
      );
    });

    test('a case without requiresLogin: true is rejected', () {
      for (final extra in ['', ', "requiresLogin": false']) {
        expect(
          () => check(
            '{"input": {"playlistId": "p1", "tracks": [{"sourceId": "a"}]}, '
            '"expect": {}, "mutates": true$extra}',
          ),
          throwsFormatException,
          reason: extra,
        );
      }
    });

    test('a case without mutates: true is rejected', () {
      for (final extra in ['', ', "mutates": false']) {
        expect(
          () => check(
            '{"input": {"playlistId": "p1", "tracks": [{"sourceId": "a"}]}, '
            '"expect": {}, "requiresLogin": true$extra}',
          ),
          throwsFormatException,
          reason: extra,
        );
      }
    });

    test('a malformed input is rejected', () {
      for (final input in [
        '{"playlistId": "p1", "tracks": []}',
        '{"playlistId": "", "tracks": [{"sourceId": "a"}]}',
        '{"tracks": [{"sourceId": "a"}]}',
        '{"playlistId": "p1", "tracks": [{"sourceId": "a", "title": "x"}]}',
        '{"playlistId": "p1", "tracks": [{"sourceId": "a"}], "x": 1}',
      ]) {
        expect(
          () => check(
            '{"input": $input, "expect": {}, "requiresLogin": true, '
            '"mutates": true}',
          ),
          throwsFormatException,
          reason: input,
        );
      }
    });

    test('nonEmpty names must be AddToPlaylistResult fields', () {
      expect(
        () => check(valid.replaceFirst('"status"', '"title"')),
        throwsFormatException,
      );
    });

    test('runs addToPlaylist and checks its results', () async {
      final plugin = await _load(_exports);
      final parsed = check(valid);

      final result = await parsed.run(plugin);

      expect(result, isA<AddToPlaylistResponse>());
      expect(
        parsed.expectation.evaluate(
          result: result,
          describe: (error) => '$error',
        ),
        isEmpty,
      );
      final tooMany = check(
        valid.replaceFirst('"minItems": 2', '"minItems": 3'),
      );
      expect(
        tooMany.expectation.evaluate(
          result: result,
          describe: (error) => '$error',
        ),
        isNotEmpty,
      );
    });
  });
}
