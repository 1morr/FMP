import 'dart:convert';
import 'dart:io';

import 'package:fjs/fjs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fjs.dart';

/// 建引擎失敗一次之後，下一次呼叫要重新建，不能一直拿到快取住的失敗。
///
/// 自己一個檔：要在 fjs 的原生庫還沒初始化時呼叫插件（每個測試檔是自己的
/// isolate）。主機上的 `flutter test` 沒有把原生庫打包進去，宿主自己初始化
/// 會失敗，丟的不是 [JsError]（例如 App 裡原生庫載入失敗）；之後由
/// [loadFjsForTests] 初始化好，下一次呼叫就該成功。
void main() {
  test(
    'after the engine fails to start, the next call starts it again',
    () async {
      final logDir = Directory.systemTemp.createTempSync('fmp_engine_retry_');
      addTearDown(() => logDir.deleteSync(recursive: true));
      final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
      addTearDown(log.close);
      final host = PluginHost(
        bundles: [
          PluginBundle(
            manifest: jsonEncode({
              'id': 'demo',
              'name': 'Demo',
              'version': '1.0.0',
              'capabilities': ['search'],
              'domains': ['api.example.com'],
            }),
            code: '''
            export async function search({ query }) {
              return { tracks: [{ id: query, title: query, author: '' }] };
            }
          ''',
          ),
        ],
        log: log,
      );
      addTearDown(host.close);
      final plugin = host.plugins.single;

      final failure = await plugin
          .search('first')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(failure, isNotNull, reason: 'fjs is not initialized yet');
      expect(failure, isNot(isA<JsError>()));

      await loadFjsForTests();

      expect((await plugin.search('second')).single.id, 'second');
    },
  );
}
