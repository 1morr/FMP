import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/sources/base_source.dart' show SearchResult;
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/providers/search/search_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/ui/pages/search/search_page.dart';

/// 搜尋頁的多 P 影片：點一下先播原曲、同時載入分 P 清單。
///
/// 分 P 是逐列展開出來的，每一列都是一首可以單獨操作的曲目，所以它的選單要跟
/// 一般單曲一樣完整；而載入分 P 是一個背景請求，失敗時不能只是讓轉圈消失。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final video = Track()
    ..sourceId = 'BV1multi'
    ..sourceType = SourceIds.bilibili
    ..title = 'Multi part video'
    ..artist = 'Uploader';

  Future<void> pumpSearchPage(
    WidgetTester tester, {
    required Future<List<VideoPage>> Function(Track track) loadPages,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    LocaleSettings.setLocale(AppLocale.en);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            searchProvider.overrideWith(
              () => _ResultsSearchNotifier(video, loadPages),
            ),
            audioControllerProvider.overrideWith(_IdleAudioController.new),
          ],
          child: const MaterialApp(home: SearchPage()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('each expanded part row offers the full single-track menu', (
    tester,
  ) async {
    await pumpSearchPage(
      tester,
      loadPages: (_) async => const [
        VideoPage(cid: 1, page: 1, part: 'Part one', duration: 60),
        VideoPage(cid: 2, page: 2, part: 'Part two', duration: 90),
      ],
    );

    await tester.tap(find.text(video.title));
    await tester.pumpAndSettle();

    final partRow = find.byKey(
      ValueKey('page-${video.sourceType}:${video.sourceId}:2'),
    );
    expect(partRow, findsOneWidget);

    await tester.tap(
      find.descendant(of: partRow, matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();

    expect(find.text(t.general.addToPlaylist), findsOneWidget);
    expect(find.text(t.lyrics.matchLyrics), findsOneWidget);
    expect(find.text(t.remote.addToFavorites), findsOneWidget);
  });

  testWidgets('a failed part list load is reported to the user', (
    tester,
  ) async {
    await pumpSearchPage(
      tester,
      loadPages: (_) async => throw const SocketException('offline'),
    );

    await tester.tap(find.text(video.title));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(t.error.networkError), findsOneWidget);
  });
}

/// 不呼叫 `super.build()`：真的那個會接搜尋服務與音源管理器。
class _ResultsSearchNotifier extends SearchNotifier {
  _ResultsSearchNotifier(this._video, this._loadPages);

  final Track _video;
  final Future<List<VideoPage>> Function(Track track) _loadPages;

  @override
  SearchState build() => SearchState(
    query: 'multi',
    onlineResults: {
      _video.sourceType: SearchResult(
        tracks: [_video],
        totalCount: 1,
        page: 1,
        pageSize: 20,
        hasMore: false,
      ),
    },
  );

  @override
  Future<List<VideoPage>> loadVideoPagesForTrack(Track track) =>
      _loadPages(track);
}

/// 點一下影片會先 `playTemporary` 原曲；這裡只需要它不去碰真的播放器。
class _IdleAudioController extends AudioController {
  @override
  PlayerState build() => const PlayerState();

  @override
  Future<void> playTemporary(Track track) async {}
}
