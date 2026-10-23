import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';

void main() {
  // ADR 0013 §決定 4：Riverpod 的自動重試全域關閉。
  Future<int> buildsOfAFailingProvider(
    WidgetTester tester,
    Widget Function(Widget child) scope,
  ) async {
    var builds = 0;
    final failing = FutureProvider<int>((ref) async {
      builds++;
      throw Exception('failed on purpose');
    });
    await tester.pumpWidget(
      scope(
        Consumer(
          builder: (context, ref, _) {
            ref.watch(failing);
            return const SizedBox();
          },
        ),
      ),
    );
    // 預設的重試最多 10 次、間隔 200ms 起倍增，一分鐘內會全部跑完。
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpWidget(const SizedBox());
    return builds;
  }

  testWidgets('the app scope never retries a failed provider', (tester) async {
    expect(
      await buildsOfAFailingProvider(
        tester,
        (child) => appProviderScope(child: child),
      ),
      1,
    );
  });

  testWidgets('a scope with the default retry does retry (control)', (
    tester,
  ) async {
    expect(
      await buildsOfAFailingProvider(
        tester,
        (child) => ProviderScope(child: child),
      ),
      greaterThan(1),
    );
  });

  // 同一次啟動 `runApp` 好幾次（匯入進度、資料庫錯誤頁換成正式 App）：override 的數量不同時，
  // 沒有 key 的根會沿用同一個 element 而觸發 Riverpod 的斷言（M5 PR 6 實機驗證抓到）。
  group('replacing the root with a scope that has other overrides', () {
    final a = Provider<int>((ref) => 1);
    final b = Provider<int>((ref) => 2);

    testWidgets('works when each root has its own key', (tester) async {
      await tester.pumpWidget(
        appProviderScope(key: const ValueKey('first'), child: const SizedBox()),
      );
      await tester.pumpWidget(
        appProviderScope(
          key: const ValueKey('second'),
          overrides: [a.overrideWithValue(3), b.overrideWithValue(4)],
          child: const SizedBox(),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fails without keys (what the keys are for)', (tester) async {
      await tester.pumpWidget(appProviderScope(child: const SizedBox()));
      await tester.pumpWidget(
        appProviderScope(
          overrides: [a.overrideWithValue(3)],
          child: const SizedBox(),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });
  });
}
