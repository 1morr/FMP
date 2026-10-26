import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/thin_progress_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_audio_backend.dart';
import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

/// 播放列單獨放在視窗底部，寬度就是視窗寬度；放在 `Column` 裡讓它拿到不限高的約束，同外殼。
Future<ShellHarness> pumpBar(
  WidgetTester tester, {
  double width = 1000,
  ShellHarness? harness,
}) async {
  final h = harness ?? ShellHarness();
  await h.pumpApp(
    tester,
    const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [WindowClassScope(child: PlayerBar())],
        ),
      ),
    ),
    size: Size(width, 600),
  );
  return h;
}

/// 滑鼠移到播放列上（進度細線變粗、出現「位置 / 時長」）。
Future<TestGesture> hoverBar(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byType(PlayerBar)));
  // 一幀開始動畫，一幀走完。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return mouse;
}

/// 進度細線的語意值（位置的文字）；要先 `tester.ensureSemantics()`。
String progressValue(WidgetTester tester) =>
    tester.getSemantics(find.bySemanticsLabel('Playback position')).value;

/// 進度細線上 [fraction]（0–1）處的畫面座標；細線貼在播放列最上緣。
Offset onThinBar(WidgetTester tester, double fraction) {
  final rect = tester.getRect(find.byType(ThinProgressBar));
  return Offset(rect.left + rect.width * fraction, rect.top + 1);
}

const _speakers = OutputDevice(id: 'wasapi/{a}', name: 'Speakers');
const _headphones = OutputDevice(id: 'wasapi/{b}', name: 'Headphones');
const _usb = OutputDevice(id: 'wasapi/{c}', name: 'USB DAC');

