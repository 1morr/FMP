import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/now_playing/now_playing.dart';
import 'package:fmp/ui/now_playing/spine.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面與中寬度的播放膠囊（`.transport`，`docs/design/DESIGN.md`〈桌面〉
/// 〈中寬度〉）：玻璃膠囊本身是書脊式進度條；三欄，左邊封面、標題、音源符號
/// ＋作者，中間上一首、播放、下一首，右邊時間。膠囊窄於 640 時收掉時間。
/// 隨機、循環、歌詞、佇列、音量與拖動進度由之後的票接上（還沒有的功能不
/// 出現入口）。
class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.state, required this.touch});

  /// 平板版（`.transport.touch`）的高度；滑鼠版 64。
  static double heightOf({required bool touch}) => touch ? 68 : 64;

  final PlaybackState state;

  /// 平板：高 68、封面 48、播放 50，手機字級。
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final track = state.track;
    final height = heightOf(touch: touch);
    final title = text.body.copyWith(
      fontSize: touch ? 15 : 13,
      height: touch ? 19 / 15 : null,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: colors.glassInk,
    );
    final sub = text.sub.copyWith(
      fontSize: touch ? 13 : 12,
      height: touch ? 17 / 13 : null,
      letterSpacing: 0,
      color: colors.glassInk2,
    );
    // 自成一個語意節點，螢幕閱讀器不把它和頁面的字併在一起。
    return Semantics(
      container: true,
      child: Glass(
        child: SizedBox(
          height: height,
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
              LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxWidth < 640;
                  return Padding(
                    padding: EdgeInsets.only(left: 10, right: touch ? 12 : 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Cover(
                                url: track.coverUrl,
                                size: touch ? 48 : 44,
                                radius: 10,
                              ),
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
                                      style: title,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        SourceMarkIcon(
                                          pluginId: track.ref.pluginId,
                                          size: touch ? 15 : 14,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Text(
                                            track.author,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: sub,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        SkipButton(
                          forward: false,
                          size: touch ? 44 : 32,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 6),
                        PlayPauseButton(
                          playing: state.playing,
                          size: touch ? 50 : 38,
                          iconSize: 24,
                        ),
                        const SizedBox(width: 6),
                        SkipButton(
                          forward: true,
                          size: touch ? 44 : 32,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: compact
                                ? null
                                : Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(
                                      playbackTime(state),
                                      maxLines: 1,
                                      style: text.cap
                                          .copyWith(
                                            fontSize: touch ? 12 : 11,
                                            letterSpacing: 0,
                                            color: colors.glassInk2,
                                          )
                                          .tabular,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
