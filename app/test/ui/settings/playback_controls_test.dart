import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/ui/settings/playback_controls.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  /// 開設定頁的「播放」組，等資料庫的值讀出來。
  Future<ShellHarness> openPlayback(WidgetTester tester) async {
    final h = ShellHarness();
    await h.pumpApp(
      tester,
      const SingleChildScrollView(child: PlaybackControls()),
    );
    await h.loadSettings(tester);
    return h;
  }

  Future<PlaybackSettings> stored(WidgetTester tester, ShellHarness h) async =>
      (await tester.runAsync(
        () =>
            h.container(tester).read(playbackSettingsRepositoryProvider).read(),
      ))!;

  final remember = find.widgetWithText(
    SwitchListTile,
    'Remember playback position',
  );
  final skipPreviews = find.widgetWithText(
    SwitchListTile,
    'Skip preview clips',
  );

  ChoiceChip chip(WidgetTester tester, String label) =>
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

  testWidgets('unset fields show the defaults and say so', (tester) async {
    await openPlayback(tester);

    expect(tester.widget<SwitchListTile>(remember).value, isTrue);
    expect(tester.widget<SwitchListTile>(skipPreviews).value, isTrue);
    expect(find.byType(ChoiceChip), findsNWidgets(6));
    expect(chip(tester, '10 s (default)').selected, isTrue);
    for (final other in ['No rewind', '3 s', '5 s', '15 s', '30 s']) {
      expect(chip(tester, other).selected, isFalse);
    }
  });

  testWidgets('choosing writes only that field', (tester) async {
    final h = await openPlayback(tester);

    await tester.tap(find.text('3 s'));
    await h.loadSettings(tester);
    expect(
      await stored(tester, h),
      const PlaybackSettings(tempPlayRewindSeconds: 3),
    );
    expect(chip(tester, '3 s').selected, isTrue);
    expect(find.text('10 s'), findsOneWidget, reason: 'no longer the default');

    await tester.tap(remember);
    await h.loadSettings(tester);
    expect(
      await stored(tester, h),
      const PlaybackSettings(rememberPosition: false, tempPlayRewindSeconds: 3),
    );

    await tester.ensureVisible(skipPreviews);
    await tester.tap(skipPreviews);
    await h.loadSettings(tester);
    expect(
      await stored(tester, h),
      const PlaybackSettings(
        rememberPosition: false,
        tempPlayRewindSeconds: 3,
        skipPreviewClips: false,
      ),
    );
    expect(tester.widget<SwitchListTile>(skipPreviews).value, isFalse);
  });

  testWidgets('the rewind is disabled while the position is not remembered', (
    tester,
  ) async {
    final h = await openPlayback(tester);
    await tester.tap(remember);
    await h.loadSettings(tester);

    expect(chip(tester, '10 s (default)').onSelected, isNull);
    expect(chip(tester, '10 s (default)').selected, isTrue, reason: 'kept');

    await tester.tap(remember);
    await h.loadSettings(tester);
    expect(chip(tester, '10 s (default)').onSelected, isNotNull);
  });

  testWidgets('the settings page lists appearance, playback and network', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);

    final groups = [
      for (final title in ['Appearance', 'Playback', 'Network'])
        tester.getCenter(find.widgetWithText(ListTile, title)).dy,
    ];
    expect(groups, orderedEquals([...groups]..sort()));
  });

  testWidgets('a rewind chosen here is used when a temporary play ends', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.text('Playback'));
    await h.loadSettings(tester);
    await tester.tap(find.text('3 s'));
    await h.loadSettings(tester);

    await h.play(tester, [summary('a')]);
    await tester.pump(const Duration(seconds: 30));
    unawaited(h.controller.playTemporary(summary('x').toTrackInfo()));
    await tester.pump(const Duration(seconds: 1));
    unawaited(h.controller.next());
    await tester.pump(const Duration(milliseconds: 100));

    expect(h.controller.queue.current?.sourceId, 'a');
    expect(h.backend.openedAt.last.inMilliseconds, closeTo(27000, 200));
  });
}
