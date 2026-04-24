import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/playlist_import/playlist_import_source.dart';
import 'package:fmp/providers/import_playlist_provider.dart';
import 'package:fmp/providers/playlist_import_provider.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('PlaylistImportState.selectedTracks', () {
    test('copies selected tracks before writing original platform metadata',
        () {
      final selected = Track()
        ..id = 42
        ..sourceId = 'matched-bv'
        ..sourceType = SourceType.bilibili
        ..title = 'Matched Song'
        ..artist = 'Matched Artist';

      final state = PlaylistImportState(
        matchedTracks: [
          MatchedTrack(
            original: const ImportedTrack(
              title: 'Original Song',
              artists: ['Original Artist'],
              sourceId: 'qq-songmid-1',
              source: PlaylistSource.qqMusic,
            ),
            selectedTrack: selected,
            status: MatchStatus.userSelected,
          ),
        ],
      );

      final tracks = state.selectedTracks;

      expect(tracks, hasLength(1));
      expect(identical(tracks.single, selected), isFalse);
      expect(tracks.single.id, selected.id);
      expect(tracks.single.sourceType, selected.sourceType);
      expect(tracks.single.sourceId, selected.sourceId);
      expect(tracks.single.originalSongId, 'qq-songmid-1');
      expect(tracks.single.originalSource, 'qqmusic');
      expect(selected.originalSongId, isNull);
      expect(selected.originalSource, isNull);
    });
  });

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

        expect(
          container.read(importPlaylistProvider('phase2-test')).isImporting,
          isTrue,
        );
        expect(
          container
              .read(importPlaylistProvider('phase2-test'))
              .progress
              .currentItem,
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

    test(
      'cancels before async service creation completes and prevents a late import start',
      () async {
        final fakeService = FakeImportService();
        final serviceCompleter = Completer<ImportServiceFacade>();
        final container = ProviderContainer(
          overrides: [
            importServiceFactoryProvider.overrideWithValue(
              () => serviceCompleter.future,
            ),
          ],
        );
        addTearDown(container.dispose);

        final subscription = container.listen<ImportPlaylistState>(
          importPlaylistProvider('async-cancel'),
          (_, __) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        final notifier =
            container.read(importPlaylistProvider('async-cancel').notifier);
        final importFuture = notifier.importFromUrl(
          'https://example.com/playlist?list=async-cancel',
          useAuth: true,
        );

        notifier.cancelImport();
        expect(
          container.read(importPlaylistProvider('async-cancel')).wasCancelled,
          isTrue,
        );

        serviceCompleter.complete(fakeService);
        await Future<void>.delayed(Duration.zero);

        if (fakeService.importCalls > 0) {
          fakeService.fail(const ImportException('late import started'));
        }

        final result = await importFuture.timeout(const Duration(seconds: 1));

        expect(result, isNull);
        expect(fakeService.importCalls, 0);
        expect(fakeService.cancelCalls, 1);
        expect(fakeService.cleanupCalls, 1);
        expect(
          container.read(importPlaylistProvider('async-cancel')).wasCancelled,
          isTrue,
        );
      },
    );
  });
}

class FakeImportService implements ImportServiceFacade {
  final _progressController = StreamController<ImportProgress>.broadcast();
  final _completer = Completer<ImportResult>();

  int importCalls = 0;
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
    importCalls++;
    return _completer.future;
  }
}
