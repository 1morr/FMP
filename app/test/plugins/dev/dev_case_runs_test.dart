import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/dev/dev_case_runs.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';
import '../contract/contract_runner.dart' show recordContract, runContract;
import '../contract/plugin_copy.dart' as contract;
import '../plugin_harness.dart';
import 'dev_support.dart';

// 開發中插件的跑案例（M3 PR 16b，design §3.1、§3.2）。不連網：真實與錄製的上游是假的。

/// 上游回給 `fmp-test-http` 的內容，含假的憑證（同 record_test.dart）。
ResponseBody _upstream(RequestOptions options) => switch (options.uri.path) {
  '/search' => reply(
    200,
    body: jsonEncode({
      'demo_session': 'FAKE_DEMO_SESSION_0001',
      'peer': '93.184.216.34',
      'list': [
        {'id': 'a1', 'name': 'Tone A', 'owner': 'FMP', 'ms': 2000},
        {'id': 'a2', 'name': 'Tone B', 'owner': 'FMP', 'ms': 3000},
      ],
      'more': false,
    }),
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': '999',
      'Set-Cookie': 'demo_session=FAKE_DEMO_SESSION_0001; Path=/',
    },
  ),
  '/stream' => reply(200, body: '{"code":403}'),
  _ => reply(404),
};

final _clock = DateTime.utc(2026, 10, 14);
DateTime _now() => _clock;

/// 插件目錄裡每個檔案的內容，鍵是相對路徑。
Map<String, List<int>> _bytes(Directory directory) => {
  for (final file in directory.listSync(recursive: true).whereType<File>())
    p.relative(file.path, from: directory.path): file.readAsBytesSync(),
};

const _loginScript = '''
export async function loginVerify(credentials) {
  const response = await fmp.http.request({
    url: 'https://example.test/me',
    headers: { Cookie: 'SESSDATA=' + credentials.cookies.SESSDATA },
    auth: 'never',
  });
  let data = {};
  try {
    data = JSON.parse(response.body).data || {};
  } catch (e) {}
  return {
    userId: '42',
    displayName: 'Tester',
    avatar: data.face ? [{ url: data.face }] : [],
  };
}
''';

const _loginChecks =
    '{"login": {"input": {"cookies": {"SESSDATA": "***"}}, '
    '"expect": {"minItems": 1, "nonEmpty": ["userId"]}, "requiresLogin": true}}';

