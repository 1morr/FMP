import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/import_playlist_provider.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('import playlist provider phase 2', () {
    test(
      'forwards progress and owns cancellation cleanup after listeners detach',
      () async {
        final fakeService = FakeImportService();
        final container = ProviderContainer(
          overrides: [
            importServiceFactoryProvider.overrideWithValue(() => fakeService),
          ],
        );
        addTearDown(container.dispose);

        final subscription = container.listen<ImportPlaylistState>(
          importPlaylistProvider('phase2-test'),
          (_, __) {},
          fireImmediately: true,
        );

        final notifier =
            container.read(importPlaylistProvider('phase2-test').notifier);
        final importFuture = notifier.importFromUrl(
          'https://example.com/playlist?list=phase2',
          useAuth: true,
        );

        fakeService.emit(
          const ImportProgress(
            status: ImportStatus.importing,
            current: 1,
            total: 3,
            currentItem: 'Track 1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(container.read(importPlaylistProvider('phase2-test')).isImporting, isTrue);
        expect(
          container.read(importPlaylistProvider('phase2-test')).progress.currentItem,
          'Track 1',
        );

        subscription.close();
        await Future<void>.delayed(Duration.zero);
        expect(
          fakeService.disposeCalls,
          0,
          reason: 'provider should stay alive while import is in flight',
        );

        notifier.cancelImport();
        expect(fakeService.cancelCalls, 1);

        fakeService.fail(const ImportException('cancelled'));
        final result = await importFuture;

        expect(result, isNull);
        expect(fakeService.cleanupCalls, 1);
        expect(
          container.read(importPlaylistProvider('phase2-test')).wasCancelled,
          isTrue,
        );

        await Future<void>.delayed(Duration.zero);
        expect(fakeService.disposeCalls, 1);
      },
    );
  });
}

class FakeImportService implements ImportServiceFacade {
  final _progressController = StreamController<ImportProgress>.broadcast();
  final _completer = Completer<ImportResult>();

  int cancelCalls = 0;
  int cleanupCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<ImportProgress> get progressStream => _progressController.stream;

  void emit(ImportProgress progress) {
    _progressController.add(progress);
  }

  void fail(Object error) {
    if (!_completer.isCompleted) {
      _completer.completeError(error);
    }
  }

  @override
  void cancelImport() {
    cancelCalls++;
  }

  @override
  Future<void> cleanupCancelledImport() async {
    cleanupCalls++;
  }

  @override
  void dispose() {
    disposeCalls++;
    unawaited(_progressController.close());
  }

  @override
  Future<ImportResult> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
    bool useAuth = false,
  }) {
    return _completer.future;
  }
}
