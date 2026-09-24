import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/providers/library/remote_playlist_sync_provider.dart';
import 'package:fmp/services/account/bilibili_favorites_service.dart';
import 'package:fmp/services/account/netease_playlist_service.dart';
import 'package:fmp/services/account/youtube_playlist_service.dart';
import 'package:fmp/services/library/remote_playlist_edit_controller.dart';
import 'package:fmp/services/library/remote_playlist_edit_result.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart';
import 'package:fmp/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart';

/// 三個「加入遠端歌單」面板的送出。
///
/// 規劃要加哪些、刪哪些、失敗怎麼算、成功後要刷新哪些本地匯入歌單，全都在
/// [RemotePlaylistEditController]；面板只負責收集勾選並交出去。部分成功時遠端
/// 已經改了，面板照樣關掉，但要先告訴使用者有幾首沒成功 —— 只報「已更新」會
/// 讓失敗的那幾首無聲消失。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases = <_DialogCase>[
    _DialogCase(
      sourceType: SourceIds.bilibili,
      playlistTitle: 'Bili folder',
      show: showAddToBilibiliPlaylistDialog,
      serviceOverride: bilibiliFavoritesServiceProvider.overrideWithValue(
        _FakeBilibiliFavorites(),
      ),
    ),
    _DialogCase(
      sourceType: SourceIds.youtube,
      playlistTitle: 'YT list',
      show: showAddToYouTubePlaylistDialog,
      serviceOverride: youtubePlaylistServiceProvider.overrideWithValue(
        _FakeYouTubePlaylists(),
      ),
    ),
    _DialogCase(
      sourceType: SourceIds.netease,
      playlistTitle: 'NE list',
      show: showAddToNeteasePlaylistDialog,
      serviceOverride: neteasePlaylistServiceProvider.overrideWithValue(
        _FakeNeteasePlaylists(),
      ),
    ),
  ];

  for (final dialog in cases) {
    testWidgets('the ${dialog.sourceType} sheet hands the selection to the '
        'edit controller and reports a partial success', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      LocaleSettings.setLocale(AppLocale.en);

      final track = Track()
        ..sourceId = 'track-1'
        ..sourceType = dialog.sourceType
        ..title = 'Song';
      final controller = _RecordingEditController();
      bool? closedWith;

      await tester.pumpWidget(
        TranslationProvider(
          child: ProviderScope(
            overrides: [
              dialog.serviceOverride,
              remotePlaylistEditControllerProvider.overrideWithValue(
                controller,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      closedWith = await dialog.show(
                        context: context,
                        tracks: [track],
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(dialog.playlistTitle));
      await tester.pump();
      await tester.tap(find.text(t.remote.addToCount(count: '1')));
      await tester.pumpAndSettle();

      final call = controller.calls.single;
      expect(call.sourceType, dialog.sourceType);
      expect(call.tracks, [track]);
      expect(call.selectedPlaylistIds, hasLength(1));
      expect(call.originalPlaylistIds, isEmpty);

      expect(
        find.text(
          t.addToPlaylistDialog.partiallyCompleted(success: 1, total: 2),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning), findsOneWidget);
      expect(find.text(t.remote.updated), findsNothing);
      expect(closedWith, isTrue);
    });
  }

  group('reportRemotePlaylistEditResult', () {
    Future<bool> report(
      WidgetTester tester,
      RemotePlaylistEditResult result,
    ) async {
      LocaleSettings.setLocale(AppLocale.en);
      var succeeded = false;
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => reportRemotePlaylistEditResult(
                    context,
                    result,
                    onSuccess: () => succeeded = true,
                  ),
                  child: const Text('report'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('report'));
      await tester.pumpAndSettle();
      return succeeded;
    }

    testWidgets('a partial success warns before closing', (tester) async {
      final succeeded = await report(tester, _partialResult('bilibili', '1'));

      expect(succeeded, isTrue);
      expect(find.byIcon(Icons.warning), findsOneWidget);
      expect(
        find.text(
          t.addToPlaylistDialog.partiallyCompleted(success: 1, total: 2),
        ),
        findsOneWidget,
      );
      expect(find.text(t.remote.updated), findsNothing);
    });

    testWidgets('a full success reports that the remote was updated', (
      tester,
    ) async {
      final succeeded = await report(
        tester,
        RemotePlaylistEditResult(
          sourceType: SourceIds.bilibili,
          confirmedAddedTrackIds: const [1],
          changedRemotePlaylistIds: const ['1'],
        ),
      );

      expect(succeeded, isTrue);
      expect(find.text(t.remote.updated), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsNothing);
    });
  });
}

RemotePlaylistEditResult _partialResult(String sourceType, String playlistId) {
  return RemotePlaylistEditResult(
    sourceType: sourceType,
    confirmedAddedTrackIds: const [1],
    failures: [
      RemotePlaylistEditFailure(
        trackId: 2,
        remotePlaylistId: playlistId,
        error: StateError('rejected'),
      ),
    ],
    changedRemotePlaylistIds: [playlistId],
  );
}

class _DialogCase {
  const _DialogCase({
    required this.sourceType,
    required this.playlistTitle,
    required this.show,
    required this.serviceOverride,
  });

  final String sourceType;
  final String playlistTitle;
  final Future<bool> Function({
    required BuildContext context,
    required List<Track> tracks,
  })
  show;
  final Override serviceOverride;
}

typedef _SubmitCall = ({
  String sourceType,
  List<Track> tracks,
  Set<String> selectedPlaylistIds,
  Set<String> originalPlaylistIds,
});

/// 只記下交進來的勾選，回一個部分成功的結果。
class _RecordingEditController extends Fake
    implements RemotePlaylistEditController {
  final calls = <_SubmitCall>[];

  @override
  Future<RemotePlaylistEditResult> submitSelectionEdit({
    required String sourceType,
    required List<Track> tracks,
    required Set<String> selectedPlaylistIds,
    required Set<String> originalPlaylistIds,
    required Set<String> deselectedPartialPlaylistIds,
    required Map<String, Set<String>> existingTrackSourceIdsByPlaylist,
  }) async {
    calls.add((
      sourceType: sourceType,
      tracks: tracks,
      selectedPlaylistIds: {...selectedPlaylistIds},
      originalPlaylistIds: {...originalPlaylistIds},
    ));
    return _partialResult(sourceType, selectedPlaylistIds.first);
  }
}

/// 下面三個只提供面板載入時會問的東西；寫入一律不該經過它們。
class _FakeBilibiliFavorites extends Fake implements BilibiliFavoritesService {
  @override
  Future<int> getVideoAid(Track track) async => 1;

  @override
  Future<List<BilibiliFavFolder>> getFavFolders({int? videoAid}) async =>
      const [BilibiliFavFolder(id: 11, title: 'Bili folder', mediaCount: 0)];
}

class _FakeYouTubePlaylists extends Fake implements YouTubePlaylistService {
  @override
  Future<List<YouTubePlaylistInfo>> getPlaylists() async => const [
    YouTubePlaylistInfo(playlistId: 'PL1', title: 'YT list', videoCount: 0),
  ];

  @override
  Future<bool> checkVideoInPlaylist(String playlistId, String videoId) async =>
      false;
}

class _FakeNeteasePlaylists extends Fake implements NeteasePlaylistService {
  @override
  Future<List<NeteasePlaylistInfo>> getWritablePlaylists() async => const [
    NeteasePlaylistInfo(
      playlistId: 'N1',
      title: 'NE list',
      trackCount: 0,
      isMine: true,
    ),
  ];

  @override
  Future<Set<String>> getTrackIdsInPlaylist(
    String playlistId, {
    Set<String>? targetTrackIds,
  }) async => const {};
}
