import 'package:flutter/material.dart';

import '../layout/detail_stats_row.dart';
import '../layout/expandable_text_section.dart';
import '../layout/tags_section.dart';

/// 電台直播間詳情主體（封面 / 標題 / 主播列 / 統計 / 公告 / 簡介 / 標籤）。
///
/// 行動版直播資訊彈窗（radio_player_page）與桌面 Detail Panel 電台詳情
/// （track_detail_panel）共用；兩處的段落順序一致，僅密度與文案鍵不同，
/// 差異全部由參數表達：
/// - [titleMaxLines]：彈窗 3 行、面板 2 行（預設面板值）。
/// - [avatarSize] / [compactHostName]：彈窗 40 + bodyLarge、面板 32 + bodyMedium。
/// - [hostTrailing]：彈窗的 chevron；[hostSubtitle]：面板的開播時間文字。
/// - [stats] / [statsAlignment]：彈窗 5 項靠左、面板 3 項 spaceEvenly。
///
/// 圖片（封面、頭像）一律由呼叫方以 Widget 傳入，此處不直接載入圖片。
class RadioDetailBody extends StatelessWidget {
  const RadioDetailBody({
    super.key,
    required this.cover,
    required this.title,
    this.titleMaxLines = 2,
    this.onTitleTap,
    this.hostName,
    this.hostAvatar,
    this.avatarSize = 32,
    this.avatarGap = 10,
    this.compactHostName = true,
    this.onHostTap,
    this.hostTrailing,
    this.hostSubtitle,
    this.stats = const <DetailStatItem>[],
    this.statsAlignment = WrapAlignment.start,
    this.announcement,
    required this.announcementTitle,
    this.description,
    required this.descriptionTitle,
    this.tags,
    required this.tagsTitle,
    this.spacingAfterCover = 20,
    this.spacingAfterTitle = 12,
  });

  /// 封面區塊（呼叫方建立，含點擊跳轉、LIVE 標章等包裝）。
  final Widget cover;

  /// 直播間標題。
  final String title;

  /// 標題最大行數（彈窗 3、面板 2）。
  final int titleMaxLines;

  /// 點擊標題跳轉直播間；為 null 時不包點擊手勢。
  final VoidCallback? onTitleTap;

  /// 主播名稱；為 null 時不渲染主播列。
  final String? hostName;

  /// 主播頭像（呼叫方建立，可自帶點擊跳轉與邊框）。
  final Widget? hostAvatar;

  /// 頭像顯示尺寸（彈窗 40、面板 32）。
  final double avatarSize;

  /// 頭像與名稱之間的間距（彈窗 12、面板 10）。
  final double avatarGap;

  /// true 使用 bodyMedium（面板）、false 使用 bodyLarge（彈窗）。
  final bool compactHostName;

  /// 點擊整個主播列（彈窗用於跳轉主播空間）；為 null 時不包點擊手勢。
  final VoidCallback? onHostTap;

  /// 主播列尾端元件（彈窗的 chevron）。
  final Widget? hostTrailing;

  /// 主播列尾端文字（面板的開播時間，例如 t.radio.startedBroadcast）。
  final String? hostSubtitle;

  /// 統計列項目。
  final List<DetailStatItem> stats;

  /// 統計列對齊（彈窗靠左、面板 spaceEvenly）。
  final WrapAlignment statsAlignment;

  /// 主播公告內容；null 或空字串時不渲染該段。
  final String? announcement;

  /// 公告段標題（呼叫方負責 i18n）。
  final String announcementTitle;

  /// 直播間簡介內容；null 或空字串時不渲染該段。
  final String? description;

  /// 簡介段標題（呼叫方負責 i18n）。
  final String descriptionTitle;

  /// 逗號分隔的標籤字串；null 或空字串時不渲染該段。
  final String? tags;

  /// 標籤段標題（呼叫方負責 i18n）。
  final String tagsTitle;

  /// 封面與標題之間的間距（彈窗 16、面板 20）。
  final double spacingAfterCover;

  /// 標題與主播列之間的間距（彈窗 16、面板 12）。
  final double spacingAfterTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 封面
        cover,

        SizedBox(height: spacingAfterCover),

        // 標題
        _buildTitle(textTheme),

        // 標題與後續內容的間距（無論有無主播列都保留，與原兩處實作一致）
        SizedBox(height: spacingAfterTitle),

        // 主播列
        if (hostName != null) _buildHostRow(colorScheme, textTheme),

        // 統計數據
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          DetailStatsRow(items: stats, alignment: statsAlignment),
        ],

        // 主播公告
        if (announcement != null && announcement!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          ExpandableTextSection(
            icon: Icons.campaign_outlined,
            title: announcementTitle,
            content: announcement!,
          ),
        ],

        // 直播間簡介
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          ExpandableTextSection(
            icon: Icons.info_outline_rounded,
            title: descriptionTitle,
            content: description!,
          ),
        ],

        // 標籤
        if (tags != null && tags!.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          TagsSection(tags: tags!, title: tagsTitle),
        ],
      ],
    );
  }

  Widget _buildTitle(TextTheme textTheme) {
    Widget titleWidget = Text(
      title,
      style: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
      maxLines: titleMaxLines,
      overflow: TextOverflow.ellipsis,
    );
    if (onTitleTap != null) {
      titleWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTitleTap, child: titleWidget),
      );
    }
    return titleWidget;
  }

  Widget _buildHostRow(ColorScheme colorScheme, TextTheme textTheme) {
    // [hostSubtitle]（面板開播時間）優先於 [hostTrailing]（彈窗 chevron）。
    final Widget? trailing = hostSubtitle != null
        ? Text(
            hostSubtitle!,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          )
        : hostTrailing;

    final row = Row(
      children: [
        if (hostAvatar != null)
          SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: hostAvatar,
          ),
        if (hostAvatar != null) SizedBox(width: avatarGap),
        Expanded(
          child: Text(
            hostName!,
            style: (compactHostName ? textTheme.bodyMedium : textTheme.bodyLarge)
                ?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing,
      ],
    );

    if (onHostTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onHostTap, child: row),
    );
  }
}
