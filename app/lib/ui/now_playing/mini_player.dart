import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/now_playing/now_playing.dart';
import 'package:fmp/ui/now_playing/spine.dart';
import 'package:material_ui/material_ui.dart';

/// 手機的迷你播放器（`FMP.mini`，`docs/design/DESIGN.md`〈手機〉）：56 高的
/// 玻璃膠囊，封面 40、標題、音源符號＋作者＋時間、播放與暫停，進度是書脊。
/// 下一首鈕照稿，沒有上一首。只顯示進度，拖動在播放頁。點整條打開播放頁
/// 由之後的票接上（還沒有的功能不出現入口）。
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final track = state.track;
    // 自成一個語意節點，螢幕閱讀器不把它和頁面的字併在一起。
    return Semantics(
      container: true,
      child: Glass(
        child: SizedBox(
          height: 56,
          child: Stack(
            children: [
              Positioned.fill(
                child: Spine(
                  progress: spineProgress(
                    state.position,
                    state.effectiveDuration,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 6),
                child: Row(
                  children: [
                    Cover(url: track.coverUrl, size: 40, radius: 9),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.body.copyWith(
                              fontSize: 15,
                              height: 19 / 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: colors.glassInk,
                            ),
                          ),
                          _Subtitle(state: state),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    PlayPauseButton(
                      playing: state.playing,
                      size: 42,
                      iconSize: 24,
                    ),
                    const SkipButton(forward: true, size: 42, iconSize: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 音源符號 · 作者 · 時間，13/17 的次要玻璃字色；作者過長時截斷，時間不截。
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    final style = context.fmpText.sub.copyWith(
      fontSize: 13,
      height: 17 / 13,
      letterSpacing: 0,
      color: context.fmpColors.glassInk2,
    );
    return Row(
      children: [
        SourceMarkIcon(pluginId: state.track.ref.pluginId, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            state.track.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 5),
        Text('· ${playbackTime(state)}', maxLines: 1, style: style.tabular),
      ],
    );
  }
}
