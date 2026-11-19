import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:material_ui/material_ui.dart';

/// 一個音源出錯的說明卡（搜尋頁的 `.srh-err`、首頁的 `.hm-err`，同一張）：
/// 左邊是音源符號加警示角標（沒有 [pluginId] 時是沒有網路的符號），中間是
/// [title] 與 [reason]，右邊是只重試它的「重試」。
class SourceErrorCard extends StatelessWidget {
  const SourceErrorCard({
    super.key,
    required this.pluginId,
    required this.title,
    required this.reason,
    required this.retryLabel,
    required this.onRetry,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 10),
  });

  final String? pluginId;
  final String title;
  final String reason;
  final String retryLabel;
  final VoidCallback onRetry;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final icon = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.cell,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: switch (pluginId) {
        final id? => SourceMarkIcon(pluginId: id, size: 18),
        null => FmpIcon(FmpIcons.wifi, size: 18, color: colors.label2),
      },
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: margin,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(context.fmpMetrics.radii.group),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 36,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  icon,
                  if (pluginId != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: colors.bg,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: FmpIcon(
                          FmpIcons.warn,
                          size: 13,
                          color: colors.warn,
                          strokeWidth: 2.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: colors.label,
                    ),
                  ),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 13,
                      height: 17 / 13,
                      letterSpacing: 0,
                      color: colors.label2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FmpButton(
              label: retryLabel,
              icon: FmpIcons.refresh,
              variant: FmpButtonVariant.tinted,
              size: FmpButtonSize.small,
              touchTarget: true,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
