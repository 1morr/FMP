import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_http_adapter.dart';
import 'contract_runner.dart';
import 'plugin_copy.dart';

// 錄製模式（prd 擁有者決定 8）。會真的連網的只有最後一個 `live` 測試：
// dart_test.yaml 讓它預設跳過，要錄時明確解除（app/AGENTS.md § 驗證）。其他
// 測試用假的 adapter 代替網路。

/// 上游回給 `fmp-test-http` 的內容，含假的憑證。
ResponseBody _upstream(RequestOptions options) => switch (options.uri.path) {
  '/search' => reply(
    200,
    body: jsonEncode({
      'demo_session': 'FAKE_DEMO_SESSION_0001',
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

final _searchFixture = p.join('fixtures', 'search', '001.json');

/// 插件目錄裡每個檔案的內容，鍵是相對路徑。
Map<String, List<int>> _bytes(Directory directory) => {
  for (final file in directory.listSync(recursive: true).whereType<File>())
    p.relative(file.path, from: directory.path): file.readAsBytesSync(),
};

Map<String, Object?> _read(Directory directory, String capability) =>
    jsonDecode(
      File(p.join(directory.path, 'fixtures', capability, '001.json'))
          .readAsStringSync(),
    ) as Map<String, Object?>;

void main() {
  test('records redacted fixtures that replay', () async {
    final directory = copyPlugin('http_test_plugin');
    Directory(p.join(directory.path, 'fixtures')).deleteSync(recursive: true);
    final upstream = FakeHttpAdapter(_upstream);

    final recording = await recordContract(
      directory,
      network: () => upstream,
      now: () => DateTime.utc(2026, 9, 30),
    );

    expect(recording.problems, isEmpty);
    expect(recording.skipped, isEmpty);
    // 插件送出的是真的值；寫進檔案的是遮過的。
    expect(
      upstream.requests.first.uri.queryParameters['access_key'],
      'FAKE_ACCESS_KEY_0001',
    );
    final files = Directory(p.join(directory.path, 'fixtures'))
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(files, hasLength(2));
    for (final file in files) {
      expect(file.readAsStringSync(), isNot(contains('FAKE_')));
    }
    final search = _read(directory, 'search');
    expect(search['meta'], {'recordedAt': '2026-09-30T00:00:00.000Z'});
    expect(
      (search['request']! as Map)['url'],
      'https://api.fmp.test/search?page=1&keyword=tone&access_key=***',
    );
    final response = search['response']! as Map;
    expect(response['headers'], {
      'content-type': ['application/json'],
      'set-cookie': ['demo_session=***; Path=/'],
    });
    expect((response['jsonBody']! as Map)['demo_session'], '***');
    expect(
      (_read(directory, 'resolveStream')['response']! as Map)['jsonBody'],
      {'code': 403},
    );

    expect(await runContract(directory), isEmpty);
  });

  test('leaves hand-edited fixtures alone', () async {
    final directory = copyPlugin('http_test_plugin');
    final before = _read(directory, 'search');
    final upstream = FakeHttpAdapter(_upstream);

    final recording = await recordContract(directory, network: () => upstream);

    expect(recording.skipped, [
      'search: has hand-edited fixtures',
      'resolveStream: has hand-edited fixtures',
    ]);
    expect(upstream.requests, isEmpty);
    expect(_read(directory, 'search'), before);
  });

  test('writes nothing for a case whose outcome misses the check', () async {
    // 連線失敗：案例以 NetworkError 結束，不是 checks.json 期望的成功。原本的
    // fixture 一個位元組都不動。
    final directory = copyPlugin('http_test_plugin');
    edit(
      directory,
      _searchFixture,
      '"edited": "手寫的合成資料，不是錄的"',
      '"recordedAt": "2026-09-01T00:00:00.000Z"',
    );
    final before = _bytes(directory);

    final recording = await recordContract(
      directory,
      network: () => FakeHttpAdapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ),
      ),
      wait: (_) async {},
    );

    expect(
      recording.problems,
      containsAll([
        startsWith('search: expected success, got NetworkError'),
        'search: fixtures not written: the outcome does not match '
            'checks.json',
      ]),
    );
    expect(_bytes(directory), before);
  });

  test('records the final exchange of a request retried to success', () async {
    // 第一次送出連線失敗、網路層重試後成功：失敗的那次沒有回應，不寫；寫下
    // 的一組重播得了。
    final directory = copyPlugin('http_test_plugin');
    Directory(p.join(directory.path, 'fixtures')).deleteSync(recursive: true);
    var failed = false;
    final upstream = FakeHttpAdapter((options) {
      if (!failed) {
        failed = true;
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'reset',
        );
      }
      return _upstream(options);
    });

    final recording = await recordContract(
      directory,
      network: () => upstream,
      wait: (_) async {},
    );

    expect(recording.problems, isEmpty);
    expect(
      upstream.requests.where((r) => r.uri.path == '/search'),
      hasLength(2),
    );
    expect(
      Directory(p.join(directory.path, 'fixtures', 'search')).listSync(),
      hasLength(1),
    );
    expect(await runContract(directory), isEmpty);
  });

  test('does not record a body that is not UTF-8', () async {
    final directory = copyPlugin('http_test_plugin');
    Directory(p.join(directory.path, 'fixtures')).deleteSync(recursive: true);

    final recording = await recordContract(
      directory,
      network: () => FakeHttpAdapter(
        (_) => ResponseBody.fromBytes([0xff, 0xfe, 0x00], 200),
      ),
    );

    expect(
      recording.problems,
      contains(contains('returned a body that is not UTF-8')),
    );
    expect(Directory(p.join(directory.path, 'fixtures')).existsSync(), isFalse);
  });

  test('sends real requests from the zone it runs in', () async {
    // 下面的 live 測試靠呼叫端 zone 的 HttpOverrides 放行真實連線。這裡換成一個
    // 只計數、不連網的 HttpOverrides：它被用到，代表插件的請求（從背景 isolate
    // 轉回主 isolate）確實在那個 zone 裡建立 HttpClient。
    final directory = copyPlugin('http_test_plugin');
    Directory(p.join(directory.path, 'fixtures')).deleteSync(recursive: true);
    final overrides = _CountingOverrides();

    await HttpOverrides.runWithHttpOverrides(
      () => recordContract(directory, network: IOHttpClientAdapter.new),
      overrides,
    );

    expect(overrides.created, greaterThan(0));
  });

  // 真的連網錄製。只有 `flutter test --run-skipped --tags live` 會跑；插件目錄
  // 由 FMP_PLUGIN_DIR 指定（一個插件目錄，或底下的每個插件目錄）。
  test('records FMP_PLUGIN_DIR from the real network', () async {
    final root = pluginDirectoryFromEnvironment();
    expect(root, isNotNull, reason: 'set FMP_PLUGIN_DIR to a plugin directory');
    final directories = pluginDirectories(root!);
    expect(directories, isNotEmpty, reason: noPluginDirectories(root));
    for (final directory in directories) {
      final recording = await HttpOverrides.runWithHttpOverrides(
        () => recordContract(directory, network: IOHttpClientAdapter.new),
        _AllowNetwork(),
      );
      for (final skipped in recording.skipped) {
        stdout.writeln('${directory.path}: skipped $skipped');
      }
      expect(recording.problems, isEmpty, reason: directory.path);
      expect(await runContract(directory), isEmpty, reason: directory.path);
    }
  }, tags: 'live');
}

/// 放行真實連線（只在錄製的 zone 內）。
final class _AllowNetwork extends HttpOverrides {}

/// 建立 HttpClient 時計數並拋錯，不連網。
final class _CountingOverrides extends HttpOverrides {
  int created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('HttpClient requested from the recording zone');
  }
}
