import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/refresh_settings_provider.dart';
import 'package:fmp/providers/repository_providers.dart';
import 'package:fmp/ui/pages/settings/home_ranking_settings_page.dart';
import 'package:fmp/ui/pages/settings/settings_page.dart';
import 'package:fmp/ui/router.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeRankingSettingsPage', () {
    late Settings settings;
    late _FakeSettingsRepository repository;

    setUp(() {
      LocaleSettings.setLocale(AppLocale.en);
      settings = Settings();
      repository = _FakeSettingsRepository(settings);
    });

    testWidgets('shows loading then all three sources', (tester) async {
      final completer = Completer<Settings>();
      repository.getOverride = () => completer.future;

      await _pumpPage(tester, repository);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(t.importPlatform.bilibili), findsNothing);

      completer.complete(settings);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(t.importPlatform.bilibili), findsOneWidget);
      expect(find.text(t.importPlatform.youtube), findsOneWidget);
      expect(find.text(t.importPlatform.netease), findsOneWidget);
      expect(find.text(t.settings.homeRankingSettings.hint), findsOneWidget);
    });

    testWidgets('toggle source updates the persisted disabled sources',
        (tester) async {
      await _pumpPage(tester, repository);
      await tester.pump();

      await tester.tap(
        find.byType(Switch).at(1),
      );
      await tester.pump();

      expect(repository.settings.disabledHomeRankingSourcesSet, {'youtube'});
      expect(
        find.text(t.settings.homeRankingSettings.disabled),
        findsOneWidget,
      );
    });

    testWidgets('last enabled source switch is disabled', (tester) async {
      settings.disabledHomeRankingSources = 'bilibili,youtube';

      await _pumpPage(tester, repository);
      await tester.pump();

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[0].value, isFalse);
      expect(switches[0].onChanged, isNotNull);
      expect(switches[1].value, isFalse);
      expect(switches[1].onChanged, isNotNull);
      expect(switches[2].value, isTrue);
      expect(switches[2].onChanged, isNull);

      await tester.tap(find.byType(Switch).at(2));
      await tester.pump();

      expect(repository.settings.disabledHomeRankingSourcesSet, {
        'bilibili',
        'youtube',
      });
      expect(find.text(t.settings.homeRankingSettings.enabled), findsOneWidget);
    });

    testWidgets('reorder updates the persisted source priority',
        (tester) async {
      await _pumpPage(tester, repository);
      await tester.pump();

      await tester.drag(
        find.byIcon(Icons.drag_handle).first,
        const Offset(0, 220),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        repository.settings.homeRankingSourcePriorityList,
        ['youtube', 'netease', 'bilibili'],
      );
    });

    testWidgets('source rows match the non-tappable lyrics ordering style',
        (tester) async {
      await _pumpPage(tester, repository);
      await tester.pump();

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();

      expect(tiles, hasLength(3));
      expect(tiles.map((tile) => tile.onTap), everyElement(isNull));
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    });

    testWidgets('SettingsPage entry opens home ranking settings route',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: RoutePaths.settings,
        routes: [
          GoRoute(
            path: RoutePaths.settings,
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: RoutePaths.homeRankingSettings,
            builder: (context, state) => const HomeRankingSettingsPage(),
          ),
        ],
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWith((ref) => repository),
              refreshSettingsProvider.overrideWith(
                (ref) => _FakeRefreshSettingsNotifier(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SettingsPage), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.settings.homeRankingSettings.title));
      await tester.pumpAndSettle();

      expect(find.byType(HomeRankingSettingsPage), findsOneWidget);
      expect(router.canPop(), isTrue);
      expect(find.text(t.settings.homeRankingSettings.hint), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  SettingsRepository repository,
) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const MaterialApp(home: HomeRankingSettingsPage()),
      ),
    ),
  );
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.settings) : super(_FakeIsar());

  final Settings settings;
  Future<Settings> Function()? getOverride;

  @override
  Future<Settings> get() => getOverride?.call() ?? Future.value(settings);

  @override
  Future<Settings> update(void Function(Settings settings) mutate) async {
    mutate(settings);
    return settings;
  }
}

class _FakeIsar extends Fake implements Isar {}

class _FakeRefreshSettingsNotifier extends StateNotifier<RefreshSettingsState>
    implements RefreshSettingsNotifier {
  _FakeRefreshSettingsNotifier()
      : super(const RefreshSettingsState(isLoading: false));

  @override
  Future<void> setRankingRefreshInterval(int minutes) async {}

  @override
  Future<void> setRadioRefreshInterval(int minutes) async {}
}
