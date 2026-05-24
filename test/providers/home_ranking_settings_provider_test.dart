import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/providers/home_ranking_settings_provider.dart';

void main() {
  group('Home ranking settings normalization', () {
    test('normalizes order by removing unknowns and appending missing sources',
        () {
      expect(
        normalizeHomeRankingSourcePriority('youtube,unknown,bilibili,youtube'),
        ['youtube', 'bilibili', 'netease'],
      );
    });

    test('normalizes disabled sources by dropping unknowns', () {
      expect(
        normalizeDisabledHomeRankingSources('netease,unknown,youtube'),
        {'netease', 'youtube'},
      );
    });

    test('normalizes all disabled home ranking sources back to enabled', () {
      expect(
        normalizeDisabledHomeRankingSources('bilibili,youtube,netease'),
        isEmpty,
      );
    });
  });

  group('HomeRankingSettingsNotifier', () {
    test('starts loading and clears loading after settings resolve', () async {
      final completer = Completer<Settings>();
      final store = _InMemorySettingsStore(Settings());
      final notifier = HomeRankingSettingsNotifier(
        loadSettings: () => completer.future,
        updateSettings: store.update,
      );

      expect(notifier.state.isLoading, isTrue);

      completer.complete(
        Settings()
          ..homeRankingSourcePriority = 'netease,youtube'
          ..disabledHomeRankingSources = 'bilibili',
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.sourceOrder, ['netease', 'youtube', 'bilibili']);
      expect(notifier.state.disabledSources, {'bilibili'});
      expect(notifier.state.isLoading, isFalse);
    });

    test('loads initial state from injected settings', () async {
      final store = _InMemorySettingsStore(
        Settings()
          ..homeRankingSourcePriority = 'youtube,bilibili'
          ..disabledHomeRankingSources = 'netease',
      );
      final notifier = _createNotifier(store);

      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.sourceOrder, ['youtube', 'bilibili', 'netease']);
      expect(notifier.state.disabledSources, {'netease'});
      expect(notifier.state.enabledSourceOrder, ['youtube', 'bilibili']);
      expect(notifier.state.isLoading, isFalse);
    });

    test('exposes immutable state collections', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);

      expect(
        () => notifier.state.sourceOrder.add('unknown'),
        throwsUnsupportedError,
      );
      expect(
        () => notifier.state.disabledSources.add('youtube'),
        throwsUnsupportedError,
      );
      expect(
        () => notifier.state.enabledSourceOrder.add('unknown'),
        throwsUnsupportedError,
      );
    });

    test('enabled source order provider exposes an immutable list', () async {
      final store = _InMemorySettingsStore(
        Settings()..disabledHomeRankingSources = 'youtube',
      );
      final container = ProviderContainer(
        overrides: [
          homeRankingSettingsProvider.overrideWith(
            (ref) => _createNotifier(store),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(homeRankingSettingsProvider);
      await Future<void>.delayed(Duration.zero);

      final enabledSources =
          container.read(enabledHomeRankingSourceOrderProvider);

      expect(enabledSources, ['bilibili', 'netease']);
      expect(
        () => enabledSources.add('unknown'),
        throwsUnsupportedError,
      );
    });

    test('setSourceOrder persists normalized order and updates state',
        () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.setSourceOrder(['netease', 'unknown', 'youtube']);

      expect(notifier.state.sourceOrder, ['netease', 'youtube', 'bilibili']);
      expect(
        store.settings.homeRankingSourcePriority,
        'netease,youtube,bilibili',
      );
    });

    test('setSourceOrder updates state before persistence completes', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      store.updateGate = Completer<void>();

      final persistence = notifier.setSourceOrder(['netease']);

      expect(notifier.state.sourceOrder, ['netease', 'bilibili', 'youtube']);
      expect(
        store.settings.homeRankingSourcePriority,
        defaultHomeRankingSourcePriority,
      );

      store.updateGate!.complete();
      await persistence;

      expect(
        store.settings.homeRankingSourcePriority,
        'netease,bilibili,youtube',
      );
    });

    test(
        'setSourceOrder persistence failure rolls back only source order '
        'and leaves disabled sources untouched', () async {
      final store = _InMemorySettingsStore(
        Settings()
          ..homeRankingSourcePriority = 'bilibili,youtube,netease'
          ..disabledHomeRankingSources = 'youtube',
      );
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      await notifier.toggleSource('netease', false);
      store.failNextUpdate = true;

      await notifier.setSourceOrder(['netease', 'youtube']);

      expect(
        notifier.state.sourceOrder,
        ['bilibili', 'youtube', 'netease'],
      );
      expect(notifier.state.disabledSources, {'youtube', 'netease'});
      expect(
        store.settings.homeRankingSourcePriority,
        'bilibili,youtube,netease',
      );
      expect(store.settings.disabledHomeRankingSourcesSet, {
        'youtube',
        'netease',
      });
    });

    test(
        'overlapping setSourceOrder calls run serially so an earlier failure '
        'cannot rollback a later successful order', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      store.failNextUpdate = true;

      final first = notifier.setSourceOrder(['youtube']);
      final second = notifier.setSourceOrder(['netease']);
      await Future.wait([first, second]);

      expect(notifier.state.sourceOrder, ['netease', 'bilibili', 'youtube']);
      expect(
        store.settings.homeRankingSourcePriority,
        'netease,bilibili,youtube',
      );
    });

    test(
        'overlapping setSourceOrder failures rollback to the last persisted '
        'order', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      store.failUpdateCount = 2;

      final first = notifier.setSourceOrder(['youtube']);
      final second = notifier.setSourceOrder(['netease']);
      await Future.wait([first, second]);

      expect(
        notifier.state.sourceOrder,
        ['bilibili', 'youtube', 'netease'],
      );
      expect(
        store.settings.homeRankingSourcePriority,
        'bilibili,youtube,netease',
      );
    });

    test('toggleSource disables and enables source', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);

      await notifier.toggleSource('youtube', false);

      expect(notifier.state.disabledSources, {'youtube'});
      expect(store.settings.disabledHomeRankingSourcesSet, {'youtube'});
      expect(notifier.state.enabledSourceOrder, ['bilibili', 'netease']);

      await notifier.toggleSource('youtube', true);

      expect(notifier.state.disabledSources, isEmpty);
      expect(store.settings.disabledHomeRankingSourcesSet, isEmpty);
      expect(
        notifier.state.enabledSourceOrder,
        ['bilibili', 'youtube', 'netease'],
      );
    });

    test('toggleSource updates state before persistence completes', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      store.updateGate = Completer<void>();

      final persistence = notifier.toggleSource('youtube', false);

      expect(notifier.state.disabledSources, {'youtube'});
      expect(notifier.state.enabledSourceOrder, ['bilibili', 'netease']);
      expect(store.settings.disabledHomeRankingSourcesSet, isEmpty);

      store.updateGate!.complete();
      await persistence;

      expect(store.settings.disabledHomeRankingSourcesSet, {'youtube'});
    });

    test('toggleSource keeps the last enabled source enabled', () async {
      final store = _InMemorySettingsStore(
        Settings()..disabledHomeRankingSources = 'bilibili,youtube',
      );
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      final previousUpdateCount = store.updateCount;

      await notifier.toggleSource('netease', false);

      expect(notifier.state.disabledSources, {'bilibili', 'youtube'});
      expect(notifier.state.enabledSourceOrder, ['netease']);
      expect(store.settings.disabledHomeRankingSourcesSet, {
        'bilibili',
        'youtube',
      });
      expect(store.updateCount, previousUpdateCount);
    });

    test(
        'toggleSource persistence failure rolls back only disabled sources '
        'and leaves source order untouched', () async {
      final store = _InMemorySettingsStore(
        Settings()
          ..homeRankingSourcePriority = 'youtube,bilibili,netease'
          ..disabledHomeRankingSources = 'netease',
      );
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      await notifier.setSourceOrder(['netease', 'youtube']);
      store.failNextUpdate = true;

      await notifier.toggleSource('youtube', false);

      expect(notifier.state.sourceOrder, ['netease', 'youtube', 'bilibili']);
      expect(notifier.state.disabledSources, {'netease'});
      expect(
        store.settings.homeRankingSourcePriority,
        'netease,youtube,bilibili',
      );
      expect(store.settings.disabledHomeRankingSources, 'netease');
    });

    test(
        'overlapping toggleSource calls run serially so an earlier failure '
        'cannot rollback a later successful disabled set', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      store.failNextUpdate = true;

      final first = notifier.toggleSource('youtube', false);
      final second = notifier.toggleSource('netease', false);
      await Future.wait([first, second]);

      expect(notifier.state.disabledSources, {'netease'});
      expect(store.settings.disabledHomeRankingSourcesSet, {'netease'});
    });

    test(
        'overlapping toggleSource failures rollback to the last persisted '
        'disabled sources', () async {
      final store = _InMemorySettingsStore(Settings());
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      store.failUpdateCount = 2;

      final first = notifier.toggleSource('youtube', false);
      final second = notifier.toggleSource('youtube', true);
      await Future.wait([first, second]);

      expect(notifier.state.disabledSources, isEmpty);
      expect(notifier.state.enabledSourceOrder, [
        'bilibili',
        'youtube',
        'netease',
      ]);
      expect(store.settings.disabledHomeRankingSourcesSet, isEmpty);
    });

    test('invalid source toggle does not change state', () async {
      final store = _InMemorySettingsStore(
        Settings()..disabledHomeRankingSources = 'netease',
      );
      final notifier = _createNotifier(store);
      await Future<void>.delayed(Duration.zero);
      final previous = notifier.state;

      await notifier.toggleSource('unknown', false);

      expect(notifier.state.sourceOrder, previous.sourceOrder);
      expect(notifier.state.disabledSources, previous.disabledSources);
      expect(notifier.state.isLoading, previous.isLoading);
      expect(store.updateCount, 0);
    });
  });
}

HomeRankingSettingsNotifier _createNotifier(_InMemorySettingsStore store) {
  return HomeRankingSettingsNotifier(
    loadSettings: store.get,
    updateSettings: store.update,
  );
}

class _InMemorySettingsStore {
  _InMemorySettingsStore(this.settings);

  final Settings settings;
  int updateCount = 0;
  bool failNextUpdate = false;
  int failUpdateCount = 0;
  Completer<void>? updateGate;

  Future<Settings> get() async => settings;

  Future<Settings> update(void Function(Settings settings) mutate) async {
    updateCount += 1;
    if (failNextUpdate) {
      failNextUpdate = false;
      throw StateError('update failed');
    }
    if (failUpdateCount > 0) {
      failUpdateCount -= 1;
      throw StateError('update failed');
    }
    final gate = updateGate;
    if (gate != null) {
      updateGate = null;
      await gate.future;
    }
    mutate(settings);
    return settings;
  }
}
