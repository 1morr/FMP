import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/ui/pages/lyrics/lyrics_search_sheet.dart';

/// 手動匹配歌詞的兩個寫入動作：選一筆結果、移除既有匹配。
///
/// 兩者都是寫資料庫的非同步動作，失敗時面板會留在原地；沒有提示的話使用者只會
/// 看到「點了沒反應」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final track = Track()
    ..sourceId = 'BV1lyrics'
    ..sourceType = SourceIds.bilibili
    ..title = 'Some song'
    ..artist = 'Someone';

  const result = LyricsResult(
    id: '42',
    trackName: 'Some song (lyrics)',
    artistName: 'Someone',
    albumName: 'Album',
    duration: 200,
    instrumental: false,
    syncedLyrics: '[00:01.00]line',
  );

  Future<_ScriptedLyricsSearchNotifier> pumpSheet(
    WidgetTester tester, {
    required _ScriptedLyricsSearchNotifier notifier,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    LocaleSettings.setLocale(AppLocale.en);

    final existingMatch = LyricsMatch()
      ..trackUniqueKey = track.uniqueKey
      ..lyricsSource = 'lrclib'
      ..externalId = '7';

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            lyricsSearchProvider.overrideWith(() => notifier),
            lyricsMatchForTrackProvider(
              track.uniqueKey,
            ).overrideWith((ref) async => existingMatch),
            lyricsSourceOrderProvider.overrideWithValue(const ['lrclib']),
            disabledLyricsSourcesProvider.overrideWithValue(const <String>{}),
          ],
          child: MaterialApp(
            home: Scaffold(body: LyricsSearchSheet(track: track)),
          ),
        ),
      ),
    );
    await tester.pump();
    return notifier;
  }

  testWidgets('a match that cannot be saved is reported to the user', (
    tester,
  ) async {
    final saves = Completer<void>();
    final notifier = await pumpSheet(
      tester,
      notifier: _ScriptedLyricsSearchNotifier(
        results: const [result],
        onSave: () => saves.future,
      ),
    );

    await tester.tap(find.text(result.trackName));
    await tester.pump();
    // 寫入還在進行時再點一次不會送出第二次。
    await tester.tap(find.text(result.trackName), warnIfMissed: false);
    await tester.pump();
    expect(notifier.saveCalls, 1);

    saves.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(t.lyrics.saveFailed(error: t.error.networkError)),
      findsOneWidget,
    );
  });

  testWidgets('a match that cannot be removed is reported to the user', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      notifier: _ScriptedLyricsSearchNotifier(
        onRemove: () async => throw const SocketException('offline'),
      ),
    );

    await tester.tap(find.byTooltip(t.lyrics.removeMatch));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(t.lyrics.removeFailed(error: t.error.networkError)),
      findsOneWidget,
    );
  });
}

/// 不呼叫 `super.build()`：真的那個會接三個歌詞源、資料庫與快取。
class _ScriptedLyricsSearchNotifier extends LyricsSearchNotifier {
  _ScriptedLyricsSearchNotifier({
    this.results = const [],
    this.onSave,
    this.onRemove,
  });

  final List<LyricsResult> results;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onRemove;
  int saveCalls = 0;

  @override
  LyricsSearchState build() => LyricsSearchState(results: results);

  @override
  Future<void> saveMatch({
    required String trackUniqueKey,
    required LyricsResult result,
  }) {
    saveCalls++;
    return onSave!();
  }

  @override
  Future<void> removeMatch(String trackUniqueKey) => onRemove!();
}
