import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/host_fetch.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/redaction/redactor.dart';

import '../../support/fake_http_adapter.dart';

void main() {
  late FakeHttpAdapter adapter;
  late Log log;
  late HostFetch fetch;

  void setUpFetch(ResponseBody Function(RequestOptions options) handler) {
    adapter = FakeHttpAdapter(handler);
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    fetch = HostFetch(log: log, createAdapter: () => adapter);
  }

  List<LogRecord> records() => [
    for (final record in log.history)
      if (record.tag == networkLogTag) record,
  ];

  Future<String> read(String url, {int maxBytes = 1024}) async =>
      utf8.decode(await fetch.fetch(Uri.parse(url), maxBytes: maxBytes));

  test('returns the body', () async {
    setUpFetch((_) => reply(200, body: '{"indexVersion":1}'));

    expect(
      await read('https://raw.example.test/index.json'),
      '{"indexVersion":1}',
    );
  });

  test(
    'carries no credentials: no Cookie, no Authorization, no user info',
    () async {
      setUpFetch((_) => reply(200, body: 'x'));

      await read('https://raw.example.test/index.json');

      final headers = adapter.requests.single.headers;
      expect(
        headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      await expectLater(
        read('https://user:pass@raw.example.test/index.json'),
        throwsA(isA<Unsupported>()),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test('only https is allowed', () async {
    setUpFetch((_) => reply(200, body: 'x'));

    await expectLater(
      read('http://raw.example.test/index.json'),
      throwsA(isA<Unsupported>()),
    );
    await expectLater(read('file:///etc/hosts'), throwsA(isA<Unsupported>()));
    expect(adapter.requests, isEmpty);
  });

  test('a redirect inside the same host is followed', () async {
    setUpFetch(
      (options) =>
          options.uri.path == '/a' ? redirect('/b') : reply(200, body: 'moved'),
    );

    expect(await read('https://raw.example.test/a'), 'moved');
  });

  test(
    'a redirect to another host or a subdomain fails without a request',
    () async {
      for (final target in [
        'https://other.example/b',
        'https://sub.raw.example.test/b',
        'http://raw.example.test/b',
      ]) {
        setUpFetch((_) => redirect(target));

        await expectLater(
          read('https://raw.example.test/a'),
          throwsA(isA<Unsupported>()),
          reason: target,
        );
        expect(adapter.requests, hasLength(1), reason: target);
      }
    },
  );

  test('a body over the size limit is refused', () async {
    setUpFetch((_) => reply(200, body: 'x' * 2000));

    await expectLater(
      read('https://raw.example.test/big'),
      throwsA(isA<Unsupported>()),
    );
  });

  test('leaves no temporary directory behind', () async {
    setUpFetch((_) => reply(200, body: 'x'));
    int count() => Directory.systemTemp
        .listSync()
        .where((e) => e.path.contains('fmp_host_fetch'))
        .length;
    final before = count();

    await read('https://raw.example.test/a');
    await expectLater(
      read('https://raw.example.test/a', maxBytes: 0),
      throwsA(isA<AppError>()),
    );

    expect(count(), before);
  });

  test('writes a network record with client host and no plugin', () async {
    setUpFetch((_) => reply(200, body: 'abc'));

    await read('https://raw.example.test/index.json');

    final fields = records().single.fields;
    expect(fields['client'], 'host');
    expect(fields['pluginId'], '');
    expect(fields['host'], 'raw.example.test');
    expect(fields['credentials'], false);
    expect(fields['status'], 200);
    expect(fields['bytes'], 3);
  });
}
