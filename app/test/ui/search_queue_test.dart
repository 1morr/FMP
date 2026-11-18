import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/search/placeholder_search.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell.dart';

/// 搜尋結果：點一首臨時播放（觸控點一下；滑鼠單擊選取、雙擊或 ↩ 才播），
/// ⋮ 與右鍵的選單有「下一首播放」「加入佇列」。搜尋結果與佇列都換成假的。
void main() {
  late Directory logDir;
  late Log log;
  late PluginHost host;
  late _FakeQueue queue;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.zhTw);
    logDir = Directory.systemTemp.createTempSync('fmp_search_queue_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    host = PluginHost(bundles: const [], log: log);
  });
  tearDown(() async {
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
    await host.close();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  Future<void> start(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    queue = _FakeQueue();
    await tester.pumpWidget(
      buildRoot(
        overrides: [
          pluginHostProvider.overrideWith((_) => host),
          placeholderSearchProvider.overrideWith(_FakeSearch.new),
          queueProvider.overrideWith(() => queue),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openSearch(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a result plays it temporarily', (tester) async {
    await start(tester, const Size(390, 844));

    await tester.tap(find.text('晴天'));
    expect(queue.calls, ['playTemporarily 1']);
  });

  group('with a mouse', () {
    /// 桌面平台才是滑鼠密度；測試結束前要還原（框架在 tearDown 之前檢查）。
    Future<void> withMouse(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await body();
      debugDefaultTargetPlatformOverride = null;
    }

    testWidgets('a single click only selects the result', (tester) async {
      await withMouse(() async {
        await start(tester, const Size(1280, 800));

        await tester.tap(find.text('晴天'));
        await tester.pump(kDoubleTapTimeout);

        expect(queue.calls, isEmpty);
        expect(
          tester.widget<ListTile>(find.widgetWithText(ListTile, '晴天')).selected,
          isTrue,
        );
      });
    });

    testWidgets('a double click plays it temporarily', (tester) async {
      await withMouse(() async {
        await start(tester, const Size(1280, 800));

        await tester.tap(find.text('晴天'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('晴天'));
        await tester.pumpAndSettle();

        expect(queue.calls, ['playTemporarily 1']);
      });
    });

    testWidgets('the more button opens its menu right away, without waiting '
        'for a double click', (tester) async {
      await withMouse(() async {
        await start(tester, const Size(1280, 800));

        await tester.tap(find.byTooltip('更多'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('加入佇列'), findsOneWidget);
        await tester.pumpAndSettle();
      });
    });

    testWidgets('↩ plays the selected result temporarily', (tester) async {
      await withMouse(() async {
        await start(tester, const Size(1280, 800));

        await tester.tap(find.text('晴天'));
        await tester.pump(kDoubleTapTimeout);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);

        expect(queue.calls, ['playTemporarily 1']);
      });
    });
  });

  testWidgets('the more menu plays next or adds to the queue', (tester) async {
    await start(tester, const Size(390, 844));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一首播放'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入佇列'));
    await tester.pumpAndSettle();

    expect(queue.calls, ['playNext 1', 'add 1']);
  });

  testWidgets('a right click opens the same menu', (tester) async {
    await start(tester, const Size(1280, 800));

    await tester.tap(find.text('晴天'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入佇列'));
    await tester.pumpAndSettle();

    expect(queue.calls, ['add 1']);
  });
}

class _FakeSearch extends PlaceholderSearch {
  @override
  AsyncValue<List<PluginResults>>? build() => const AsyncData([
    PluginResults('Songs', tracks: [track]),
  ]);
}

const track = Track(
  ref: TrackRef(pluginId: 'songs', trackId: '1'),
  title: '晴天',
  author: 'Alice',
);

/// 記下放進佇列的動作。
class _FakeQueue extends QueueController {
  final calls = <String>[];

  @override
  Queue build() => Queue.empty;

  @override
  Future<void> playTemporarily(Track track) async =>
      calls.add('playTemporarily ${track.ref.trackId}');

  @override
  Future<void> playNext(List<Track> tracks) async =>
      calls.add('playNext ${tracks.single.ref.trackId}');

  @override
  Future<void> add(List<Track> tracks) async =>
      calls.add('add ${tracks.single.ref.trackId}');
}
