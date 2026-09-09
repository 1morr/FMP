import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/providers/download/file_exists_cache.dart';
import 'package:fmp/providers/library/playlist_import_provider.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/providers/settings/layout_settings_provider.dart';
import 'package:fmp/providers/settings/theme_provider.dart';
import 'package:fmp/services/audio/queue_state.dart';
import 'package:fmp/services/import/playlist_import_service.dart';

import '../support/fakes/fake_settings_repository.dart';

/// Riverpod 3 的 `Notifier` 與被它取代的 `StateNotifier` 有一個靜默的語意差：
/// `build()` 重跑時**實例會被保留**（`notifier/orphan.dart` 明文），而
/// `StateNotifierProvider((ref) => X(ref.watch(y)))` 是整個重建。所以每一批
/// 改寫都要有一條「重建之後狀態與副作用都還對」的測試，否則漏改只會表現成
/// 洩漏或殘留，不會有錯誤訊息。
void main() {
  group('state providers rewritten as Notifier', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test(
      'queueStateProvider starts empty and takes a published projection',
      () {
        expect(container.read(queueStateProvider), const QueueState());

        final projection = QueueState(
          queue: [Track()..title = 'one'],
          queueVersion: 1,
        );
        container.read(queueStateProvider.notifier).publish(projection);
        expect(container.read(queueStateProvider), same(projection));

        // 重建回到初始值 —— 投影的唯一真相在 AudioController，provider 不留舊值。
        container.invalidate(queueStateProvider);
        expect(container.read(queueStateProvider), const QueueState());
      },
    );

    test('lyricsAutoMatchingProvider flips through its named setter', () {
      expect(container.read(lyricsAutoMatchingProvider), isFalse);

      container.read(lyricsAutoMatchingProvider.notifier).setMatching(true);
      expect(container.read(lyricsAutoMatchingProvider), isTrue);

      container.invalidate(lyricsAutoMatchingProvider);
      expect(container.read(lyricsAutoMatchingProvider), isFalse);
    });

    test('fileExistsCacheEpochProvider mirrors the cache epoch', () {
      expect(container.read(fileExistsCacheEpochProvider), 0);

      container.read(fileExistsCacheEpochProvider.notifier).set(7);
      expect(container.read(fileExistsCacheEpochProvider), 7);

      container.invalidate(fileExistsCacheEpochProvider);
      expect(container.read(fileExistsCacheEpochProvider), 0);
    });
  });

  group('settings notifiers survive a build() re-run', () {
    // 這一組守的是 Notifier 改寫裡最容易靜默壞掉的地方：`Notifier.build()` 重跑時
    // **實例會被保留**，所以協作者欄位必須是 `late` 而不是 `late final`，
    // 否則第二次指派就是 LateInitializationError。
    // 換掉的是**實例**：override 每次回傳同一個 repository 的話，失效後新舊
    // 值相等，Riverpod 不會通知下游，build() 也就不會重跑 —— 那樣測不到東西。
    late FakeSettingsRepository repository;
    late ProviderContainer container;

    setUp(() {
      repository = FakeSettingsRepository(
        Settings()
          ..railExpanded = true
          ..detailPanelWidth = 500,
      );
      container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) => repository),
        ],
      );
    });
    tearDown(() => container.dispose());

    test('layoutSettingsProvider reloads instead of throwing', () async {
      container.read(layoutSettingsProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(layoutSettingsProvider).railExpanded, isTrue);
      expect(container.read(layoutSettingsProvider).detailPanelWidth, 500);

      final notifier = container.read(layoutSettingsProvider.notifier);

      repository = FakeSettingsRepository(Settings()..railExpanded = false);
      container.invalidate(settingsRepositoryProvider);
      container.read(layoutSettingsProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(layoutSettingsProvider.notifier),
        same(notifier),
        reason: 'Riverpod 3 保留 Notifier 實例，只重跑 build()',
      );
      expect(container.read(layoutSettingsProvider).railExpanded, isFalse);
    });

    test('themeProvider reloads instead of throwing', () async {
      container.read(themeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeProvider).isLoading, isFalse);

      final notifier = container.read(themeProvider.notifier);

      repository = FakeSettingsRepository(Settings());
      container.invalidate(settingsRepositoryProvider);
      container.read(themeProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeProvider.notifier), same(notifier));
      expect(container.read(themeProvider).isLoading, isFalse);
    });
  });

  _playlistImportSubscriptionGroup();
}

/// `PlaylistImportNotifier` 是全批唯一在建構子裡 `listen` 的 notifier。
/// `build()` 重跑時實例被保留，訂閱卻會再開一條 —— 沒有 `ref.onDispose`
/// 就是每次 rebuild 洩一條，而且完全沒有錯誤訊息。
void _playlistImportSubscriptionGroup() {
  test('playlist import notifier does not leak its progress subscription', () {
    var service = _CountingImportService();
    final container = ProviderContainer(
      overrides: [playlistImportServiceProvider.overrideWith((ref) => service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(playlistImportProvider.notifier);
    expect(service.listenCount, 1);
    expect(service.cancelCount, 0);

    final first = service;
    service = _CountingImportService();
    container.invalidate(playlistImportServiceProvider);
    container.read(playlistImportProvider);

    expect(container.read(playlistImportProvider.notifier), same(notifier));
    expect(first.cancelCount, 1, reason: '前一次 build 開的訂閱必須在 rebuild 之前關掉');
    expect(service.listenCount, 1);
  });
}

class _CountingImportService implements PlaylistImportService {
  int listenCount = 0;
  int cancelCount = 0;
  late final StreamController<ImportProgress> _controller =
      StreamController<ImportProgress>.broadcast(
        onListen: () => listenCount++,
        onCancel: () => cancelCount++,
      );

  @override
  Stream<ImportProgress> get progressStream => _controller.stream;

  @override
  void dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
