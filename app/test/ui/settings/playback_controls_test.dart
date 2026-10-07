import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/stream_preferences.dart';
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

  /// 倒退秒數有兩列（臨時播放回佇列在前、重啟恢復在後）：[restart] 取後一列。
  Finder chipFinder(String label, {bool restart = false}) {
    final chips = find.widgetWithText(ChoiceChip, label);
    return restart ? chips.last : chips.first;
  }

  ChoiceChip chip(WidgetTester tester, String label, {bool restart = false}) =>
      tester.widget<ChoiceChip>(chipFinder(label, restart: restart));

  testWidgets('unset fields show the defaults and say so', (tester) async {
    await openPlayback(tester);

    expect(tester.widget<SwitchListTile>(remember).value, isTrue);
    expect(tester.widget<SwitchListTile>(skipPreviews).value, isTrue);
    expect(find.byType(ChoiceChip), findsNWidgets(3 + 2 + 6 + 6 + 4));
    expect(chip(tester, 'High (default)').selected, isTrue);
    expect(chip(tester, 'Medium').selected, isFalse);
    expect(chip(tester, 'Low').selected, isFalse);
    expect(chip(tester, 'Opus first (default)').selected, isTrue);
    expect(chip(tester, 'AAC first').selected, isFalse);
    expect(chip(tester, '10 s (default)').selected, isTrue);
    for (final other in ['No rewind', '3 s', '5 s', '15 s', '30 s']) {
      expect(chip(tester, other).selected, isFalse);
    }
    // 重啟恢復的倒退預設 0 秒。
    expect(chip(tester, 'No rewind (default)', restart: true).selected, isTrue);
    for (final other in ['3 s', '5 s', '10 s', '15 s', '30 s']) {
      expect(chip(tester, other, restart: true).selected, isFalse);
    }
    // 播放歷史保留筆數預設 10,000。
    expect(chip(tester, '10,000 entries (default)').selected, isTrue);
    for (final other in ['1,000 entries', '5,000 entries', '50,000 entries']) {
      expect(chip(tester, other).selected, isFalse);
    }
  });

  testWidgets('choosing a play history limit writes only that field', (
    tester,
  ) async {
    final h = await openPlayback(tester);

    await tester.ensureVisible(chipFinder('1,000 entries'));
    await tester.tap(chipFinder('1,000 entries'));
    await h.loadSettings(tester);

    expect(
      await stored(tester, h),
      const PlaybackSettings(playHistoryLimit: 1000),
    );
    expect(chip(tester, '1,000 entries').selected, isTrue);
    expect(
      find.text('10,000 entries (default)'),
      findsNothing,
      reason: 'no longer the default',
    );
    expect(chip(tester, '10,000 entries').selected, isFalse);
  });

  testWidgets('choosing writes only that field', (tester) async {
    final h = await openPlayback(tester);

    await tester.tap(chipFinder('3 s'));
    await h.loadSettings(tester);
    expect(
      await stored(tester, h),
      const PlaybackSettings(tempPlayRewindSeconds: 3),
    );
    expect(chip(tester, '3 s').selected, isTrue);
    expect(
      find.text('10 s (default)'),
      findsNothing,
      reason: 'no longer the default',
    );

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

  testWidgets('choosing a quality or a format writes only that field', (
    tester,
  ) async {
    final h = await openPlayback(tester);

    await tester.tap(find.text('Low'));
    await h.loadSettings(tester);
    expect(
      await stored(tester, h),
      const PlaybackSettings(audioQuality: AudioQuality.low),
    );
    expect(chip(tester, 'Low').selected, isTrue);
    expect(find.text('High'), findsOneWidget, reason: 'no longer the default');

    await tester.tap(find.text('AAC first'));
    await h.loadSettings(tester);
    expect(
      await stored(tester, h),
      const PlaybackSettings(
        audioQuality: AudioQuality.low,
        audioFormatPriority: AudioFormatPriority.aacFirst,
      ),
    );
    expect(chip(tester, 'AAC first').selected, isTrue);
    expect(chip(tester, 'Opus first').selected, isFalse);
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

  testWidgets('choosing a restart rewind writes only that field', (
    tester,
  ) async {
    final h = await openPlayback(tester);

    await tester.ensureVisible(chipFinder('15 s', restart: true));
    await tester.tap(chipFinder('15 s', restart: true));
    await h.loadSettings(tester);

    expect(
      await stored(tester, h),
      const PlaybackSettings(restartRewindSeconds: 15),
    );
    expect(chip(tester, '15 s', restart: true).selected, isTrue);
    expect(
      chip(tester, '15 s').selected,
      isFalse,
      reason: 'the temporary-play rewind is a separate setting',
    );
    expect(
      find.text('No rewind (default)'),
      findsNothing,
      reason: 'no longer the default',
    );
  });

  testWidgets('the restart rewind is disabled while the position is not '
      'remembered', (tester) async {
    final h = await openPlayback(tester);
    await tester.tap(remember);
    await h.loadSettings(tester);

    expect(chip(tester, '5 s', restart: true).onSelected, isNull);
    expect(
      chip(tester, 'No rewind (default)', restart: true).selected,
      isTrue,
      reason: 'kept',
    );
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

  testWidgets('a quality and a format chosen here go to the plugin', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.text('Playback'));
    await h.loadSettings(tester);
    await tester.tap(find.text('Low'));
    await h.loadSettings(tester);
    await tester.tap(find.text('AAC first'));
    await h.loadSettings(tester);

    await h.play(tester, [summary('a')]);

    final request = h.plugin.requests.single;
    expect(request.toJson()['quality'], 'low');
    // ShellHarness 的平台只有 mp4/aac：格式偏好不會加進平台沒有的編碼。
    expect([for (final f in request.formats) f.codec], ['aac']);
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
    await tester.tap(chipFinder('3 s'));
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