void main() {
  const play = 'Play (Space)';
  const pause = 'Pause (Space)';
  const previous = 'Previous (Ctrl+←)';
  const next = 'Next (Ctrl+→)';
  const shuffle = 'Shuffle (Ctrl+S)';
  const loopOff = 'Repeat: off (Ctrl+R)';
  const more = 'More';
  const mute = 'Mute';
  const unmute = 'Unmute';
  const volumeIcon = 'Volume (Ctrl+↑/↓)';
  const outputDevice = 'Output device';
  const panelHide = 'Hide the now playing panel';

  testWidgets('takes no space while nothing is queued', (tester) async {
    await pumpBar(tester);

    expect(tester.getSize(find.byType(PlayerBar)).height, 0);
  });

  // ADR 0024 §決定 5、design §9.2：三段的控制項集合與邊界。
  group('controls per width', () {
    Set<String?> tooltipsOf(WidgetTester tester) => {
      for (final button in tester.widgetList<IconButton>(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.byType(IconButton),
        ),
      ))
        button.tooltip,
    };

    for (final (width, controls, sliders) in [
      (360.0, {pause, next}, 0),
      (599.0, {pause, next}, 0),
      (600.0, {previous, pause, next, volumeIcon, more}, 0),
      (839.0, {previous, pause, next, volumeIcon, more}, 0),
      (840.0, {shuffle, previous, pause, next, loopOff, panelHide, mute}, 1),
      (1600.0, {shuffle, previous, pause, next, loopOff, panelHide, mute}, 1),
    ]) {
      testWidgets('$width wide: $controls; the title keeps 160dp', (
        tester,
      ) async {
        final h = await pumpBar(tester, width: width);
        await h.play(tester, [summary('a'), summary('b')]);
        await tester.pump(const Duration(milliseconds: 100));

        expect(tooltipsOf(tester), controls);
        // 只有 expanded 以上的音量滑桿（medium 的在彈出的選單裡）；進度是頂端的細線，不是 Slider。
        expect(find.byType(Slider), findsNWidgets(sliders));
        expect(
          tester.getSize(find.byKey(PlayerBar.titleKey)).width,
          greaterThanOrEqualTo(160),
        );
        expect(find.text('Song a'), findsOneWidget);
        expect(find.text('Uploader a'), findsOneWidget);
      });
    }

    // 平台宣告能選輸出裝置（Windows）才有輸出裝置鈕；Android 沒有。
    for (final (width, controls) in [
      (599.0, {pause, next}),
      (600.0, {previous, pause, next, volumeIcon, more}),
      (839.0, {previous, pause, next, volumeIcon, more}),
      (
        840.0,
        {
          shuffle,
          previous,
          pause,
          next,
          loopOff,
          panelHide,
          outputDevice,
          mute,
        },
      ),
    ]) {
      testWidgets('$width wide with output device selection: $controls', (
        tester,
      ) async {
        final h = ShellHarness(
          outputDeviceSelection: true,
          outputDevices: FakeOutputDevices(const [_speakers]),
        );
        await pumpBar(tester, width: width, harness: h);
        await h.play(tester, [summary('a'), summary('b')]);
        await tester.pump(const Duration(milliseconds: 100));

        expect(tooltipsOf(tester), controls);
        expect(
          tester.getSize(find.byKey(PlayerBar.titleKey)).width,
          greaterThanOrEqualTo(160),
        );
      });
    }

    testWidgets('without output device selection (Android) there is no '
        'output device in the menu either', (tester) async {
      final h = await pumpBar(tester, width: 720);
      await h.play(tester, [summary('a')]);

      await tester.tap(find.byTooltip(more));
      await tester.pump();
      expect(find.text(outputDevice), findsNothing);
    });
  });

  // ADR 0018 §決定 7、design §5.3：曲名下面那一行先寫狀態。三種寬度都看得到、
  // 不溢出。
  group('status labels', () {
    Finder inBar(String text) => find.descendant(
      of: find.byType(PlayerBar),
      matching: find.textContaining(text),
    );

    for (final width in [360.0, 600.0, 1000.0]) {
      testWidgets('$width wide: retrying', (tester) async {
        final h = ShellHarness();
        h.plugin.respond = (_) => throw NetworkError(pluginId: 'fmp-test');
        await pumpBar(tester, width: width, harness: h);
        await h.play(tester, [summary('a')]);

        expect(h.controller.state, isA<Retrying>());
        expect(inBar('Retrying'), findsOneWidget);
        expect(inBar('Uploader a'), findsOneWidget);
      });

      testWidgets('$width wide: waiting for the network', (tester) async {
        final h = ShellHarness();
        h.plugin.respond = (_) => throw NetworkError(pluginId: 'fmp-test');
        await pumpBar(tester, width: width, harness: h);
        await h.setNetwork(tester, NetworkStatus.noInterface);
        await h.play(tester, [summary('a')]);

        expect(inBar('Waiting for the network'), findsOneWidget);
        expect(inBar('Retrying'), findsNothing);
      });

      testWidgets('$width wide: preview', (tester) async {
        final h = ShellHarness();
        h.plugin.previewOnly = (_) => true;
        await pumpBar(tester, width: width, harness: h);
        await tester.runAsync(
          () => h
              .container(tester)
              .read(playbackPreferencesProvider.notifier)
              .setSkipPreviewClips(false),
        );
        await h.loadSettings(tester);
        await h.play(tester, [summary('a')]);
        await tester.pump(const Duration(milliseconds: 100));

        expect(h.controller.state, isA<Playing>());
        expect(inBar('Preview'), findsOneWidget);
      });
    }

    testWidgets('nothing extra while playing normally', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));

      for (final label in ['Retrying', 'Waiting for the network', 'Preview']) {
        expect(inBar(label), findsNothing);
      }
      expect(inBar('Uploader a'), findsOneWidget);
    });
  });

  group('state from the controller', () {
    testWidgets('loading shows a labelled spinner; pressing it pauses', (
      tester,
    ) async {
      final pending = Completer<List<StreamCandidate>>();
      final h = ShellHarness();
      h.plugin.respond = (_) => pending.future;
      await pumpBar(tester, harness: h);
      await h.play(tester, [summary('a')]);

      expect(h.controller.state, isA<Loading>());
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.byTooltip(pause), findsOneWidget);

      await tester.tap(find.byTooltip(pause));
      await tester.pump();
      pending.complete([candidate('a.m4a')]);
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, isA<Paused>());
      expect(find.byTooltip(play), findsOneWidget);
    });

    testWidgets('play, pause, previous and next go to the controller', (
      tester,
    ) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.state, isA<Playing>());

      await tester.tap(find.byTooltip(pause));
      await tester.pump();
      expect(h.controller.state, isA<Paused>());
      await tester.tap(find.byTooltip(play));
      await tester.pump();
      expect(h.controller.state, isA<Playing>());

      await tester.tap(find.byTooltip(next));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.queue.currentIndex, 1);
      expect(find.text('Song b'), findsOneWidget);
      // 最後一首：下一首停用。
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.skip_next),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip(previous));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.controller.queue.currentIndex, 0);
    });

    testWidgets('dragging the progress line seeks on release', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));

      final gesture = await tester.startGesture(onThinBar(tester, 0.5));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      // 拖動中只改畫面，還沒 seek；把手上方浮著時間。
      expect(
        h.container(tester).read(playbackProgressProvider).value!.position,
        lessThan(const Duration(seconds: 5)),
      );
      expect(find.textContaining(' / 3:00'), findsOneWidget);
      await gesture.up();
      await tester.pump();

      // 從中間附近開始播：位置跳到約 1:30。
      await tester.pump(const Duration(milliseconds: 60));
      final position = h
          .container(tester)
          .read(playbackProgressProvider)
          .value!
          .position
          .inSeconds;
      expect(position, greaterThan(60));
      // 放開之後把手與時間收起。
      expect(find.textContaining(' / '), findsNothing);
    });

    testWidgets('tapping the line seeks to that point', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tapAt(onThinBar(tester, 0.75));
      await tester.pump(const Duration(milliseconds: 60));

      final position = h
          .container(tester)
          .read(playbackProgressProvider)
          .value!
          .position
          .inSeconds;
      expect(position, inInclusiveRange(130, 140), reason: '75% of 3:00');
    });

    testWidgets('the line is 2dp and grows to 6dp with a thumb and the time '
        'while the mouse is over the bar', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));

      double lineHeight() => tester
          .getSize(
            find.descendant(
              of: find.byType(ThinProgressBar),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .height;
      expect(lineHeight(), 2);
      expect(find.textContaining(' / '), findsNothing);

      final mouse = await hoverBar(tester);
      expect(lineHeight(), 6);
      expect(find.text('0:00 / 3:00'), findsOneWidget);

      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(lineHeight(), 2);
      expect(find.textContaining(' / '), findsNothing);
    });

    FocusNode lineFocus(WidgetTester tester) => tester
        .widget<Focus>(
          find
              .descendant(
                of: find.byType(ThinProgressBar),
                matching: find.byType(Focus),
              )
              .first,
        )
        .focusNode!;

    double lineHeightOf(WidgetTester tester) => tester
        .getSize(
          find.descendant(
            of: find.byType(ThinProgressBar),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .height;

    testWidgets('Tab reaches the line, which shows the 6dp state and a focus '
        'ring while focused', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));
      final node = lineFocus(tester);

      var tabs = 0;
      while (!node.hasFocus && tabs < 20) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        tabs++;
      }
      expect(node.hasFocus, isTrue, reason: 'in the tab order');
      await tester.pump(const Duration(milliseconds: 200));

      expect(lineHeightOf(tester), 6);
      expect(find.textContaining(' / '), findsOneWidget);
      final ring = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ThinProgressBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final border = (ring.foregroundDecoration! as BoxDecoration).border!;
      expect(
        (border as Border).top.color,
        Theme.of(tester.element(find.byType(ThinProgressBar)))
            .colorScheme
            .primary,
      );

      node.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(lineHeightOf(tester), 2);
    });

    testWidgets('the arrow keys seek by the Shift+arrow step', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 20));
      lineFocus(tester).requestFocus();
      await tester.pump();

      final before = h
          .container(tester)
          .read(playbackProgressProvider)
          .value!
          .position;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 60));
      final after = h
          .container(tester)
          .read(playbackProgressProvider)
          .value!
          .position;
      expect(after - before, greaterThanOrEqualTo(const Duration(seconds: 4)));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 60));
      final back = h
          .container(tester)
          .read(playbackProgressProvider)
          .value!
          .position;
      expect(back, lessThan(after - const Duration(seconds: 4)));
    });

    testWidgets('reduced motion grows the line at once', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pump();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(PlayerBar)));
      await tester.pump();

      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(ThinProgressBar),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .height,
        6,
      );
    });

    testWidgets('the line is a slider for screen readers: position as the '
        'value, increase and decrease by 10%', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 2));

      final node = tester.getSemantics(
        find.bySemanticsLabel('Playback position'),
      );
      expect(
        node,
        matchesSemantics(
          label: 'Playback position',
          value: '0:02',
          increasedValue: '0:20',
          decreasedValue: '0:00',
          isSlider: true,
          isFocusable: true,
          hasFocusAction: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );

      tester.semantics.increase(find.semantics.byLabel('Playback position'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        h.container(tester).read(playbackProgressProvider).value!.position,
        greaterThan(const Duration(seconds: 15)),
      );
      handle.dispose();
    });

    // M2 驗收（Android，2026-10-08）：臨時播放結束、佇列那首只載入不播時，
    // ExoPlayer 不回報位置；進度條曾停在臨時曲目最後的位置與時長。時長還沒回報
    // 時用曲目的（3:05），所以照樣能拖。
    testWidgets('a song loaded paused after a temporary play shows its own '
        'start and length, not the temporary track', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 15));
      unawaited(h.controller.pause());
      await tester.pump();
      unawaited(h.controller.playTemporary(summary('b').toTrackInfo()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(progressValue(tester), '0:02', reason: 'live progress');

      unawaited(h.controller.next());
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(h.controller.state, isA<Paused>());
      expect(h.controller.queue.current?.sourceId, 'a');
      // 預設倒退 10 秒：從 0:05 開始。
      expect(progressValue(tester), '0:05');
      await hoverBar(tester);
      expect(find.text('0:05 / 3:05'), findsOneWidget);
      handle.dispose();
    });
  });

  group('shuffle and loop', () {
    testWidgets('the buttons switch shuffle and cycle the loop mode', (
      tester,
    ) async {
      final h = await pumpBar(tester, width: 1000);
      await h.play(tester, [summary('a'), summary('b'), summary('c')]);

      await tester.tap(find.byTooltip(shuffle));
      await tester.pump();
      expect(h.controller.queue.shuffleEnabled, isTrue);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.shuffle))
            .isSelected,
        isTrue,
      );
      await tester.tap(find.byTooltip(shuffle));
      await tester.pump();
      expect(h.controller.queue.shuffleEnabled, isFalse);

      for (final (mode, tooltip, icon) in [
        (LoopMode.all, 'Repeat: all (Ctrl+R)', Icons.repeat),
        (LoopMode.one, 'Repeat: one (Ctrl+R)', Icons.repeat_one),
        (LoopMode.off, loopOff, Icons.repeat),
      ]) {
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is IconButton && (w.tooltip?.startsWith('Repeat') ?? false),
          ),
        );
        await tester.pump();
        expect(h.controller.queue.loopMode, mode);
        expect(find.byTooltip(tooltip), findsOneWidget);
        expect(find.widgetWithIcon(IconButton, icon), findsOneWidget);
      }
    });

    testWidgets('at medium width they are in the "more" menu', (tester) async {
      final h = await pumpBar(tester, width: 720);
      await h.play(tester, [summary('a'), summary('b')]);

      await tester.tap(find.byTooltip(more));
      await tester.pump();
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      expect(h.controller.queue.shuffleEnabled, isTrue);

      await tester.tap(find.byTooltip(more));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxMenuButton>(find.byType(CheckboxMenuButton))
            .value,
        isTrue,
      );
      await tester.tap(find.text('Repeat: off'));
      await tester.pump();
      expect(h.controller.queue.loopMode, LoopMode.all);
    });
  });

  group('volume', () {
    Finder volumeSlider() => find.byType(Slider);

    Future<void> dragVolume(WidgetTester tester, double dx) async {
      final gesture = await tester.startGesture(
        tester.getCenter(volumeSlider()),
      );
      await tester.pump();
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('dragging the slider sets the volume at once and unmutes', (
      tester,
    ) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      unawaited(h.controller.toggleMute());
      await tester.pump();
      await tester.pump();
      expect(h.controller.muted, isTrue);
      expect(find.byTooltip(unmute), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(volumeSlider()),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      // 還沒放開：音量已經套用。
      expect(h.controller.volume, lessThan(0.5));
      expect(h.backend.volume, h.controller.volume);
      expect(h.controller.muted, isFalse);
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip(mute), findsOneWidget);
    });

    testWidgets('a volume of 0 is not mute; mute is kept apart', (
      tester,
    ) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);

      await dragVolume(tester, -400);
      expect(h.controller.volume, 0);
      expect(h.controller.muted, isFalse);
      // 音量 0 時圖示是關閉的樣子，但按鈕仍是「靜音」（沒有靜音）。
      expect(find.byTooltip(mute), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      await dragVolume(tester, 400);
      expect(h.controller.volume, 1);
    });

    testWidgets('the mute button toggles mute and the icon follows', (
      tester,
    ) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      await tester.tap(find.byTooltip(mute));
      await tester.pump();
      expect(h.controller.muted, isTrue);
      expect(h.controller.volume, 1, reason: 'the volume is kept');
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      await tester.tap(find.byTooltip(unmute));
      await tester.pump();
      expect(h.controller.muted, isFalse);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      unawaited(h.controller.setVolume(0.3));
      await tester.pump();
      expect(find.byIcon(Icons.volume_down), findsOneWidget);
    });

    testWidgets('at medium width the icon opens a slider with mute inside; '
        'Esc closes it', (tester) async {
      final h = await pumpBar(tester, width: 720);
      await h.play(tester, [summary('a')]);
      expect(find.byType(Slider), findsNothing);

      await tester.tap(find.byTooltip(volumeIcon));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      await dragVolume(tester, -30);
      expect(h.controller.volume, lessThan(0.5));

      await tester.tap(find.byTooltip(mute));
      await tester.pump();
      expect(h.controller.muted, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a volume changed elsewhere moves the slider', (tester) async {
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);

      unawaited(h.controller.setVolume(0.25));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<Slider>(volumeSlider()).value, 25);
    });
  });

  group('output devices', () {
    Future<(ShellHarness, FakeOutputDevices)> pumpWithDevices(
      WidgetTester tester, {
      double width = 1000,
    }) async {
      final devices = FakeOutputDevices(const [_speakers, _headphones]);
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: devices,
      );
      await pumpBar(tester, width: width, harness: h);
      await h.play(tester, [summary('a')]);
      return (h, devices);
    }

    Finder device(String name) => find.widgetWithText(MenuItemButton, name);

    // 目前的打勾：項目的 leading 是看得見的勾。
    Finder check(String name) => find.descendant(
      of: device(name),
      matching: find.byWidgetPredicate(
        (w) => w is Visibility && w.visible && w.child is Icon,
      ),
    );

    testWidgets('the menu lists the system default and the devices; the '
        'current one is checked and a choice goes to the controller', (
      tester,
    ) async {
      final (h, devices) = await pumpWithDevices(tester);

      await tester.tap(find.byTooltip(outputDevice));
      await tester.pump();
      expect(device('System default'), findsOneWidget);
      expect(device('Speakers'), findsOneWidget);
      expect(device('Headphones'), findsOneWidget);
      expect(check('System default'), findsOneWidget);
      expect(check('Headphones'), findsNothing);

      await tester.tap(device('Headphones'));
      await tester.pump();
      expect(devices.selections, [_headphones]);
      expect(h.controller.outputDeviceState.selected, _headphones);

      await tester.tap(find.byTooltip(outputDevice));
      await tester.pump();
      expect(check('Headphones'), findsOneWidget);
      expect(check('System default'), findsNothing);

      await tester.tap(device('System default'));
      await tester.pump();
      expect(devices.selections, [_headphones, null]);
    });

    testWidgets('a device plugged in while the app runs shows up', (
      tester,
    ) async {
      final (_, devices) = await pumpWithDevices(tester);

      devices.list(const [_speakers, _headphones, _usb]);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip(outputDevice));
      await tester.pump();
      expect(device('USB DAC'), findsOneWidget);
    });

    testWidgets('at medium width the devices are a submenu of the "more" '
        'menu', (tester) async {
      final (h, devices) = await pumpWithDevices(tester, width: 720);

      await tester.tap(find.byTooltip(more));
      await tester.pump();
      await tester.tap(find.text(outputDevice));
      await tester.pump();
      expect(device('System default'), findsOneWidget);
      await tester.tap(device('Speakers'));
      await tester.pump();
      expect(devices.selections, [_speakers]);
      expect(h.controller.outputDeviceState.selected, _speakers);
    });
  });

  // 啟動恢復後還沒按播放：進度條與時間顯示恢復的位置（design §7.7）。
  group('after a restore', () {
    testWidgets('the progress shows the restored position and the duration, '
        'and dragging moves the start', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester);
      expect(
        h.controller.restore(
          tracks: [summary('a').toTrackInfo()],
          currentIndex: 0,
          loopMode: LoopMode.off,
          shuffle: false,
          position: const Duration(seconds: 83),
          volume: 1,
          muted: false,
        ),
        isTrue,
      );
      await tester.pump();
      await tester.pump();

      expect(h.controller.state, isA<Idle>());
      expect(progressValue(tester), '1:23');
      final mouse = await hoverBar(tester);
      expect(find.text('1:23 / 3:05'), findsOneWidget);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 200));

      // 細線 83/185 = 45% 的位置往左拖。
      final gesture = await tester.startGesture(onThinBar(tester, 0.45));
      await tester.pump();
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(h.controller.position, lessThan(const Duration(seconds: 83)));
      expect(progressValue(tester), formatDuration(h.controller.position));

      // 按播放從拖到的位置開始。
      final start = h.controller.position;
      await tester.tap(find.byTooltip(play));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.single, start);
      handle.dispose();
    });

    // design §7.7：恢復後先臨時播放，結束時佇列停著、按播放仍從恢復的位置開始；
    // 進度條也回到恢復的位置，不是臨時曲目最後的進度。
    testWidgets('after a temporary play ends the progress is the restored '
        'position again', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester);
      h.controller.restore(
        tracks: [summary('a').toTrackInfo()],
        currentIndex: 0,
        loopMode: LoopMode.off,
        shuffle: false,
        position: const Duration(seconds: 83),
        volume: 1,
        muted: false,
      );
      await tester.pump();
      await tester.pump();

      unawaited(h.controller.playTemporary(summary('b').toTrackInfo()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(progressValue(tester), '0:02', reason: 'live progress');

      unawaited(h.controller.next());
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, isA<Idle>());
      expect(h.controller.queue.current?.sourceId, 'a');
      expect(progressValue(tester), '1:23');
      await hoverBar(tester);
      expect(find.text('1:23 / 3:05'), findsOneWidget);

      await tester.tap(find.byTooltip(play));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.backend.openedAt.last, const Duration(seconds: 83));
      handle.dispose();
    });

    // 沒有恢復的 Idle：按播放從頭開始，不顯示上一首最後的進度，也不能拖（拖了
    // 按播放仍從頭）。
    testWidgets('idle without a restore shows the start, not the last song', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(progressValue(tester), '0:02');

      unawaited(h.controller.clear());
      await tester.pump();
      h.controller.addToQueue([
        summary('b', duration: const Duration(minutes: 4)).toTrackInfo(),
      ]);
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, isA<Idle>());

      expect(progressValue(tester), '0:00');
      // 不能拖：沒有把手與時間，點了也不 seek。
      await hoverBar(tester);
      expect(find.textContaining(' / '), findsNothing);
      await tester.tapAt(onThinBar(tester, 0.5));
      await tester.pump();
      expect(h.controller.position, Duration.zero);
      handle.dispose();
    });

    testWidgets('an unknown duration keeps the bar as it was', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester);
      h.controller.restore(
        tracks: [
          const TrackSummary(
            sourceTypeId: 'fmp-test',
            sourceId: 'x',
            title: 'Song x',
          ).toTrackInfo(),
        ],
        currentIndex: 0,
        loopMode: LoopMode.off,
        shuffle: false,
        position: const Duration(seconds: 83),
        volume: 1,
        muted: false,
      );
      await tester.pump();
      await tester.pump();

      expect(progressValue(tester), '0:00');
      await hoverBar(tester);
      expect(find.textContaining(' / '), findsNothing);
      handle.dispose();
    });
  });

  // tooltip 是只有圖示的按鈕唯一的名稱：再給 Icon.semanticLabel 會念成「X. X」。
  group('semantics', () {
    testWidgets('an icon-only button is named once, by its tooltip', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = ShellHarness(
        outputDeviceSelection: true,
        outputDevices: FakeOutputDevices(const [_speakers]),
      );
      await pumpBar(tester, width: 1000, harness: h);
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.pump(const Duration(milliseconds: 100));

      final buttons = tester.widgetList<IconButton>(
        find.descendant(
          of: find.byType(PlayerBar),
          matching: find.byType(IconButton),
        ),
      );
      expect(buttons, hasLength(8));
      for (final button in buttons) {
        final tooltip = button.tooltip!;
        // 名稱只有 tooltip 一份：Icon 再給 semanticLabel 的話標籤也有字，輔助技術
        // 會念成「X. X」。
        final node = tester.getSemantics(find.byWidget(button));
        expect(node.tooltip, tooltip);
        expect(node.label, isEmpty, reason: tooltip);
      }
      handle.dispose();
    });

    // 曲名與封面那一塊是開播放頁的按鈕：名稱是曲名與上傳者，「開啟播放頁」是提示。
    testWidgets('the title area is a button that opens the player', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await pumpBar(tester, width: 1000);
      await h.play(tester, [summary('a')]);
      await tester.pump(const Duration(milliseconds: 100));

      final node = tester.getSemantics(
        find
            .ancestor(of: find.text('Song a'), matching: find.byType(InkWell))
            .first,
      );
      expect(
        node,
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          label: 'Song a\nUploader a',
          hint: 'Open the player',
        ),
      );
      handle.dispose();
    });
  });
}
