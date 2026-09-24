import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/lyrics/lrc_parser.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/ui/widgets/lyrics/lyrics_display.dart';

const _syncedLyrics =
    '[00:00.00]First line\n'
    '[00:10.00]Second line\n'
    '[00:20.00]Third line';

void main() {
  testWidgets('position ticks within one line do not rebuild the lyrics', (
    tester,
  ) async {
    // 播放位置每秒更新好幾次。歌詞只該在「目前是哪一行」變了的時候重建；
    // 直接 watch 位置的話，整份歌詞（量字寬、排版、整條清單）每一跳都重做一次。
    final controller = _PositionController(const Duration(seconds: 1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioControllerProvider.overrideWith(() => controller),
          currentLyricsMatchProvider.overrideWithValue(
            AsyncData(
              LyricsMatch()
                ..trackUniqueKey = 'bilibili:BV1'
                ..lyricsSource = 'lrclib'
                ..externalId = '1',
            ),
          ),
          currentLyricsContentProvider.overrideWithValue(
            const AsyncData(
              LyricsResult(
                id: '1',
                trackName: 'Track',
                artistName: 'Artist',
                albumName: '',
                duration: 30,
                instrumental: false,
                syncedLyrics: _syncedLyrics,
              ),
            ),
          ),
          parsedLyricsProvider.overrideWithValue(
            LrcParser.parse(_syncedLyrics, null),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: LyricsDisplay())),
      ),
    );
    expect(find.text('Second line'), findsOneWidget);

    // build() 每次都產生新的子 widget 實例，所以根節點實例沒換就代表沒有重建。
    Widget builtRoot() => tester.widget(
      find
          .descendant(
            of: find.byType(LyricsDisplay),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    final before = builtRoot();

    controller.moveTo(const Duration(seconds: 2));
    await tester.pump();
    controller.moveTo(const Duration(milliseconds: 9500));
    await tester.pump();

    expect(
      builtRoot(),
      same(before),
      reason: 'still on the first line, so nothing the widget shows changed',
    );

    // 反方向：跨到下一行時確實重建 —— 證明上面的觀察方式抓得到重建。
    controller.moveTo(const Duration(seconds: 11));
    await tester.pump();

    expect(builtRoot(), isNot(same(before)));
    await tester.pumpAndSettle();
  });
}

/// 只持有播放位置的控制器；歌詞元件從它讀到的只有位置。
class _PositionController extends AudioController {
  _PositionController(this._initial);

  final Duration _initial;

  @override
  PlayerState build() => PlayerState(position: _initial);

  void moveTo(Duration position) => state = state.copyWith(position: position);
}
