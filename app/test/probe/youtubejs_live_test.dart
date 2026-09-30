// PROBE ONLY (branch probe/youtubejs, not for merge): runs the bundled
// YouTube.js plugin in the real QuickJS runtime with the real network layer.
//
//   flutter test --run-skipped --tags live test/probe/youtubejs_live_test.dart
//
// FMP_PROBE_PLUGIN overrides the plugin path (default: the research build).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../support/memory_database.dart';

final class _AllowNetwork extends HttpOverrides {}

void main() {
  test('youtube.js probe: load, search, resolve, range GET', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final path =
          Platform.environment['FMP_PROBE_PLUGIN'] ??
          '../research/youtubejs-probe/dist/youtubejs_probe.js';
      final redactor = Redactor();
      final log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
      final database = memoryDatabase();
      addTearDown(database.close);
      final loader = ScriptPluginLoader(
        log: log,
        redactor: redactor,
        httpClients: SourceHttpClientFactory(log: log),
        storage: PluginStorageRepository(database),
      );
      final file = PluginFile.parse(File(path).readAsStringSync());
      await PluginRepository(database).install(
        InstalledPlugin(
          id: file.manifest.id,
          version: '0',
          manifestJson: '{}',
          script: '',
          installedAt: DateTime.utc(2026, 9, 30),
        ),
      );

      void out(String s) => stdout.writeln('FMP_PROBE $s');
      var seen = 0;
      void dump() {
        for (final r in log.history.skip(seen)) {
          final net = r.tag == 'network'
              ? ' ${r.fields['method']} ${r.fields['host']}${r.fields['path']} '
                    '${r.fields['status']} ${r.fields['ms']}ms ${r.fields['bytes']}B'
              : '';
          out('log ${r.level.name} ${r.tag} ${r.message}$net ${r.error ?? ''}');
        }
        seen = log.history.length;
      }

      Future<T> step<T>(String name, Future<T> Function() body) async {
        final sw = Stopwatch()..start();
        try {
          final value = await body();
          out('$name ms=${sw.elapsedMilliseconds}');
          return value;
        } on AppError catch (e) {
          log.report('$name failed', e, tag: 'probe');
          out('$name FAILED ms=${sw.elapsedMilliseconds}');
          rethrow;
        } finally {
          dump();
        }
      }

      final plugin = await step('load', () => loader.load(file));
      addTearDown(plugin.close);
      out('bundle chars=${file.source.length}');

      final page = await step(
        'search#1',
        () => plugin.search(SearchQuery(keyword: 'rick astley')),
      );
      out('items=${page.items.length} hasMore=${page.hasMore}');
      for (final t in page.items.take(3)) {
        out(
          '  ${t.sourceId} "${t.title}" by ${t.uploader} '
          '${t.duration} art=${t.artwork.length}',
        );
      }
      final page2 = await step(
        'search#2',
        () => plugin.search(SearchQuery(keyword: 'lofi')),
      );
      out('items=${page2.items.length}');

      final target = page.items.firstWhere(
        (t) =>
            (t.duration?.inSeconds ?? 0) > 60 &&
            (t.duration?.inSeconds ?? 0) < 900,
      );
      final candidates = await step(
        'resolve ${target.sourceId}',
        () => plugin.resolveStream(
          StreamRequest(
            sourceId: target.sourceId,
            formats: [
              StreamFormat(container: 'mp4', codec: 'aac'),
              StreamFormat(container: 'webm', codec: 'opus'),
            ],
          ),
        ),
      );
      for (final c in candidates) {
        out(
          '  ${c.container}/${c.codec} ${c.bitrate} host=${c.url.host} '
          'expiresAt=${c.expiresAt} headers=${c.headers.keys.toList()}',
        );
      }
      final res = await Dio().getUri<List<int>>(
        candidates.first.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-65535'},
          validateStatus: (_) => true,
        ),
      );
      out(
        'range GET status=${res.statusCode} '
        'type=${res.headers.value('content-type')} bytes=${res.data?.length}',
      );
      expect(res.statusCode, 206);
    }, _AllowNetwork());
  }, tags: 'live', timeout: const Timeout(Duration(minutes: 3)));
}
