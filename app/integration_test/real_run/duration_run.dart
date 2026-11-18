import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 06b 的實跑情境：匿名搜一次「lofi」，連續點第 1、2、3 首，記下每一個播放
/// 狀態的時長。驗收：迷你播放器與播放膠囊顯示的時長和曲目自己的時長差 1 秒
/// 內，切歌時不出現上一首的時長。跑法見 docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d ios integration_test/real_run/duration_run.dart
///
/// 連續切兩首要播三首，比 spec〈共同規則〉的「播一首」多兩首：驗收要的就是切歌。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shown duration follows the track while switching twice', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final more = find.byTooltip(t.queue.more);
    await run.waitFor(more);
    await run.step('search');

    final container = ProviderScope.containerOf(tester.element(more.first));
    final started = DateTime.now();
    final log = <String>[];
    final mismatches = <String>[];
    container.listen<PlaybackState?>(playbackProvider, (_, state) {
      if (state == null) return;
      final ms = DateTime.now().difference(started).inMilliseconds;
      final shown = state.effectiveDuration;
      final own = state.track.duration;
      final line =
          '$ms ms ${state.track.ref.logId} ${state.status.name} '
          'pos=${formatDuration(state.position)} '
          'backend=${state.duration == null ? '-' : formatDuration(state.duration!)} '
          'track=${own == null ? '-' : formatDuration(own)} '
          'shown=${shown == null ? '-' : formatDuration(shown)}';
      if (log.isEmpty ||
          log.last.split(' ms ').last != line.split(' ms ').last) {
        log.add(line);
      }
      if (shown != null &&
          own != null &&
          (shown - own).abs() > const Duration(seconds: 1)) {
        mismatches.add(line);
      }
    }, fireImmediately: true);
    addTearDown(() {
      // ignore: avoid_print -- 狀態的流水帳留在實跑的輸出裡，根因靠它查。
      print('[duration log]\n  ${log.join('\n  ')}');
    });

    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );

    /// 迷你播放器或播放膠囊畫出來的「位置 / 長度」，長度和曲目自己的時長差
    /// 1 秒內（票的驗收）。讀畫面上的字，不讀狀態：元件改讀別的值也抓得到。
    void expectShownLengthMatchesTrack() {
      final own = container.read(playbackProvider)!.track.duration!;
      final shown = [
        for (final e
            in find
                .descendant(of: controls, matching: find.textContaining(' / '))
                .evaluate())
          switch (e.widget) {
            Text(:final data?) => data,
            Text(:final textSpan?) => textSpan.toPlainText(),
            RichText(:final text) => text.toPlainText(),
            _ => '',
          },
      ].map((t) => RegExp(r'/ ([\d:]+)$').firstMatch(t)?[1]).nonNulls;
      expect(shown, isNotEmpty);
      for (final text in shown) {
        final length = text
            .split(':')
            .map(int.parse)
            .fold(0, (seconds, part) => seconds * 60 + part);
        expect(
          (Duration(seconds: length) - own).abs(),
          lessThanOrEqualTo(const Duration(seconds: 1)),
          reason: 'shown $text, the track is $own',
        );
      }
    }

    /// App 還沒有拖進度的畫面（播放頁的票），經音訊後端跳到 33:20：iOS 曾把
    /// 這首報成 33:10 並在那裡結束（事實 M14）。讀回位置要往前走、還在播同一首。
    Future<void> seekPast33Minutes(String title) async {
      const target = Duration(minutes: 33, seconds: 20);
      await tester.runAsync(
        () => container.read(audioBackendProvider).seek(target),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 8)),
      );
      final state = container.read(playbackProvider)!;
      expect(state.track.title, title);
      expect(state.status, PlaybackStatus.playing);
      expect(state.position, greaterThan(target + const Duration(seconds: 2)));
      expectShownLengthMatchesTrack();
      await run.step('seek');
    }

    for (final (index, name) in [(0, 'first'), (1, 'second'), (2, 'third')]) {
      final row = searchResultAt(index);
      final title = searchResultTitle(tester, index);
      // 點一首是臨時播放（桌面雙擊）；連點三首是連續臨時播放。
      await playSearchResult(tester, row);
      await run.waitFor(
        find.descendant(of: controls, matching: find.text(title)),
      );
      // B 站 CDN 開頭偶爾要等十幾秒（看門狗會記警告）。
      await run.waitFor(
        find.text(t.placeholder.playback.playing),
        timeout: const Duration(seconds: 60),
      );
      // 播一陣子：後端在開始播之後才會更新長度（seekable 範圍、mpv 的 duration）。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 6)),
      );
      expectShownLengthMatchesTrack();
      await run.step(name);
      if (index == 0) await seekPast33Minutes(title);
    }

    expect(mismatches, isEmpty);
  });
}
