import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 13 的實跑情境：背景播放與系統媒體控制。匿名搜一次「lofi」，前 2 首
/// 加入佇列（第 1 首開始播），把 App 送到背景（Android 按 Home、iOS 切到
/// 設定、macOS 縮到 Dock），確認聲音沒停（位置照走），再用系統的媒體控制
/// 按暫停、播放、下一首、上一首、拖進度，每一下讀回播放層的狀態。系統那一
/// 側的動作與讀回經宿主（`RealRun.system`、`tool/real_run_system.sh`），不動
/// Mac 的游標：
///
/// - Android：通知列的媒體通知（`uiautomator` 讀回、點按鈕與進度條）、
///   `dumpsys media_session`、媒體鍵（`cmd media_session dispatch`）。
/// - macOS：選單列的「正在播放」面板（`scripts/experiments/macos-now-playing/
///   np-panel.sh`，輔助使用）與合成的媒體鍵（`mediakey.sh`）。
/// - iOS 模擬器：沒有讀控制中心、送遠端指令的工具，只驗背景播放（事實 I5）。
///
///     dart run tool/real_run.dart -d android integration_test/real_run/media_run.dart
///
/// 解析兩首（spec 的「播一首」多一首：要有上一首、下一首）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('playback goes on in the background and the system media '
      'controls drive it', (tester) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final more = find.byTooltip(t.queue.more);
    await run.waitFor(more);
    await run.step('search');

    final container = ProviderScope.containerOf(tester.element(more.first));
    PlaybackState? playback() => container.read(playbackProvider);
    final first = searchResultTitle(tester, 0);
    final second = searchResultTitle(tester, 1);
    for (final index in [0, 1]) {
      await tester.tap(more.at(index));
      await run.waitFor(find.text(t.queue.actions.addToQueue));
      await tester.tap(find.text(t.queue.actions.addToQueue));
      await run.waitFor(
        find.byWidgetPredicate(
          (_) =>
              container.read(queueProvider).entries.length == index + 1 &&
              find.text(t.queue.actions.addToQueue).evaluate().isEmpty,
        ),
      );
    }
    await run.waitFor(
      find.byWidgetPredicate(
        (_) => playback()?.status == PlaybackStatus.playing,
      ),
      timeout: const Duration(seconds: 40),
    );
    await run.step('playing');

    /// 不 pump、只真的等，直到 [condition] 成立（App 在背景時不出幀）。
    Future<void> until(
      String what,
      bool Function(PlaybackState? state) condition, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!condition(playback())) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out waiting for $what; playback is ${playback()}');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
      }
      // ignore: avoid_print -- 每一下的結果留在實跑的輸出裡。
      print('[real run] $what: ${playback()}');
    }

    bool playingTitle(PlaybackState? s, String title) =>
        s?.track.title == title && s?.status == PlaybackStatus.playing;

    // 背景：10 秒後位置至少往前 8 秒，狀態仍是播放中。
    await run.system('background', 'background');
    final before = playback()!.position;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 10)),
    );
    final after = playback()!;
    // ignore: avoid_print -- 背景播放的讀回。
    print(
      '[real run] in the background (${WidgetsBinding.instance.lifecycleState})'
      ': $before -> ${after.position}, ${after.status.name}',
    );
    expect(after.status, PlaybackStatus.playing);
    expect(after.position - before, greaterThan(const Duration(seconds: 8)));

    if (Platform.isAndroid) {
      // 播放中 uiautomator 讀不到畫面（tool/real_run_system.sh 開頭），先用
      // 媒體鍵暫停再讀通知；之後的點按用讀到的按鈕位置。
      await run.system('session', 'session');
      await run.system('key-pause', 'dispatch', ['pause']);
      await until('paused by the media key', (s) {
        return s?.status == PlaybackStatus.paused;
      });
      final shade = await run.system('notification', 'notification');
      expect(shade, contains(first));

      await run.system('play', 'tap', ['Play']);
      await until('playing', (s) => playingTitle(s, first));
      await run.system('pause', 'tap', ['Play:Pause']);
      await until('paused', (s) => s?.status == PlaybackStatus.paused);
      await run.system('next', 'tap', ['Next:Next_track']);
      await until('next track', (s) => playingTitle(s, second));
      await run.system('key-pause-2', 'dispatch', ['pause']);
      await until('paused by the media key', (s) {
        return s?.status == PlaybackStatus.paused;
      });
      await run.system('notification-2', 'notification');
      await run.system('previous', 'tap', ['Previous:Previous_track']);
      await until('previous track', (s) => playingTitle(s, first));
      final length = playback()!.effectiveDuration!;
      await run.system('seek', 'seek-bar', ['0.5']);
      await until(
        'seeked to about half',
        (s) => s != null && s.position > length * 0.4,
      );
      await run.system('key-next', 'dispatch', ['next']);
      await until('next track by the media key', (s) {
        return playingTitle(s, second);
      });
      await run.system('key-toggle', 'dispatch', ['play-pause']);
      await until('paused by play/pause', (s) {
        return s?.status == PlaybackStatus.paused;
      });
      await run.system('session-paused', 'session');
      await run.system('collapse', 'collapse');
      await run.system('foreground', 'foreground');
      await run.step('back');
    } else if (Platform.isMacOS) {
      final panel = await run.system('panel', 'panel');
      expect(panel, contains(first));

      await run.system('pause', 'press', ['toggle']);
      await until('paused', (s) => s?.status == PlaybackStatus.paused);
      await run.system('play', 'press', ['toggle']);
      await until('playing', (s) => playingTitle(s, first));
      await run.system('next', 'press', ['next']);
      await until('next track', (s) => playingTitle(s, second));
      await run.system('previous', 'press', ['previous']);
      await until('previous track', (s) => playingTitle(s, first));
      await run.system('seek', 'seek', ['60']);
      await until(
        'seeked to 1:00',
        (s) =>
            s != null &&
            (s.position - const Duration(seconds: 60)).abs() <
                const Duration(seconds: 5),
      );
      await run.system('media-key', 'key', ['play']);
      await until('paused by the media key', (s) {
        return s?.status == PlaybackStatus.paused;
      });
      await run.system('panel-paused', 'panel');
      await run.system('close-panel', 'close-panel');
      await run.system('foreground', 'foreground');
      await run.step('back');
    } else if (Platform.isIOS) {
      // iOS 模擬器：只截背景時的畫面（事實 I5，控制中心與鎖屏讀不到）。
      await run.system('home', 'screen');
    } else {
      fail(
        'The system side of this scenario is not wired up on Windows yet '
        '(Windows is skipped for now, docs/decisions.md 2026-11-18).',
      );
    }
  });
}
