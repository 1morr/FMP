import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/format/count_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 曲目列的副標：上傳者（或音源不可用的原因）加「▶ 播放數」（舊版的做法，ADR 0035 §決定 10）。
/// 播放數用 CLDR 縮寫（`formatCount`），沒有就整組不畫。
///
/// 兩段都可以縮到省略號：播放數的圖示與數字包在同一個 `Flexible`，窄版或大字級時不會溢出
/// （舊版 #85 的教訓）。時長欄在列尾，不在這裡，所以固定寬度的欄位不受影響。
class TrackSubtitle extends ConsumerWidget {
  const TrackSubtitle({super.key, this.text, this.viewCount});

  /// 上傳者；沒有就只畫播放數。
  final String? text;

  /// 播放數；`null` 不畫。
  final int? viewCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = this.text;
    final count = viewCount;
    if (count == null) {
      return text == null
          ? const SizedBox.shrink()
          : Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final spacing = AppTokens.of(context).spacing;
    final style = Theme.of(context).textTheme.bodySmall;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        if (text != null)
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (text != null) SizedBox(width: spacing.x2),
              Icon(Icons.play_arrow, size: style?.fontSize, color: color),
              Flexible(
                child: Text(
                  formatCount(ref.watch(uiLocaleProvider), count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
