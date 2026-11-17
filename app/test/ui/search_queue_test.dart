import 'dart:io';

import 'package:flutter/gestures.dart';
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

/// 搜尋結果放進佇列：點一首馬上播（插在正在播的後面），⋮ 與右鍵的選單有
/// 「下一首播放」「加入佇列」。搜尋結果與佇列都換成假的。
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

  testWidgets('tapping a result plays it now', (tester) async {
    await start(tester, const Size(390, 844));

    await tester.tap(find.text('晴天'));
    expect(queue.calls, ['playNow 1']);
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
  Future<void> playNow(Track track) async =>
      calls.add('playNow ${track.ref.trackId}');

  @override
  Future<void> playNext(List<Track> tracks) async =>
      calls.add('playNext ${tracks.single.ref.trackId}');

  @override
  Future<void> add(List<Track> tracks) async =>
      calls.add('add ${tracks.single.ref.trackId}');
}
