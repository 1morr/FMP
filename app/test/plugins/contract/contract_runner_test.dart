import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:path/path.dart' as p;

import 'contract_runner.dart';
import 'credential_scan.dart';
import 'plugin_copy.dart';

// 契約執行器自己的測試：每一種違反都造一個讓它紅，也改一個無關處證明它不會
// 誤紅（雙向變異）。變異都在 test/fixtures/plugins/ 的副本上做。

const _script = 'http_test_plugin.js';
const _checks = 'checks.json';
final _searchFixture = p.join('fixtures', 'search', '001.json');
final _streamFixture = p.join('fixtures', 'resolveStream', '001.json');

/// 讓 `fmp-test-http` 的 resolveStream 成功（原本是錯誤案例）。
void resolveStreamSucceeds(Directory directory) {
  edit(
    directory,
    _streamFixture,
    '"jsonBody": { "code": 403 }',
    '"jsonBody": { "code": 0, "url": "https://media.fmp.test/a1.m4a" }',
  );
  edit(
    directory,
    _checks,
    '"expect": { "error": "Unavailable", "reason": "copyright" }',
    '"expect": { "minItems": 1, "nonEmpty": ["url", "headers"] }',
  );
}

/// 讓 `fmp-test-http` 的 resolveStream 成功，網址帶期限參數 `expires`（unix
/// 秒），候選的 `expiresAt` 取自回應的 [expiresAt]（毫秒；`null` 就不給），
/// checks.json 以 `expiresAtPattern` 核對兩者。
void expiringStream(Directory directory, {required int? expiresAt}) {
  resolveStreamSucceeds(directory);
  edit(
    directory,
    _script,
    "codec: 'aac',",
    "codec: 'aac', expiresAt: json.expiresAt ?? null,",
  );
  edit(
    directory,
    _streamFixture,
    '"url": "https://media.fmp.test/a1.m4a" }',
    '"url": "https://media.fmp.test/a1.m4a?expires=1790000000"'
        '${expiresAt == null ? '' : ', "expiresAt": $expiresAt'} }',
  );
  edit(
    directory,
    _checks,
    '"nonEmpty": ["url", "headers"] }',
    r'"nonEmpty": ["url", "headers"] }, "expiresAtPattern": "[?&]expires=(\\d+)"',
  );
}

/// 讓 `fmp-test-http` 的 search 把一個假的 demo_session 寫進 log 的欄位
/// （manifest 追加的遮蔽鍵名）。
void logDemoSession(Directory directory) {
  edit(
    directory,
    _script,
    'demo_session: json.demo_session,',
    "demo_session: 'FAKE_DEMO_SESSION_0001',",
  );
}

