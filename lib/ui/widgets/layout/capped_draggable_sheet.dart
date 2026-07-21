import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import 'sheet_drag_handle.dart';

/// [CappedDraggableSheet] 的高度模式。
enum CappedSheetMode {
  /// 兩段式拖曳：初始停在 60% 螢幕高度（上限不足時貼齊上限），
  /// snap 點為 `[0, init, max]`，可拖到底關閉。用於資訊類彈窗。
  snap,

  /// 內容自適應：`expand: false`，高度由內容決定但不超過上限比例，
  /// 初始即上限比例、無額外 snap 點。用於表單類彈窗（如歌詞搜尋）。
  fitContent,
}

/// 帶高度上限的共享 DraggableScrollableSheet 外殼。
///
/// 統一三個彈窗（曲目資訊、直播資訊、歌詞搜尋）先前逐字複製的外層結構：
/// 高度上限換算（[AppSizes.maxBottomSheetHeight] / 螢幕高度，clamp 0.4~0.95）、
/// `surfaceContainerLow` + 頂部圓角 [AppRadius.sheet] 的容器、
/// 桌面板拖曳手勢（touch/mouse/trackpad）的 ScrollConfiguration、
/// [SheetDragHandle]、標題列（圖示 + 標題 + 關閉鈕）與 Divider。
///
/// 呼叫端只需提供標題列內容與 body slivers：
///
/// ```dart
/// CappedDraggableSheet(
///   icon: Icons.info_outline_rounded,
///   title: t.player.songInfo,
///   onClose: () => Navigator.of(context).pop(),
///   bodySlivers: (context, scrollController) => [...],
/// )
/// ```
///
/// 預設 [CappedSheetMode.snap]；內容自適應的彈窗傳
/// `mode: CappedSheetMode.fitContent`。
class CappedDraggableSheet extends StatelessWidget {
  const CappedDraggableSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.onClose,
    required this.bodySlivers,
    this.mode = CappedSheetMode.snap,
    this.headerPadding = const EdgeInsets.fromLTRB(20, 16, 20, 8),
  });

  /// 標題列圖示（20px，primary 色）。
  final IconData icon;

  /// 標題文字（titleMedium bold）。
  final String title;

  /// 關閉鈕回呼。
  final VoidCallback onClose;

  /// 內容區 slivers，接在固定標頭（把手 + 標題列 + Divider）之後。
  final List<Widget> Function(
    BuildContext context,
    ScrollController scrollController,
  ) bodySlivers;

  /// 高度模式，見 [CappedSheetMode]。
  final CappedSheetMode mode;

  /// 標題列 padding，預設 `fromLTRB(20, 16, 20, 8)`。
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 限制最大高度，避免 Windows 全屏时弹窗过高
    final screenHeight = MediaQuery.of(context).size.height;
    final maxRatio =
        (AppSizes.maxBottomSheetHeight / screenHeight).clamp(0.4, 0.95);

    final double initialChildSize;
    final List<double> snapSizes;
    final bool expand;
    switch (mode) {
      case CappedSheetMode.snap:
        initialChildSize = maxRatio < 0.6 ? maxRatio : 0.6;
        snapSizes = [
          0.0,
          initialChildSize,
          if (maxRatio > initialChildSize) maxRatio,
        ];
        expand = true;
      case CappedSheetMode.fitContent:
        initialChildSize = maxRatio;
        snapSizes = const [];
        expand = false;
    }

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: 0.0,
      maxChildSize: maxRatio,
      snap: true,
      snapSizes: snapSizes,
      expand: expand,
      builder: (context, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                // 頂部固定區域：拖動把手 + 標題列 + Divider
                const SliverToBoxAdapter(
                  child: SheetDragHandle(margin: EdgeInsets.only(top: 12)),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: headerPadding,
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: Divider(height: 1)),

                // 內容區域
                ...bodySlivers(context, scrollController),
              ],
            ),
          ),
        );
      },
    );
  }
}
