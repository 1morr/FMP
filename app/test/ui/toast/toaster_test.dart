import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/ui/toast/toaster.dart';

void main() {
  late Log log;
  late List<Toast> shown;

  /// 以繁中與固定的插件名稱建一個 [Toaster]，記下它送出的提示。
  Toaster toaster({AppLocale locale = AppLocale.zhTw}) {
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    final toaster = Toaster(
      log: log,
      translations: locale.buildSync,
      sourceName: (pluginId) => pluginId == 'bilibili' ? 'Bilibili' : null,
    );
    shown = [];
    toaster.toasts.listen(shown.add);
    addTearDown(toaster.dispose);
    return toaster;
  }

  test('durations: 4 seconds for success and info, 6 for the rest', () {
    expect(
      {for (final kind in ToastKind.values) kind: kind.duration.inSeconds},
      {
        ToastKind.success: 4,
        ToastKind.info: 4,
        ToastKind.warning: 6,
        ToastKind.error: 6,
      },
    );
  });

  test('messages pass through with their kind and action', () {
    final toasts = toaster();
    final action = ToastAction(label: '復原', onPressed: () {});

    toasts
      ..success('已加入')
      ..info('已複製', action: action)
      ..warning('空間不足');

    expect(
      [for (final t in shown) (t.kind, t.message, t.action)],
      [
        (ToastKind.success, '已加入', null),
        (ToastKind.info, '已複製', action),
        (ToastKind.warning, '空間不足', null),
      ],
    );
  });

  group('errors', () {
    test('show the mapped message with the plugin name', () {
      toaster().error(
        RateLimited(pluginId: 'bilibili'),
        operation: 'Search failed',
        tag: 'search',
      );

      expect(shown.single.kind, ToastKind.error);
      expect(shown.single.message, 'Bilibili 請求太頻繁，請稍後再試');
    });

    test('an unknown plugin shows its id; no plugin, the generic word', () {
      final toasts = toaster(locale: AppLocale.en);
      toasts
        ..error(
          ParseError(pluginId: 'fmp-test'),
          operation: 'Load failed',
          tag: 'plugins',
        )
        ..error(ParseError(), operation: 'Load failed', tag: 'plugins');

      expect(
        [for (final t in shown) t.message],
        [
          'The response format of fmp-test changed. An update may be needed.',
          'The response format of the source changed. An update may be needed.',
        ],
      );
    });

    test('an error without a plugin id never names an uninstalled source', () {
      final toasts = toaster();
      toasts.error(
        RateLimited(),
        operation: 'Index request failed',
        tag: 'plugins',
      );

      expect(shown.single.message, isNot(contains('未安裝')));
      expect(shown.single.message, isNot(contains('已停用')));
    });

    test('a sentence wraps the mapped message; the key stays class and '
        'plugin', () {
      fakeAsync((async) {
        final toasts = toaster();
        toasts.error(
          NotFound(pluginId: 'bilibili'),
          operation: 'Track skipped',
          tag: 'playback',
          sentence: (message) => '已跳過「A」：$message',
        );
        // 同類別同音源、不同的句子：仍在去重的視窗內。
        toasts.error(
          NotFound(pluginId: 'bilibili'),
          operation: 'Track skipped',
          tag: 'playback',
          sentence: (message) => '已跳過「B」：$message',
        );

        expect([for (final t in shown) t.message], ['已跳過「A」：找不到內容，可能已失效']);
        expect(log.history, hasLength(2));
      });
    });

    test("never show the plugin's own message", () {
      toaster().error(
        structuredScriptError(
          pluginId: 'bilibili',
          fmpError: 'VerificationRequired',
          message: 'FAKE_SERVER_TEXT_123',
        ),
        operation: 'Play failed',
        tag: 'playback',
      );

      expect(shown.single.message, isNot(contains('FAKE_SERVER_TEXT_123')));
    });

    test('go to the error history, also when deduplicated', () {
      final toasts = toaster();
      for (var i = 0; i < 2; i++) {
        toasts.error(
          NetworkError(pluginId: 'bilibili'),
          operation: 'Search failed',
          tag: 'search',
        );
      }

      expect(shown, hasLength(1));
      final reported = [
        for (final record in log.history)
          if (record.message == 'Search failed') record,
      ];
      expect(reported, hasLength(2));
      expect(reported.first.tag, 'search');
      expect(reported.first.level, LogLevel.warning);
      expect(reported.first.fields['type'], 'NetworkError');
    });
  });

  group('deduplication (5 seconds)', () {
    test('the same message shows once within the window', () {
      fakeAsync((async) {
        final toasts = toaster();
        toasts.success('已加入');
        async.elapse(const Duration(milliseconds: 4999));
        toasts.success('已加入');
        expect(shown, hasLength(1));

        async.elapse(const Duration(milliseconds: 1));
        toasts.success('已加入');
        expect(shown, hasLength(2));
      });
    });

    test('a suppressed toast does not extend the window', () {
      fakeAsync((async) {
        final toasts = toaster();
        toasts.info('已複製');
        async.elapse(const Duration(seconds: 3));
        toasts.info('已複製');
        async.elapse(const Duration(seconds: 2));
        toasts.info('已複製');

        expect(shown, hasLength(2));
      });
    });

    test('different messages or kinds are not duplicates', () {
      fakeAsync((async) {
        toaster()
          ..success('已加入')
          ..success('已移除')
          ..info('已加入');

        expect(shown, hasLength(3));
      });
    });

    test('errors are keyed by class and plugin, not by message', () {
      fakeAsync((async) {
        final toasts = toaster();
        void fail(AppError error) =>
            toasts.error(error, operation: 'Search failed', tag: 'search');

        fail(Unavailable(reason: UnavailableReason.region, pluginId: 'a'));
        // 同類別、同音源、不同原因：同一類。
        fail(Unavailable(reason: UnavailableReason.age, pluginId: 'a'));
        fail(Unavailable(reason: UnavailableReason.region, pluginId: 'b'));
        fail(NotFound(pluginId: 'a'));

        expect([for (final t in shown) t.message], hasLength(3));

        async.elapse(Toaster.dedupeWindow);
        fail(Unavailable(reason: UnavailableReason.age, pluginId: 'a'));
        expect(shown, hasLength(4));
      });
    });
  });

  group('an invalidated sign-in', () {
    void reject(Toaster toasts, String pluginId) => toasts.error(
      CredentialInvalid(pluginId: pluginId),
      operation: 'Search failed',
      tag: 'search',
    );

    test('keeps its prompt over the same failure that follows as an error', () {
      fakeAsync((async) {
        final toasts = toaster();
        final action = ToastAction(label: '登入', onPressed: () {});

        toasts.credentialInvalidated('bilibili', '已失效', action: action);
        reject(toasts, 'bilibili');
        // 別的音源、別的類別照常。
        reject(toasts, 'netease');
        toasts.error(
          NetworkError(pluginId: 'bilibili'),
          operation: 'Search failed',
          tag: 'search',
        );

        expect(
          [for (final t in shown) (t.kind, t.action)],
          [
            (ToastKind.warning, action),
            (ToastKind.error, null),
            (ToastKind.error, null),
          ],
        );
        // 被去重的錯誤仍寫進錯誤歷史。
        expect(
          log.history.where((record) => record.message == 'Search failed'),
          hasLength(3),
        );

        async.elapse(Toaster.dedupeWindow);
        reject(toasts, 'bilibili');
        expect(shown, hasLength(4));
      });
    });

    test('replaces an error that arrived first', () {
      final toasts = toaster();
      final action = ToastAction(label: '登入', onPressed: () {});

      reject(toasts, 'bilibili');
      toasts.credentialInvalidated('bilibili', '已失效', action: action);

      expect(shown.last.action, action);
    });

    test('an unrelated change to the prompt text does not stop the '
        'deduplication', () {
      final toasts = toaster();
      final action = ToastAction(label: '登入', onPressed: () {});

      toasts.credentialInvalidated('bilibili', '登入已失效（改過）', action: action);
      reject(toasts, 'bilibili');

      expect(shown, hasLength(1));
    });
  });

  test('without a host the toasts are dropped', () {
    final toasts = Toaster(
      log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
      translations: AppLocale.zhTw.buildSync,
      sourceName: (_) => null,
    );
    addTearDown(toasts.dispose);

    expect(() => toasts.success('已加入'), returnsNormally);
  });
}
