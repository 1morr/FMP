import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/library/playlist_import_provider.dart';
import 'package:fmp/services/import/playlist_import_service.dart';

import '../support/pump_until.dart';

void main() {
  test(
    'invalidating playlistImportServiceProvider disposes the service it built',
    () async {
      final container = ProviderContainer(
        overrides: [
          sourceManagerProvider.overrideWithValue(SourceManager(sources: [])),
        ],
      );
      addTearDown(container.dispose);

      final first = container.read(playlistImportServiceProvider);
      var firstDone = false;
      first.progressStream.listen(null, onDone: () => firstDone = true);

      container.invalidate(playlistImportServiceProvider);
      final second = container.read(playlistImportServiceProvider);
      expect(second, isNot(same(first)));

      await pumpUntil(
        () => firstDone,
        reason: "the replaced service's progress stream should be closed",
      );
    },
  );

  test('disposing the container disposes the service', () async {
    final container = ProviderContainer(
      overrides: [
        sourceManagerProvider.overrideWithValue(SourceManager(sources: [])),
      ],
    );

    final service = container.read(playlistImportServiceProvider);
    var done = false;
    service.progressStream.listen(null, onDone: () => done = true);

    container.dispose();

    await pumpUntil(
      () => done,
      reason: "the service's progress stream should close with its provider",
    );
  });

  /// 服務只歸 provider 所有。notifier 以前在 `_teardown` 裡 `_service.dispose()`，
  /// 單獨 invalidate notifier 就會關掉仍被共用的服務，重建後的 notifier
  /// 聽的是一條已關閉的 stream，匯入時 `add` 直接丟 StateError。
  test('invalidating playlistImportProvider alone leaves the shared service '
      'open for the rebuilt notifier', () async {
    final container = ProviderContainer(
      overrides: [
        sourceManagerProvider.overrideWithValue(SourceManager(sources: [])),
      ],
    );
    addTearDown(container.dispose);

    final service = container.read(playlistImportServiceProvider);
    container.read(playlistImportProvider);
    var serviceDone = false;
    service.progressStream.listen(null, onDone: () => serviceDone = true);

    container.invalidate(playlistImportProvider);
    final notifier = container.read(playlistImportProvider.notifier);
    expect(container.read(playlistImportServiceProvider), same(service));

    await drainEventQueue(
      reason:
          "the shared service's progress stream must not close when "
          'only the notifier is rebuilt',
    );
    expect(serviceDone, isFalse);

    final progressPhases = <ImportPhase>[];
    container.listen(
      playlistImportProvider,
      (_, next) => progressPhases.add(next.progress.phase),
    );
    // 沒有匯入來源認得這個網址：服務先發 `fetching` 進度，再丟「不支援的連結」，
    // 不碰網路。
    await notifier.importAndMatch('https://example.com/not-a-playlist');

    expect(
      progressPhases,
      contains(ImportPhase.fetching),
      reason: 'the rebuilt notifier should receive progress from the service',
    );
    expect(serviceDone, isFalse);
  });
}