void main() {
  late PluginHarness harness;
  late Directory root;
  late FakeHttpAdapter upstream;
  late FutureOr<ResponseBody> Function(RequestOptions) handler;

  setUp(() {
    harness = PluginHarness();
    root = tempFolder();
    handler = _upstream;
    upstream = FakeHttpAdapter((options) => handler(options));
  });

  /// 開好資料夾、載入、等到套用完成。
  Future<ProviderContainer> start() async {
    await selectFolder(harness, root);
    final container = devContainer(
      harness,
      overrides: [
        credentialStoreProvider.overrideWithValue(harness.credentials),
        caseTransportsProvider.overrideWithValue(
          CaseTransports(network: () => upstream, now: _now),
        ),
      ],
    );
    container.listen(pluginDevelopmentProvider, (_, _) {});
    container.listen(devCaseRunsProvider, (_, _) {});
    await pumpUntil(
      () => container.read(pluginDevelopmentProvider)?.busy == false,
      maxRounds: 1000,
    );
    return container;
  }

  DevCaseRuns runs(ProviderContainer container) =>
      container.read(devCaseRunsProvider.notifier);

  DevCaseResult? result(
    ProviderContainer container,
    String id,
    PluginCapability capability,
  ) => container.read(devCaseRunsProvider).results[id]?[capability];

  Directory plugin(String fixture, {bool keepFixtures = true}) {
    final directory = copyPlugin(fixturePlugin(fixture), root, fixture);
    if (!keepFixtures) {
      Directory(p.join(directory.path, 'fixtures')).deleteSync(recursive: true);
    }
    return directory;
  }

  test('the default mode is replay and fmp-test-http replays clean', () async {
    plugin('http_test_plugin');
    final container = await start();
    expect(
      container.read(devCaseRunsProvider).modeOf('fmp-test-http'),
      CaseMode.replay,
    );

    await runs(container).runAll('fmp-test-http');

    for (final capability in [
      PluginCapability.search,
      PluginCapability.resolveStream,
    ]) {
      final shown = result(container, 'fmp-test-http', capability)!;
      expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
      expect(shown.mode, CaseMode.replay);
    }
    expect(upstream.requests, isEmpty);
    expect(container.read(devCaseRunsProvider).busy, isFalse);
    final search = result(container, 'fmp-test-http', PluginCapability.search)!;
    expect(search.value, contains('Tone A'));
  });

  test('a replay mismatch fails the case with an explanation', () async {
    final directory = plugin('http_test_plugin');
    contract.edit(
      directory,
      p.join('fixtures', 'search', '001.json'),
      'keyword=tone',
      'keyword=other',
    );
    final container = await start();

    await runs(container).run('fmp-test-http', PluginCapability.search);

    final shown = result(container, 'fmp-test-http', PluginCapability.search)!;
    expect(shown.outcome, DevCaseOutcome.failed);
    expect(shown.problems, isNotEmpty);
  });

  test(
    'cases run isolated: the app storage is neither read nor written',
    () async {
      await storeInstalled(
        harness,
        scriptOf(fixturePlugin('test_plugin')).readAsStringSync(),
      );
      await harness.storage.write('fmp-test', 'titlePrefix', 'Warm');
      plugin('test_plugin');
      final container = await start();

      await runs(container).run('fmp-test', PluginCapability.search);

      final shown = result(container, 'fmp-test', PluginCapability.search)!;
      expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
      expect(shown.value, contains('Test tone'));
      expect(shown.value, isNot(contains('Warm')));
      expect(await harness.storage.read('fmp-test', 'titlePrefix'), 'Warm');
    },
  );

  test('a live case runs liveStatus and shows the room', () async {
    plugin('test_plugin');
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.live);

    final shown = result(container, 'fmp-test', PluginCapability.live)!;
    expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
    expect(shown.value, contains('Test live room'));
    expect(shown.value, contains('"status": "live"'));
  });

  test('a live case against a broken room fails, not offline', () async {
    final directory = plugin('test_plugin');
    contract.edit(
      directory,
      'checks.json',
      '"input": { "roomId": "live-ok" }',
      '"input": { "roomId": "live-broken" }',
    );
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.live);

    final shown = result(container, 'fmp-test', PluginCapability.live)!;
    expect(shown.outcome, DevCaseOutcome.failed);
    expect(shown.errorType, 'NetworkError');
  });

  test('a mix case starts a mix by seed and shows the tracks', () async {
    plugin('test_plugin');
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.mix);

    final shown = result(container, 'fmp-test', PluginCapability.mix)!;
    expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
    expect(shown.value, contains('Test mix track 1'));
    expect(shown.value, contains('Test mix track 5'));
  });

  test('a multiPart case fetches the parts and shows them', () async {
    plugin('test_plugin');
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.multiPart);

    final shown = result(container, 'fmp-test', PluginCapability.multiPart)!;
    expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
    expect(shown.value, contains('Part one'));
    expect(shown.value, contains('Part three'));
  });

  test('a multiPart case that expects too many parts fails', () async {
    final directory = plugin('test_plugin');
    contract.edit(directory, 'checks.json', '"minItems": 3', '"minItems": 4');
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.multiPart);

    final shown = result(container, 'fmp-test', PluginCapability.multiPart)!;
    expect(shown.outcome, DevCaseOutcome.failed);
    expect(shown.problems.join(), contains('expected at least 4 items'));
  });

  test('a trackDetail case fetches the detail and shows it', () async {
    plugin('test_plugin');
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.trackDetail);

    final shown = result(container, 'fmp-test', PluginCapability.trackDetail)!;
    expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
    expect(shown.value, contains('Test album'));
  });

  test('a trackDetail case whose detail lacks a field fails', () async {
    final directory = plugin('test_plugin');
    contract.edit(
      directory,
      'test_plugin.js',
      "    album: 'Test album',\n",
      '',
    );
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.trackDetail);

    final shown = result(container, 'fmp-test', PluginCapability.trackDetail)!;
    expect(shown.outcome, DevCaseOutcome.failed);
    expect(shown.problems.join(), contains('"album" is empty'));
  });

  test('a mix case that expects too many tracks fails', () async {
    final directory = plugin('test_plugin');
    contract.edit(directory, 'checks.json', '"minItems": 5', '"minItems": 6');
    final container = await start();

    await runs(container).run('fmp-test', PluginCapability.mix);

    final shown = result(container, 'fmp-test', PluginCapability.mix)!;
    expect(shown.outcome, DevCaseOutcome.failed);
    expect(shown.problems.join(), contains('expected at least 6 items'));
  });

  group('record', () {
    Future<ProviderContainer> recording() async {
      plugin('http_test_plugin', keepFixtures: false);
      final container = await start();
      runs(container).setMode('fmp-test-http', CaseMode.record);
      return container;
    }

    test('writes redacted fixtures that replay and match the command line '
        'byte for byte', () async {
      final container = await recording();

      await runs(container).runAll('fmp-test-http');

      final search = result(
        container,
        'fmp-test-http',
        PluginCapability.search,
      )!;
      expect(
        search.outcome,
        DevCaseOutcome.passed,
        reason: '${search.problems}',
      );
      expect(search.written, 1);
      final directory = Directory(p.join(root.path, 'http_test_plugin'));
      final fixtures = Directory(p.join(directory.path, 'fixtures'));
      final files = fixtures.listSync(recursive: true).whereType<File>();
      expect(files, hasLength(2));
      for (final file in files) {
        expect(file.readAsStringSync(), isNot(contains('FAKE_')));
        expect(file.readAsStringSync(), isNot(contains('93.184.216.34')));
      }
      // 插件送出的是真的值，寫進檔案的是遮過的。
      expect(
        upstream.requests.first.uri.queryParameters['access_key'],
        'FAKE_ACCESS_KEY_0001',
      );
      // 重播通過。
      expect(await runContract(directory), isEmpty);

      // 命令列錄製：同一個假上游與時鐘，寫出的目錄逐位元組相同。
      final cli = contract.copyPlugin('http_test_plugin');
      Directory(p.join(cli.path, 'fixtures')).deleteSync(recursive: true);
      final recorded = await recordContract(
        cli,
        network: () => FakeHttpAdapter(_upstream),
        now: _now,
      );
      expect(recorded.problems, isEmpty);
      expect(_bytes(fixtures), _bytes(Directory(p.join(cli.path, 'fixtures'))));
    });

    test('leaves hand-edited fixtures alone and sends nothing', () async {
      plugin('http_test_plugin');
      final container = await start();
      runs(container).setMode('fmp-test-http', CaseMode.record);
      final before = _bytes(Directory(p.join(root.path, 'http_test_plugin')));

      await runs(container).run('fmp-test-http', PluginCapability.search);

      final shown = result(
        container,
        'fmp-test-http',
        PluginCapability.search,
      )!;
      expect(shown.outcome, DevCaseOutcome.skipped);
      expect(shown.skip, DevSkip.handEdited);
      expect(upstream.requests, isEmpty);
      expect(_bytes(Directory(p.join(root.path, 'http_test_plugin'))), before);
    });

    test('writes nothing when the outcome misses checks.json', () async {
      final container = await recording();
      handler = (_) => reply(404);

      await runs(container).run('fmp-test-http', PluginCapability.search);

      final shown = result(
        container,
        'fmp-test-http',
        PluginCapability.search,
      )!;
      expect(shown.outcome, DevCaseOutcome.failed);
      expect(shown.notWritten, isTrue);
      expect(shown.written, isNull);
      expect(
        Directory(p.join(root.path, 'http_test_plugin', 'fixtures'))
            .existsSync(),
        isFalse,
      );
    });

    for (final unload in [false, true]) {
      test('${unload ? 'unloading' : 'a folder change'} while recording drops '
          'the result and the write', () async {
        final container = await recording();
        final release = Completer<void>();
        handler = (options) async {
          await release.future;
          return _upstream(options);
        };

        final running = runs(container)
            .run('fmp-test-http', PluginCapability.search);
        await pumpUntil(() => upstream.requests.isNotEmpty, maxRounds: 1000);
        expect(container.read(devCaseRunsProvider).busy, isTrue);
        final other = unload ? null : tempFolder();
        await selectFolder(harness, other);
        await pumpUntil(
          () =>
              container.read(pluginDevelopmentProvider)?.folder.path ==
              other?.path,
          maxRounds: 1000,
        );
        release.complete();
        await running;

        expect(container.read(devCaseRunsProvider).results, isEmpty);
        expect(container.read(devCaseRunsProvider).busy, isFalse);
        expect(
          Directory(p.join(root.path, 'http_test_plugin', 'fixtures'))
              .existsSync(),
          isFalse,
        );
      });
    }
  });

  group('requiresLogin', () {
    /// [keyNames]：manifest 的 `redaction.keyNames`。
    Directory loginPlugin({List<String> keyNames = const []}) {
      final directory = Directory(p.join(root.path, 'login-plugin'))
        ..createSync();
      final source = pluginSource(
        _loginScript,
        id: 'login-plugin',
        capabilities: ['login'],
        login: '{"methods": ["cookie"]}',
      );
      File(p.join(directory.path, 'login-plugin.js')).writeAsStringSync(
        keyNames.isEmpty
            ? source
            : source.replaceFirst(
                '"allowedHosts"',
                '"redaction": {"keyNames": ${jsonEncode(keyNames)}}, '
                    '"allowedHosts"',
              ),
      );
      File(p.join(directory.path, 'checks.json'))
          .writeAsStringSync(_loginChecks);
      return directory;
    }

    Future<void> logIn() async {
      await harness.credentials.ready;
      await harness.credentials.save(
        Account(
          pluginId: 'login-plugin',
          userId: '42',
          displayName: 'Tester',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 14),
        ),
        const LoginCredentials(cookies: {'SESSDATA': 'FAKE_STORED_SESSION'}),
      );
    }

    for (final mode in [CaseMode.real, CaseMode.record]) {
      test('is skipped in ${mode.name} mode when not logged in, sending '
          'nothing', () async {
        loginPlugin();
        final container = await start();
        runs(container).setMode('login-plugin', mode);

        await runs(container).run('login-plugin', PluginCapability.login);

        final shown = result(
          container,
          'login-plugin',
          PluginCapability.login,
        )!;
        expect(shown.outcome, DevCaseOutcome.skipped);
        expect(shown.skip, DevSkip.requiresLogin);
        expect(upstream.requests, isEmpty);
      });
    }

    test('real mode hands the stored credentials to loginVerify and never '
        'shows the account', () async {
      loginPlugin();
      await logIn();
      final container = await start();
      runs(container).setMode('login-plugin', CaseMode.real);

      await runs(container).run('login-plugin', PluginCapability.login);

      final shown = result(container, 'login-plugin', PluginCapability.login)!;
      expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
      expect(
        upstream.requests.single.headers['Cookie'],
        contains('FAKE_STORED_SESSION'),
      );
      final everything = [
        shown.value,
        ...shown.problems,
        for (final record in harness.log.history) record.toJsonLine(),
      ].join(' | ');
      expect(everything, isNot(contains('Tester')));
      expect(everything, isNot(contains('FAKE_STORED_SESSION')));
      expect(shown.value, contains('***'));
    });

    group('record mode with the stored credentials', () {
      /// 上游的帳號資訊回應：名稱、uid、頭像都是假的帳號。
      ResponseBody me(RequestOptions options) => reply(
        200,
        body: jsonEncode({
          'code': 0,
          'data': {
            'uname': 'Tester',
            'mid': 42,
            'face': 'https://example.test/face/tester.jpg',
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );

      Directory fixtures() =>
          Directory(p.join(root.path, 'login-plugin', 'fixtures'));

      test(
        'scrubs the account and writes fixtures that still replay',
        () async {
          loginPlugin();
          await logIn();
          handler = me;
          final container = await start();
          runs(container).setMode('login-plugin', CaseMode.record);

          await runs(container).run('login-plugin', PluginCapability.login);

          final shown = result(
            container,
            'login-plugin',
            PluginCapability.login,
          )!;
          expect(
            shown.outcome,
            DevCaseOutcome.passed,
            reason: '${shown.problems}',
          );
          expect(shown.written, 1);
          final written = fixtures()
              .listSync(recursive: true)
              .whereType<File>()
              .single
              .readAsStringSync();
          expect(written, isNot(contains('Tester')));
          expect(written, isNot(contains('tester.jpg')));
          expect(written, isNot(contains('FAKE_STORED_SESSION')));
          final body = (jsonDecode(written) as Map)['response'] as Map;
          final data = (body['jsonBody'] as Map)['data'] as Map;
          expect(data['uname'], '***');
          expect(data['mid'], '***');
          expect(data['face'], 'https://example.test/***');
          // 換過的 fixture 重播仍過：頭像的主機還在，nonEmpty 成立。
          expect(
            await runContract(Directory(p.join(root.path, 'login-plugin'))),
            isEmpty,
          );
        },
      );
    });

    test('replay mode uses the fake credentials of checks.json', () async {
      plugin('test_plugin');
      final container = await start();

      await runs(container).run('fmp-test', PluginCapability.login);

      final shown = result(container, 'fmp-test', PluginCapability.login)!;
      expect(shown.outcome, DevCaseOutcome.passed, reason: '${shown.problems}');
      expect(shown.mode, CaseMode.replay);
    });
  });

  test('only one case runs at a time', () async {
    plugin('http_test_plugin');
    final container = await start();
    runs(container).setMode('fmp-test-http', CaseMode.real);
    final release = Completer<void>();
    handler = (options) async {
      await release.future;
      return _upstream(options);
    };

    final first = runs(container).run('fmp-test-http', PluginCapability.search);
    await pumpUntil(() => upstream.requests.isNotEmpty, maxRounds: 1000);
    // 同一個插件在跑時，模式不能換。
    runs(container).setMode('fmp-test-http', CaseMode.replay);
    expect(
      container.read(devCaseRunsProvider).modeOf('fmp-test-http'),
      CaseMode.real,
    );
    await runs(container).run('fmp-test-http', PluginCapability.resolveStream);
    await runs(container).runAll('fmp-test-http');
    expect(upstream.requests, hasLength(1));
    release.complete();
    await first;

    expect(container.read(devCaseRunsProvider).results['fmp-test-http']!.keys, [
      PluginCapability.search,
    ]);
  });

  test('every case writes one log record tagged with the plugin id', () async {
    plugin('http_test_plugin');
    final container = await start();

    await runs(container).runAll('fmp-test-http');

    final records = harness.log.history
        .where(
          (record) =>
              record.tag == 'fmp-test-http' && record.message == 'Plugin case',
        )
        .toList();
    expect(records.map((record) => record.fields['capability']), [
      'search',
      'resolveStream',
    ]);
    for (final record in records) {
      expect(record.level, LogLevel.info);
      expect(record.fields['mode'], 'replay');
      expect(record.fields['result'], 'passed');
      expect(record.fields['durationMs'], isA<int>());
    }
  });
}
