import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 播放列、播放頁與右側面板的直播版（ADR 0031 §決定 7、M3 design §9.4）：沒有進度條，
// 有停止鈕、主播、人數；三種階段（重新連線中、直播已結束、查詢失敗）看得出來；佇列頁
// 照常顯示原佇列、沒有一列在播；快捷鍵在直播時不動上一首、下一首、seek。

const _target = LiveTarget(
  pluginId: 'fmp-test',
  roomId: 'r',
  title: 'Room r',
  hostName: 'Host r',
);

final _barTitle = find
    .descendant(of: find.byKey(PlayerBar.titleKey), matching: find.byType(Text))
    .first;

const _stop = 'Stop listening';
const _previous = 'Previous (Ctrl+←)';
const _next = 'Next (Ctrl+→)';

/// 直播間的狀態：`liveStatus` 回這個（`live-info` 與提前結束時問）。
LiveRoom _room({
  LiveRoomStatus status = LiveRoomStatus.live,
  int? online = 1500,
}) => LiveRoom(
  roomId: 'r',
  title: 'Room r, later',
  hostName: 'Host r',
  status: status,
  online: online,
);

/// 先播佇列裡的兩首，再收聽直播間 `r`。
Future<ShellHarness> _listening(
  WidgetTester tester, {
  Size size = const Size(1000, 800),
  bool collapsePanel = true,
}) async {
  final h = ShellHarness(live: true);
  h.plugin
    ..onResolveLive = ((request) => [candidate('${request.roomId}.flv')])
    ..onLiveStatus = ((_) => _room());
  await h.pumpShell(tester, size: size, collapsePanel: collapsePanel);
  await h.play(tester, [summary('a'), summary('b')]);
  await tester.pump(const Duration(milliseconds: 200));
  unawaited(h.controller.playLive(_target));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(h.controller.state, isA<Playing>());
  return h;
}

/// `live-info` 到期一次：更新標題與人數。
Future<void> _liveInfo(WidgetTester tester, ShellHarness h) async {
  await h.liveInfoJob!();
  await tester.pump();
}

Finder _inBar(Finder finder) =>
    find.descendant(of: find.byType(PlayerBar), matching: finder);

String _badge(WidgetTester tester, Finder scope) => tester
    .widget<StatusTag>(
      find.descendant(
        of: find.descendant(of: scope, matching: find.byType(LiveBadge)),
        matching: find.byType(StatusTag),
      ),
    )
    .text;

Future<void> _openPage(WidgetTester tester) async {
  await tester.tap(_barTitle);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(PlayerPage), findsOneWidget);
}

