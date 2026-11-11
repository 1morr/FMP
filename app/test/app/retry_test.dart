import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';

void main() {
  testWidgets('the root ProviderScope never retries a failing provider', (
    tester,
  ) async {
    await tester.pumpWidget(buildRoot());
    final scope = tester.widget<ProviderScope>(find.byType(ProviderScope));

    var calls = 0;
    final failing = FutureProvider<int>((ref) async {
      calls++;
      throw Exception('transient');
    });
    final container = ProviderContainer(retry: scope.retry);
    addTearDown(container.dispose);
    final sub = container.listen(failing, (_, _) {});
    addTearDown(sub.close);

    // Riverpod 3 的預設重試從 200ms 開始倍增；等過好幾輪仍只能有一次。
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 1);
    expect(container.read(failing).hasError, isTrue);
  });
}
