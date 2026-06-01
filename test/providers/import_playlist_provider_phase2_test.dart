import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/playlist_import/playlist_import_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/library/import_playlist_provider.dart';
import 'package:fmp/providers/library/playlist_import_provider.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:fmp/services/import/playlist_import_service.dart'
    as legacy_import;
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
    test('legacy PlaylistImportNotifier ignores late importAndMatch results',
        () async {
      final service = _FakePlaylistImportService();
      final notifier = PlaylistImportNotifier(service);

      final oldImport = service.enqueueImport(_playlistImportResult('old'));
      final oldFuture = notifier.importAndMatch('https://example.com/old');
      await pumpEventQueue(times: 2);

      final newImport = service.enqueueImport(_playlistImportResult('new'));
      final newFuture = notifier.importAndMatch('https://example.com/new');
      await pumpEventQueue(times: 2);

      oldImport.complete();
      await oldFuture;

      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.playlist, isNull);

      newImport.complete();
      await newFuture;

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.playlist?.name, 'new');
      notifier.dispose();
    });

    test('legacy PlaylistImportNotifier ignores late manualSearch results',
        () async {
      final service = _FakePlaylistImportService();
      final notifier = PlaylistImportNotifier(service);
      notifier.setSeedState(
        PlaylistImportState(
          matchedTracks: [
            MatchedTrack(
              original: const ImportedTrack(
                title: 'Original',
                artists: ['Artist'],
              ),
              status: MatchStatus.noResult,
            ),
          ],
        ),
      );

      final oldSearch = service.enqueueSearch([_track('old-manual')]);
      final oldFuture = notifier.manualSearch(0, 'old query');
      await pumpEventQueue(times: 2);

      final newSearch = service.enqueueSearch([_track('new-manual')]);
      final newFuture = notifier.manualSearch(0, 'new query');
      await pumpEventQueue(times: 2);

      oldSearch.complete();
      await oldFuture;
      expect(
        notifier.state.matchedTracks.single.selectedTrack,
        isNull,
      );

      newSearch.complete();
      await newFuture;
      expect(
        notifier.state.matchedTracks.single.selectedTrack?.sourceId,
        'new-manual',
      );
      notifier.dispose();
    });

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
        expect(fakeService.disposeCalls, 1);
        expect(
          container.read(importPlaylistProvider('async-cancel')).wasCancelled,
          isTrue,
        );
      },
    );

    test('reset prevents a late import result from rewriting idle state',
        () async {
      final fakeService = FakeImportService();
      final container = ProviderContainer(
        overrides: [
          importServiceFactoryProvider.overrideWithValue(() => fakeService),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<ImportPlaylistState>(
        importPlaylistProvider('reset-stale'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final notifier =
          container.read(importPlaylistProvider('reset-stale').notifier);
      final importFuture = notifier.importFromUrl(
        'https://example.com/playlist?list=reset-stale',
      );
      await Future<void>.delayed(Duration.zero);

      notifier.reset();
      fakeService.complete(_result('late result'));
      await importFuture;

      final state = container.read(importPlaylistProvider('reset-stale'));
      expect(state.isImporting, isFalse);
      expect(state.result, isNull);
      expect(state.errorMessage, isNull);
      expect(state.wasCancelled, isFalse);
    });

    test('new import ignores late progress and result from previous service',
        () async {
      final oldService = FakeImportService();
      final newService = FakeImportService();
      var createCount = 0;
      final container = ProviderContainer(
        overrides: [
          importServiceFactoryProvider.overrideWithValue(() {
            createCount++;
            return createCount == 1 ? oldService : newService;
          }),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<ImportPlaylistState>(
        importPlaylistProvider('overlap-stale'),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final notifier =
          container.read(importPlaylistProvider('overlap-stale').notifier);
      final oldFuture = notifier.importFromUrl(
        'https://example.com/playlist?list=old',
      );
      await Future<void>.delayed(Duration.zero);
      expect(oldService.importCalls, 1);

      notifier.cancelImport();
      final newFuture = notifier.importFromUrl(
        'https://example.com/playlist?list=new',
      );
      await Future<void>.delayed(Duration.zero);
      expect(newService.importCalls, 1);

      oldService.emit(
        const ImportProgress(
          status: ImportStatus.importing,
          current: 1,
          total: 1,
          currentItem: 'old progress',
        ),
      );
      oldService.complete(_result('old result'));
      await oldFuture;
      await Future<void>.delayed(Duration.zero);

      var state = container.read(importPlaylistProvider('overlap-stale'));
      expect(state.isImporting, isTrue);
      expect(state.progress.currentItem, isNull);
      expect(state.result, isNull);
      expect(state.wasCancelled, isFalse);

      newService.complete(_result('new result'));
      await newFuture;

      state = container.read(importPlaylistProvider('overlap-stale'));
      expect(state.isImporting, isFalse);
      expect(state.result!.playlist.name, 'new result');
      expect(state.wasCancelled, isFalse);
    });
  });
}

legacy_import.PlaylistImportResult _playlistImportResult(String name) {
  final importedTrack = ImportedTrack(
    title: '$name track',
    artists: const ['Artist'],
  );
  return legacy_import.PlaylistImportResult(
    playlist: ImportedPlaylist(
      name: name,
      sourceUrl: 'https://example.com/$name',
      source: PlaylistSource.qqMusic,
      tracks: [importedTrack],
      totalCount: 1,
    ),
    matchedTracks: [
      MatchedTrack(
        original: importedTrack,
        selectedTrack: _track('$name-match'),
        status: MatchStatus.matched,
      ),
    ],
  );
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId;
}

extension on PlaylistImportNotifier {
  void setSeedState(PlaylistImportState state) {
    this.state = state;
  }
}

class _FakePlaylistImportService extends legacy_import.PlaylistImportService {
  _FakePlaylistImportService() : super(sourceManager: SourceManager());

  final _progressController =
      StreamController<legacy_import.ImportProgress>.broadcast();
  final List<_PendingPlaylistImport> _pendingImports = [];
  final List<_PendingManualSearch> _pendingSearches = [];

  @override
  Stream<legacy_import.ImportProgress> get progressStream =>
      _progressController.stream;

  Completer<void> enqueueImport(legacy_import.PlaylistImportResult result) {
    final gate = Completer<void>();
    _pendingImports.add(_PendingPlaylistImport(gate, result));
    return gate;
  }

  Completer<void> enqueueSearch(List<Track> results) {
    final gate = Completer<void>();
    _pendingSearches.add(_PendingManualSearch(gate, results));
    return gate;
  }

  @override
  Future<legacy_import.PlaylistImportResult> importAndMatch(
    String url, {
    legacy_import.SearchSourceConfig searchSource =
        legacy_import.SearchSourceConfig.all,
    int maxSearchResults = 5,
  }) async {
    final pending = _pendingImports.removeAt(0);
    await pending.gate.future;
    return pending.result;
  }

  @override
  Future<List<Track>> searchForTrack(
    String query, {
    legacy_import.SearchSourceConfig searchSource =
        legacy_import.SearchSourceConfig.all,
    int maxResults = 5,
  }) async {
    final pending = _pendingSearches.removeAt(0);
    await pending.gate.future;
    return pending.results;
  }

  @override
  void dispose() {
    unawaited(_progressController.close());
  }
}

class _PendingPlaylistImport {
  _PendingPlaylistImport(this.gate, this.result);

  final Completer<void> gate;
  final legacy_import.PlaylistImportResult result;
}

class _PendingManualSearch {
  _PendingManualSearch(this.gate, this.results);

  final Completer<void> gate;
  final List<Track> results;
}

ImportResult _result(String name) {
  return ImportResult(
    playlist: Playlist()
      ..id = name.hashCode
      ..name = name,
    addedCount: 1,
    skippedCount: 0,
    errors: const [],
  );
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

  void complete(ImportResult result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
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
