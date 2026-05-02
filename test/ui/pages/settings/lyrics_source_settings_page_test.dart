import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/repository_providers.dart';
import 'package:fmp/ui/pages/settings/lyrics_source_settings_page.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsSourceSettingsPage', () {
    late Settings settings;
    late _FakeSettingsRepository repository;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      LocaleSettings.setLocale(AppLocale.en);
      settings = Settings();
      repository = _FakeSettingsRepository(settings);
    });

    testWidgets(
      'shows plain lyrics auto-match switch on page instead of AI dialog',
      (tester) async {
        await _pumpPage(tester, repository);
        await tester.pump();

        final plainLyricsLabel =
            t.settings.lyricsSourceSettings.allowPlainLyricsAutoMatch;
        expect(find.text(plainLyricsLabel), findsOneWidget);
        expect(
          find.text(t.settings.lyricsSourceSettings.hint),
          findsNothing,
          reason: 'the plain lyrics switch replaces the old top hint text',
        );
        expect(tester.widget<Divider>(find.byType(Divider)).height, 1);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        expect(repository.settings.allowPlainLyricsAutoMatch, isTrue);

        await tester.tap(find.byIcon(Icons.smart_toy_outlined));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(plainLyricsLabel), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(plainLyricsLabel),
          ),
          findsNothing,
        );
      },
    );
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
        child: const MaterialApp(home: LyricsSourceSettingsPage()),
      ),
    ),
  );
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository(this.settings) : super(_FakeIsar());

  final Settings settings;

  @override
  Future<Settings> get() async => settings;

  @override
  Future<Settings> update(void Function(Settings settings) mutate) async {
    mutate(settings);
    return settings;
  }
}

class _FakeIsar extends Fake implements Isar {}