void main() {
  group('stays green', () {
    test('on both test plugins', () async {
      expect(await runContract(copyPlugin('http_test_plugin')), isEmpty);
      expect(await runContract(copyPlugin('test_plugin')), isEmpty);
    });

    test('when the install file is renamed', () async {
      final directory = copyPlugin('http_test_plugin');
      File(p.join(directory.path, _script))
          .renameSync(p.join(directory.path, 'plugin.js'));

      expect(await runContract(directory), isEmpty);
    });

    test('when checks.json and fixtures are reformatted', () async {
      final directory = copyPlugin('http_test_plugin');
      for (final relative in [_checks, _searchFixture, _streamFixture]) {
        final file = File(p.join(directory.path, relative));
        final json = jsonDecode(file.readAsStringSync());
        file.writeAsStringSync(
          const JsonEncoder.withIndent('\t').convert(json),
        );
      }

      expect(await runContract(directory), isEmpty);
    });

    test('when the fixture lists the query in another order', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _searchFixture,
        '?access_key=***&keyword=tone&page=1',
        '?page=1&access_key=***&keyword=tone',
      );

      expect(await runContract(directory), isEmpty);
    });

    test('when request headers in a fixture change (not matched)', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _searchFixture,
        '"referer": "https://www.fmp.test/"',
        '"referer": "https://other.fmp.test/", "x-trace": "1"',
      );

      expect(await runContract(directory), isEmpty);
    });

    test('when the plugin logs a credential the log facade redacts', () async {
      final directory = copyPlugin('http_test_plugin');
      logDemoSession(directory);

      expect(await runContract(directory), isEmpty);
    });

    test('when stream headers hold only media headers', () async {
      final directory = copyPlugin('http_test_plugin');
      resolveStreamSucceeds(directory);

      expect(await runContract(directory), isEmpty);
    });

    test('when expiresAt agrees with the expiry in the URL', () async {
      final directory = copyPlugin('http_test_plugin');
      expiringStream(directory, expiresAt: 1790000000000);

      expect(await runContract(directory), isEmpty);
    });

    test('when an unrelated part of the stream URL changes', () async {
      final directory = copyPlugin('http_test_plugin');
      expiringStream(directory, expiresAt: 1790000000000);
      edit(directory, _streamFixture, '/a1.m4a?', '/b2.m4a?x=1&');

      expect(await runContract(directory), isEmpty);
    });
  });

  group('turns red on', () {
    test('a request to a host outside allowedHosts', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _script,
        "const API = 'https://api.fmp.test';",
        "const API = 'https://api.evil.test';",
      );

      final problems = await runContract(directory);

      expect(
        problems,
        contains(
          startsWith('search: tried to reach a host outside allowedHosts'),
        ),
      );
    });

    test('a fixture on a host outside allowedHosts', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _searchFixture,
        'https://api.fmp.test/',
        'https://api.evil.test/',
      );

      expect(
        await runContract(directory),
        contains(contains('api.evil.test is outside allowedHosts')),
      );
    });

    test('a request that matches no fixture', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(directory, _searchFixture, '/search?', '/find?');

      expect(
        await runContract(directory),
        contains(
          allOf(startsWith('search: request #1'), contains('does not match')),
        ),
      );
    });

    test('a request after the fixtures ran out', () async {
      final directory = copyPlugin('http_test_plugin');
      File(p.join(directory.path, _streamFixture)).deleteSync();

      expect(
        await runContract(directory),
        contains(
          allOf(
            startsWith('resolveStream: request #1'),
            contains('no fixture'),
          ),
        ),
      );
    });

    test('a fixture that is never requested', () async {
      final directory = copyPlugin('http_test_plugin');
      File(p.join(directory.path, _searchFixture))
          .copySync(p.join(directory.path, 'fixtures', 'search', '002.json'));

      expect(
        await runContract(directory),
        contains('search: fixtures/search/002.json was not requested'),
      );
    });

    test('fixtures for a capability without a check', () async {
      final directory = copyPlugin('http_test_plugin');
      Directory(p.join(directory.path, 'fixtures', 'charts')).createSync();

      expect(
        await runContract(directory),
        contains('fixtures/charts: checks.json has no charts check'),
      );
    });

    test('too few items', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(directory, _checks, '"minItems": 2', '"minItems": 5');

      expect(
        await runContract(directory),
        contains('search: expected at least 5 items, got 2'),
      );
    });

    test('an empty field', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(directory, _searchFixture, '"owner": "FMP"', '"owner": " "');

      expect(
        await runContract(directory),
        contains('search: item 0: "uploader" is empty'),
      );
    });

    test('another error than expected', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(directory, _checks, '"reason": "copyright"', '"reason": "region"');

      expect(
        await runContract(directory),
        contains(
          startsWith(
            'resolveStream: expected Unavailable (region), got '
            'Unavailable',
          ),
        ),
      );
    });

    test('success where an error is expected', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _streamFixture,
        '"jsonBody": { "code": 403 }',
        '"jsonBody": { "code": 0, "url": "https://media.fmp.test/a1.m4a" }',
      );

      expect(
        await runContract(directory),
        contains(
          'resolveStream: expected Unavailable (copyright), but the call '
          'succeeded',
        ),
      );
    });

    test('an expiresAt that disagrees with the URL', () async {
      final directory = copyPlugin('http_test_plugin');
      expiringStream(directory, expiresAt: 1790000001000);

      expect(
        await runContract(directory),
        contains(
          'resolveStream: candidate 0: expiresAt is 2026-09-21 '
          '14:13:21.000Z, the URL says 2026-09-21 14:13:20.000Z',
        ),
      );
    });

    test('a missing expiresAt where the URL has one', () async {
      final directory = copyPlugin('http_test_plugin');
      expiringStream(directory, expiresAt: null);

      expect(
        await runContract(directory),
        contains(
          'resolveStream: candidate 0: expiresAt is null, the URL says '
          '2026-09-21 14:13:20.000Z',
        ),
      );
    });

    test('an expiresAtPattern that no URL matches', () async {
      // 例如 fixture 裡的期限參數被遮掉了：檢查什麼也沒核對到，不能算過。
      final directory = copyPlugin('http_test_plugin');
      expiringStream(directory, expiresAt: 1790000000000);
      edit(directory, _streamFixture, '?expires=1790000000', '');

      expect(
        await runContract(directory),
        contains('resolveStream: expiresAtPattern matched no candidate URL'),
      );
    });

    test('a return value that fails DTO validation', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(directory, _searchFixture, '"name": "Tone A"', '"name": 5');

      expect(
        await runContract(directory),
        contains(
          allOf(
            startsWith('search: expected success, got ParseError'),
            contains('SearchPage.items[0].title'),
          ),
        ),
      );
    });

    test('a declared capability that is not exported', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _script,
        '"capabilities": ["search", "resolveStream"]',
        '"capabilities": ["search", "resolveStream", "charts"]',
      );

      expect(
        await runContract(directory),
        contains(
          allOf(
            startsWith('load: Unsupported'),
            contains('declared but not exported: charts'),
          ),
        ),
      );
    });

    test('an exported capability that is not declared', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _script,
        'export async function resolveStream',
        'export function charts() {}\nexport async function resolveStream',
      );

      expect(
        await runContract(directory),
        contains(contains('exported but not declared: charts')),
      );
    });

    test('a check for an undeclared capability', () async {
      final directory = copyPlugin('test_plugin');
      edit(
        directory,
        'test_plugin.js',
        '"capabilities": ["search", "resolveStream", "login"]',
        '"capabilities": ["search", "login"]',
      );

      expect(
        await runContract(directory),
        contains('checks.json: resolveStream is not a declared capability'),
      );
    });

    test('an unknown field in checks.json', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(directory, _checks, '"minItems": 2', '"minItems": 2, "maxItems": 3');

      expect(
        await runContract(directory),
        contains('checks.json: checks.search.expect: unknown field "maxItems"'),
      );
    });

    test('a missing checks.json', () async {
      final directory = copyPlugin('http_test_plugin');
      File(p.join(directory.path, _checks)).deleteSync();

      expect(await runContract(directory), contains('checks.json is missing'));
    });

    test('a fixture with an unredacted credential', () async {
      final directory = copyPlugin('http_test_plugin');
      edit(
        directory,
        _searchFixture,
        'access_key=***',
        'access_key=FAKE_ACCESS_KEY_0001',
      );

      expect(
        await runContract(directory),
        contains(
          'fixtures/search/001.json: request.url has an unredacted '
          '"access_key"',
        ),
      );
    });

    test('a plugin log that skipped redaction', () async {
      // 案例的 log 沒接上插件追加的遮蔽名單（demo_session）：插件寫進 log 的
      // 值沒遮，執行器要從插件實際寫的 log 看出來。
      final directory = copyPlugin('http_test_plugin');
      logDemoSession(directory);
      final plugin = PluginDirectory.read(directory);
      final search = plugin.checks.firstWhere(
        (check) => check.capability == PluginCapability.search,
      );

      expect(
        await runCheck(
          plugin,
          search,
          log: (_) => Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
        ),
        contains(
          allOf(
            startsWith('search: log record'),
            contains('fields.demo_session is not redacted'),
          ),
        ),
      );
    });

    test('stream headers that carry a credential', () async {
      final directory = copyPlugin('http_test_plugin');
      resolveStreamSucceeds(directory);
      edit(
        directory,
        _script,
        'headers: { Referer: REFERER },',
        "headers: { Cookie: 'SESSDATA=FAKE_SESSDATA_0001' },",
      );

      expect(
        await runContract(directory),
        contains(
          startsWith(
            'resolveStream: candidate #1: header "Cookie" carries a '
            'credential',
          ),
        ),
      );
    });
  });

  group('the log inspection', () {
    final names = CredentialNames();
    LogRecord record(
      String message, {
      Map<String, Object?> fields = const {},
    }) => LogRecord(
      time: DateTime.utc(2026, 9, 30),
      level: LogLevel.info,
      tag: 'fmp-test-http',
      message: message,
      fields: fields,
    );

    test('reports a record that skipped redaction', () {
      final problems = inspectLog(
        [
          record(
            'search https://api.fmp.test/search?access_key=FAKE_ACCESS_KEY_0001',
          ),
          record('ok', fields: {'token': 'FAKE_TOKEN_0001'}),
        ],
        Redactor(),
        names,
      );

      expect(problems, [
        'log record #1 (fmp-test-http): message changes when redacted again',
        'log record #1 (fmp-test-http): message has an unredacted "access_key"',
        'log record #2 (fmp-test-http): fields change when redacted again',
        'log record #2 (fmp-test-http): fields.token is not redacted',
      ]);
    });

    test('passes what the log facade wrote', () {
      final redactor = Redactor();
      final log = Log(redactor: redactor, minimumLevel: LogLevel.debug)
        ..info(
          'search https://api.fmp.test/search?access_key=FAKE_ACCESS_KEY_0001',
          tag: 'fmp-test-http',
          fields: {'token': 'FAKE_TOKEN_0001'},
        )
        ..info('{"token":["FAKE_TOKEN_0001"]}', tag: 'fmp-test-http');

      expect(inspectLog(log.history, redactor, names), isEmpty);
    });

    test('passes look-alike names that are not credentials', () {
      expect(
        inspectLog(
          [
            record('no token found', fields: {'tokens_used': 3, 'bvid': 'BV1'}),
          ],
          Redactor(),
          names,
        ),
        isEmpty,
      );
    });
  });
}