void main() {
  group('the player bar', () {
    for (final width in const [400.0, 700.0, 1000.0]) {
      testWidgets('at $width: no progress bar or previous/next; a stop '
          'button, the host and the viewers', (tester) async {
        final h = await _listening(tester, size: Size(width, 800));
        await _liveInfo(tester, h);

        expect(_inBar(find.byType(ProgressRow)), findsNothing);
        expect(_inBar(find.byTooltip(_previous)), findsNothing);
        expect(_inBar(find.byTooltip(_next)), findsNothing);
        expect(_inBar(find.byTooltip(_stop)), findsOneWidget);
        expect(_inBar(find.text('Host r')), findsOneWidget);
        expect(_inBar(find.text('Room r, later')), findsOneWidget);
        expect(_inBar(find.text('1.5K watching')), findsOneWidget);
        expect(_badge(tester, find.byType(PlayerBar)), 'Live');
        expect(_inBar(find.textContaining('Listened')), findsOneWidget);
      });
    }

    testWidgets('the stop button goes back to the queue', (tester) async {
      final h = await _listening(tester);

      await tester.tap(_inBar(find.byTooltip(_stop)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(h.controller.queue.live, isNull);
      expect(h.controller.queue.current?.title, 'Song a');
      expect(_inBar(find.byType(ProgressRow)), findsOneWidget);
      expect(_inBar(find.byType(LiveBadge)), findsNothing);
    });

    testWidgets('reconnecting, ended and a failed status check are told '
        'apart', (tester) async {
      final h = await _listening(tester);

      // 提前結束、仍在直播：等 1 秒重連。
      h.backend.endEarly();
      await tester.pump();
      await tester.pump();
      expect(h.controller.state, isA<Retrying>());
      expect(_inBar(find.textContaining('Reconnecting')), findsOneWidget);
      expect(_badge(tester, find.byType(PlayerBar)), 'Live');
      await tester.pump(const Duration(seconds: 2));
      expect(h.controller.state, isA<Playing>());

      // 提前結束、沒在直播：直播已結束。
      h.plugin.onLiveStatus = (_) => _room(status: LiveRoomStatus.offline);
      h.backend.endEarly();
      await tester.pump();
      await tester.pump();
      expect(h.controller.live?.phase, LivePhase.ended);
      expect(_badge(tester, find.byType(PlayerBar)), 'Live ended');
      expect(_inBar(find.textContaining('Listened')), findsNothing);

      // 再播一次，提前結束時查不到：查詢失敗（不是已結束）。
      unawaited(h.controller.play());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      h.plugin.onLiveStatus = (_) => throw NetworkError(pluginId: 'fmp-test');
      h.backend.endEarly();
      await tester.pump();
      await tester.pump();
      expect(h.controller.live?.phase, LivePhase.statusFailed);
      expect(_badge(tester, find.byType(PlayerBar)), 'Status check failed');
    });

    testWidgets('a pause stops the stream and says so', (tester) async {
      final h = await _listening(tester);

      await tester.tap(_inBar(find.byTooltip('Pause (Space)')));
      await tester.pump();

      expect(h.controller.state, isA<Paused>());
      expect(_inBar(find.textContaining('Stopped')), findsOneWidget);
    });
  });

  group('the player page', () {
    for (final size in const [Size(400, 800), Size(1000, 800)]) {
      testWidgets('at ${size.width}: the live version', (tester) async {
        final h = await _listening(tester, size: size);
        await _liveInfo(tester, h);
        await _openPage(tester);

        final page = find.byType(PlayerPage);
        Finder inPage(Finder finder) =>
            find.descendant(of: page, matching: finder);
        expect(inPage(find.byType(ProgressRow)), findsNothing);
        expect(inPage(find.byTooltip(_previous)), findsNothing);
        expect(inPage(find.byTooltip(_next)), findsNothing);
        expect(inPage(find.byTooltip('Shuffle (Ctrl+S)')), findsNothing);
        expect(inPage(find.byTooltip(_stop)), findsOneWidget);
        expect(inPage(find.text('Room r, later')), findsWidgets);
        expect(inPage(find.text('Host r')), findsWidgets);
        expect(inPage(find.text('1.5K watching')), findsWidgets);
        expect(_badge(tester, find.byType(PlayerPage).first), 'Live');

        // 停止：回到佇列，頁面換回曲目版、不關。
        await tester.tap(inPage(find.byTooltip(_stop)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(page, findsOneWidget);
        expect(inPage(find.byType(ProgressRow)), findsOneWidget);
      });
    }

    // 開著播放頁（或 compact 的佇列面板）時開始收聽：`current` 變成 `null`，頁面與面板不能當成
    // 「沒有在播」自己關掉。
    for (final size in const [Size(400, 800), Size(1000, 800)]) {
      testWidgets('at ${size.width}: going live with the page open keeps it '
          'open', (tester) async {
        final h = ShellHarness(live: true);
        h.plugin.onResolveLive = (request) => [
          candidate('${request.roomId}.flv'),
        ];
        await h.pumpShell(tester, size: size, collapsePanel: true);
        await h.play(tester, [summary('a'), summary('b')]);
        await tester.pump(const Duration(milliseconds: 200));
        await _openPage(tester);

        unawaited(h.controller.playLive(_target));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(PlayerPage), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PlayerPage),
            matching: find.byType(LiveFacts),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('the queue page shows the queue with no row playing', (
      tester,
    ) async {
      final h = await _listening(tester);
      await h.openQueue(tester);

      final rows = tester.widgetList<ListTile>(
        find.descendant(
          of: find.byType(QueueView),
          matching: find.byType(ListTile),
        ),
      );
      expect(rows, hasLength(2));
      expect(rows.where((row) => row.selected), isEmpty);
    });

    testWidgets('the details tab is the room', (tester) async {
      final h = await _listening(tester);
      await _liveInfo(tester, h);
      await _openPage(tester);
      await tester.tap(find.widgetWithText(Tab, 'Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(LiveDetails), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LiveDetails),
          matching: find.text('Test Source'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('it closes when nothing is left to play', (tester) async {
      final h = ShellHarness(live: true);
      h.plugin.onResolveLive = (request) => [
        candidate('${request.roomId}.flv'),
      ];
      await h.pumpShell(tester);
      // 佇列是空的也能收聽直播；播放列與播放頁照樣有。
      unawaited(h.controller.playLive(_target));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await _openPage(tester);

      unawaited(h.controller.stopLive());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerPage), findsNothing);
      // 佇列是空的：播放列也不佔位置了。
      expect(find.byType(PlayerBar), findsNothing);
    });
  });

  group('the now playing panel', () {
    testWidgets('shows the room with a stop button', (tester) async {
      final h = await _listening(tester, collapsePanel: false);
      await _liveInfo(tester, h);

      final panel = find.byType(NowPlayingPanel);
      Finder inPanel(Finder finder) =>
          find.descendant(of: panel, matching: finder);
      expect(inPanel(find.byType(LiveDetails)), findsOneWidget);
      expect(inPanel(find.text('Host r')), findsOneWidget);
      expect(inPanel(find.text('1.5K watching')), findsOneWidget);
      expect(inPanel(find.byType(ProgressRow)), findsNothing);
      expect(_badge(tester, panel), 'Live');

      await tester.tap(inPanel(find.text(_stop)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.live, isNull);
      expect(inPanel(find.byType(LiveDetails)), findsNothing);
      expect(inPanel(find.text('Song a')), findsOneWidget);
    });
  });

  group('shortcuts while listening', () {
    Future<bool> chord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
    }) async {
      await tester.sendKeyDownEvent(modifier);
      final handled = await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      return handled;
    }

    testWidgets('previous, next, seek, shuffle and repeat do nothing', (
      tester,
    ) async {
      final h = await _listening(tester);
      final opened = h.backend.openedAt.length;
      final queue = h.controller.queue;

      // 按鍵被接下、不做事（不往上傳給 App 根的預設捲動鍵）：直播時停用 action 的話
      // `Shortcuts` 不處理，`handled` 是假。
      for (final (key, modifier) in [
        (LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.controlLeft),
        (LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.controlLeft),
        (LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.shiftLeft),
        (LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.shiftLeft),
        (LogicalKeyboardKey.keyS, LogicalKeyboardKey.controlLeft),
        (LogicalKeyboardKey.keyR, LogicalKeyboardKey.controlLeft),
      ]) {
        expect(
          await chord(tester, key, modifier: modifier),
          isTrue,
          reason: '$modifier+$key is handled',
        );
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(h.controller.queue.live?.target, _target);
      expect(h.controller.queue.shuffleEnabled, queue.shuffleEnabled);
      expect(h.controller.queue.loopMode, queue.loopMode);
      expect(h.backend.openedAt, hasLength(opened));
      expect(h.controller.state, isA<Playing>());
    });

    testWidgets('space stops the stream and plays it again', (tester) async {
      final h = await _listening(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.controller.state, isA<Paused>());

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.state, isA<Playing>());
      // 暫停就是停止串流：再播放重新取流。
      expect(h.plugin.liveRequests, hasLength(2));
    });

    testWidgets('the same keys still work on the queue after stopping', (
      tester,
    ) async {
      final h = await _listening(tester);
      unawaited(h.controller.stopLive());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(await chord(tester, LogicalKeyboardKey.arrowRight), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.currentIndex, 1);
    });
  });
}
