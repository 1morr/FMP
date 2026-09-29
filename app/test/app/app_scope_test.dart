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
}
