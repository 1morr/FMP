import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/download/download_providers.dart';

void main() {
  group('task-scoped download progress providers', () {
    test(
      'task-scoped progress provider returns null when no live progress exists',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final progress = container.read(downloadTaskProgressProvider(42));

        expect(progress, isNull);
      },
    );

    test(
      'task-scoped progress provider returns live progress for matching task id',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container
            .read(downloadProgressStateProvider.notifier)
            .update(7, 0.5, 50, 100);

        final progress = container.read(downloadTaskProgressProvider(7));

        expect(progress, isNotNull);
        expect(progress!.$1, 0.5);
        expect(progress.$2, 50);
        expect(progress.$3, 100);
      },
    );

    test('task-scoped progress provider ignores unrelated task updates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final values = <(double, int, int?)?>[];
      final subscription = container.listen<(double, int, int?)?>(
        downloadTaskProgressProvider(7),
        (_, next) => values.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container
          .read(downloadProgressStateProvider.notifier)
          .update(8, 0.25, 25, 100);

      expect(container.read(downloadTaskProgressProvider(7)), isNull);
      expect(values, hasLength(1));
      expect(values.single, isNull);
    });
  });
}
