import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/glass_menu.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/common/track_actions.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 區塊標題（`.srh-sh`；表格是 `.srh-dsh`）：「線上結果 49」。
class SearchSectionHeader extends StatelessWidget {
  const SearchSectionHeader({
    super.key,
    required this.title,
    this.count,
    required this.table,
    this.trailing,
  });

  final String title;
  final int? count;
  final bool table;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Padding(
      padding: table
          ? const EdgeInsets.fromLTRB(10, 22, 10, 6)
          : const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: table
                  ? const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ).copyWith(color: colors.label)
                  : context.fmpText.title3.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
            ),
          ),
          if (count case final count?) ...[
            SizedBox(width: table ? 7 : 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: table ? 13 : 15,
                fontWeight: table ? FontWeight.w500 : null,
                letterSpacing: 0,
                color: colors.label3,
              ).tabular,
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 一個音源搜尋失敗的原因（brief〈錯誤、log 與診斷〉的錯誤分類）。
String searchErrorReason(Translations t, AppError error, String source) =>
    switch (error) {
      RateLimited() => t.search.error.rateLimited(source: source),
      NetworkError() => t.search.error.network,
      LoginRequired() || CredentialInvalid() => t.search.error.loginRequired,
      _ => t.search.error.failed,
    };

/// 觸控列表裡一個音源出錯的說明卡（`.srh-err`）：哪個音源、原因、只重查它的
/// 「重試」。[othersShown] 時補一句其他音源照常顯示。
class SearchErrorCard extends StatelessWidget {
  const SearchErrorCard({
    super.key,
    required this.source,
    required this.othersShown,
    required this.onRetry,
  });

  final SourceResults source;
  final bool othersShown;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final manifest = source.manifest;
    final reason = [
      searchErrorReason(t, source.error!, manifest.name),
      if (othersShown) t.search.error.othersShown,
    ].join();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
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
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.cell,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: SourceMarkIcon(pluginId: manifest.id, size: 18),
                ),
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
                  t.search.error.title(source: manifest.name),
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
            label: t.search.error.retry,
            icon: FmpIcons.refresh,
            variant: FmpButtonVariant.tinted,
            size: FmpButtonSize.small,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// 表格裡一個音源出錯的一列（`.srh-derr`）：警示符號、音源、「X 暫時無法
/// 搜尋：原因」、「重試 X」。
class SearchErrorLine extends StatelessWidget {
  const SearchErrorLine({
    super.key,
    required this.source,
    required this.othersShown,
    required this.onRetry,
  });

  final SourceResults source;
  final bool othersShown;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final manifest = source.manifest;
    final style = TextStyle(
      fontSize: 12.5,
      letterSpacing: 0,
      color: colors.label2,
    );
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          FmpIcon(FmpIcons.warn, size: 16, color: colors.warn),
          const SizedBox(width: 10),
          SourceMarkIcon(pluginId: manifest.id, size: 15),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.search.error.title(source: manifest.name),
                    style: TextStyle(
                      color: colors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text:
                        '：${searchErrorReason(t, source.error!, manifest.name)}'
                        '${othersShown ? t.search.error.othersShown : ''}',
                  ),
                ],
              ),
              style: style,
            ),
          ),
          const SizedBox(width: 10),
          FmpButton(
            label: t.search.error.retrySource(source: manifest.name),
            icon: FmpIcons.refresh,
            size: FmpButtonSize.small,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// 載入中的骨架列（`.srh-sk`）：封面與兩行字的灰塊。[index] 決定兩行的
/// 長度，幾列看起來不一樣長。
class SearchSkeletonRow extends StatelessWidget {
  const SearchSkeletonRow({
    super.key,
    required this.index,
    required this.table,
  });

  final int index;
  final bool table;

  static const _first = [.72, .55, .80, .62, .68];
  static const _second = [.40, .32, .46, .36, .30];

  @override
  Widget build(BuildContext context) {
    final fill = context.fmpColors.fill;
    Widget bar(double height, double factor) => FractionallySizedBox(
      widthFactor: factor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    final cover = table ? 36.0 : 48.0;
    return Container(
      height: table ? 50 : 60,
      padding: EdgeInsets.symmetric(horizontal: table ? 46 : 16),
      child: Row(
        children: [
          Container(
            width: cover,
            height: cover,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          SizedBox(width: table ? 10 : 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                bar(table ? 11 : 13, _first[index % 5]),
                SizedBox(height: table ? 6 : 7),
                bar(table ? 9 : 10, _second[index % 5]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 找不到（`.srh-empty`）：每個音源都成功、都沒有結果時。
class SearchEmpty extends StatelessWidget {
  const SearchEmpty({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 90, 40, 0),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colors.fill,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: FmpIcon(FmpIcons.search, size: 30, color: colors.label3),
          ),
          Text(
            t.search.empty.title(query: query),
            textAlign: TextAlign.center,
            style: context.fmpText.title3.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            t.search.empty.body,
            textAlign: TextAlign.center,
            style: context.fmpText.sub.copyWith(color: colors.label2),
          ),
        ],
      ),
    );
  }
}

/// 結果最後的一行字（`.srh-foot`）：「已載入全部」。
class SearchFoot extends StatelessWidget {
  const SearchFoot(this.text, {super.key, required this.table});

  final String text;
  final bool table;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: table ? 12 : 13,
        letterSpacing: 0,
        color: context.fmpColors.label3,
      ),
    ),
  );
}

/// 搜尋紀錄的一列（`.srh-hist .row`）：時鐘、字串（輸入中時打過的字加粗）、
/// 刪單筆的 ×。點整列重搜。
class SearchHistoryRow extends StatelessWidget {
  const SearchHistoryRow({
    super.key,
    required this.query,
    required this.typed,
    required this.separator,
    required this.table,
    required this.onTap,
    required this.onRemove,
  });

  final String query;

  /// 搜尋欄裡正在打的字：紀錄裡相符的那段加粗。
  final String typed;
  final bool separator;
  final bool table;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final at = typed.isEmpty
        ? -1
        : query.toLowerCase().indexOf(typed.toLowerCase());
    final style = TextStyle(
      fontSize: table ? 13 : 17,
      letterSpacing: 0,
      color: colors.label,
    );
    final text = at < 0
        ? TextSpan(text: query)
        : TextSpan(
            children: [
              TextSpan(text: query.substring(0, at)),
              TextSpan(
                text: query.substring(at, at + typed.length),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: query.substring(at + typed.length)),
            ],
          );
    return ShellButton(
      onTap: onTap,
      label: query,
      builder: (context, hovered) => Container(
        constraints: BoxConstraints(minHeight: table ? 36 : 50),
        decoration: BoxDecoration(
          color: hovered ? colors.cellHover : null,
          borderRadius: BorderRadius.circular(table ? 8 : 0),
        ),
        child: Stack(
          children: [
            if (separator && !table)
              Positioned(
                top: 0,
                left: 50,
                right: 0,
                height: .5,
                child: ColoredBox(color: colors.sep),
              ),
            Padding(
              padding: EdgeInsets.only(left: table ? 10 : 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: FmpIcon(
                      FmpIcons.history,
                      size: table ? 16 : 20,
                      color: colors.label3,
                    ),
                  ),
                  SizedBox(width: table ? 10 : 12),
                  Expanded(
                    child: Text.rich(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  PlainIconButton(
                    icon: FmpIcons.close,
                    tooltip: context.t.search.history.remove,
                    size: table ? 28 : 44,
                    onTap: onRemove,
                  ),
                  SizedBox(width: table ? 4 : 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音源篩選與排序（`.srh-fil`、`.srh-dfil`）：篩選 chip 可以橫向捲，排序鈕
/// 固定在同一排最右（設計稿〈待確認〉2）。桌面寬版的 chip 帶數量，[hints]
/// 放在排序鈕前面。
class SearchFilterBar extends ConsumerWidget {
  const SearchFilterBar({
    super.key,
    required this.search,
    required this.filter,
    required this.table,
    required this.onFilter,
    this.hints,
  });

  final SearchState search;
  final String? filter;
  final bool table;
  final ValueChanged<String?> onFilter;
  final Widget? hints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final sources = search.sources;
    final visible = [
      for (final s in sources)
        if (filter == null || s.manifest.id == filter) s.manifest,
    ];
    final sorts = sortsOf(visible);
    final chips = [
      _Chip(
        label: t.search.all,
        on: filter == null,
        table: table,
        count: table ? search.tracks.length : null,
        onTap: () => onFilter(null),
      ),
      for (final s in sources)
        _Chip(
          label: s.manifest.name,
          pluginId: s.manifest.id,
          on: filter == s.manifest.id,
          table: table,
          warn: s.error != null,
          count: table ? s.tracks.length : null,
          onTap: () => onFilter(s.manifest.id),
        ),
    ];
    final sort = sorts.length < 2
        ? null
        : _SortButton(
            sorts: sorts,
            current: search.sort ?? sorts.first,
            table: table,
          );
    if (table) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              chip,
            ],
            const Spacer(),
            ?hints,
            if (sort != null) ...[const SizedBox(width: 14), sort],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                colors: const [Color(0xFF000000), Color(0x00000000)],
                stops: [(rect.width - 20) / rect.width, 1],
              ).createShader(rect),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 20, right: 8),
                child: Row(
                  children: [
                    for (final (i, chip) in chips.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      chip,
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (sort != null)
            Padding(padding: const EdgeInsets.only(right: 16), child: sort),
        ],
      ),
    );
  }
}

/// 篩選 chip（`.chip`）：選中的是實心 `--label` 底；出錯的音源帶警示符號。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.on,
    required this.table,
    required this.onTap,
    this.pluginId,
    this.count,
    this.warn = false,
  });

  final String label;
  final bool on;
  final bool table;
  final VoidCallback onTap;
  final String? pluginId;
  final int? count;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final ink = on ? colors.bg : colors.label;
    return Semantics(
      selected: on,
      child: ShellButton(
        onTap: onTap,
        label: label,
        builder: (context, hovered) => Container(
          height: table ? 26 : 32,
          padding: EdgeInsets.symmetric(horizontal: table ? 11 : 13),
          decoration: BoxDecoration(
            color: on ? colors.label : (hovered ? colors.fill2 : colors.fill),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pluginId case final id?) ...[
                SourceMarkIcon(pluginId: id, size: table ? 13 : 15),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: table ? 12.5 : 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: ink,
                ),
              ),
              if (warn) ...[
                const SizedBox(width: 6),
                FmpIcon(
                  FmpIcons.warn,
                  size: table ? 14 : 16,
                  color: on ? ink : colors.warn,
                ),
              ] else if (count case final count?) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: ink.withValues(alpha: .6),
                  ).tabular,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String sortLabel(Translations t, SearchSort sort) => switch (sort) {
  SearchSort.relevance => t.search.sort.relevance,
  SearchSort.viewCount => t.search.sort.viewCount,
  SearchSort.date => t.search.sort.date,
};

/// 排序鈕（`.srh-sortc`）：外框膠囊，寫目前的排序；點了從它長出選單，只列
/// 插件宣告的排序。
class _SortButton extends ConsumerWidget {
  const _SortButton({
    required this.sorts,
    required this.current,
    required this.table,
  });

  final List<SearchSort> sorts;
  final SearchSort current;
  final bool table;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final label = sortLabel(t, current);
    return ShellButton(
      label: t.search.sort.label(sort: label),
      onTap: () async {
        final box = context.findRenderObject()! as RenderBox;
        final chosen = await showGlassMenu<SearchSort>(
          context: context,
          // 右緣對齊排序鈕（鈕在一排的最右邊，選單往左長）。
          at: box.localToGlobal(box.size.bottomRight(Offset.zero)),
          entries: [
            for (final sort in sorts)
              GlassMenuItem(
                value: sort,
                label: sortLabel(t, sort),
                checked: sort == current,
              ),
          ],
        );
        // 選打勾的那項（沒選過時是插件的預設）不重搜。
        if (chosen != null && chosen != current) {
          await ref.read(searchProvider.notifier).sortBy(chosen);
        }
      },
      builder: (context, hovered) => Container(
        height: table ? 26 : 32,
        padding: const EdgeInsets.only(left: 10, right: 8),
        decoration: BoxDecoration(
          color: hovered ? colors.cellHover : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.sepStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FmpIcon(FmpIcons.sort, size: 15, color: colors.label2),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: table ? 12 : 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: colors.label,
              ),
            ),
            const SizedBox(width: 3),
            FmpIcon(FmpIcons.chevD, size: 15, color: colors.label2),
          ],
        ),
      ),
    );
  }
}

/// 桌面的快速鍵提示（`.hint`）：「雙擊 臨時播放」「⌘ 點選多選」「右鍵 更多」。
class SearchKeyHints extends StatelessWidget {
  const SearchKeyHints({super.key, required this.commandKey});

  /// ⌘ 或 Ctrl。
  final String commandKey;

  @override
  Widget build(BuildContext context) {
    final t = context.t.search.hints;
    final colors = context.fmpColors;
    Widget hint(String key, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: colors.label2,
            ).tabular,
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            letterSpacing: 0,
            color: colors.label3,
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 12,
      children: [
        hint(t.doubleClick, t.play),
        hint(commandKey, t.multiSelect),
        hint(t.rightClick, t.more),
      ],
    );
  }
}

/// 桌面與平板的浮動動作列（`.srh-dact`）：「已選擇 n 首｜下一首播放｜加入
/// 佇列｜×」，玻璃膠囊、在內容欄置中。
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onAction,
    required this.onClear,
  });

  final int count;
  final ValueChanged<TrackAction> onAction;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    Widget action(FmpIcons icon, String label, TrackAction value) =>
        ShellButton(
          onTap: () => onAction(value),
          label: label,
          builder: (context, hovered) => Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hovered ? colors.glassPress : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FmpIcon(icon, size: 16, color: colors.glassInk),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: colors.glassInk,
                  ),
                ),
              ],
            ),
          ),
        );
    return Glass(
      radius: 22,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.search.selection.selected(count: count),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: colors.glassInk,
                ),
              ),
              const SizedBox(width: 10),
              action(
                FmpIcons.nextUp,
                t.queue.actions.playNext,
                TrackAction.playNext,
              ),
              const SizedBox(width: 2),
              action(
                FmpIcons.queue,
                t.queue.actions.addToQueue,
                TrackAction.addToQueue,
              ),
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: colors.glassInk.withValues(alpha: .14),
              ),
              PlainIconButton(
                icon: FmpIcons.close,
                tooltip: t.search.selection.clear,
                size: 32,
                onTap: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手機的浮動動作列（`.srh-act`）：取代 dock 與迷你播放器，每個動作是圖示
/// 加小字。
class PhoneSelectionBar extends StatelessWidget {
  const PhoneSelectionBar({super.key, required this.onAction});

  final ValueChanged<TrackAction> onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    Widget action(FmpIcons icon, String label, TrackAction value) => Expanded(
      child: ShellButton(
        onTap: () => onAction(value),
        label: label,
        builder: (context, pressed) => Container(
          height: 56,
          decoration: BoxDecoration(
            color: pressed ? colors.glassPress : null,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FmpIcon(icon, size: 23, color: colors.glassInk),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: colors.glassInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Glass(
      radius: 32,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              action(
                FmpIcons.nextUp,
                t.queue.actions.playNext,
                TrackAction.playNext,
              ),
              action(
                FmpIcons.queue,
                t.queue.actions.addToQueue,
                TrackAction.addToQueue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手機多選時的頂列文字膠囊（`.srh-gtext`）：「取消」「全選」。
class GlassTextButton extends StatelessWidget {
  const GlassTextButton({
    super.key,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return ShellButton(
      onTap: onTap,
      label: label,
      builder: (context, _) => Glass(
        radius: 22,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: accent ? colors.accent : colors.glassInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// 沒有底色的文字鈕（`.btn.btn-plain.btn-sm`）：搜尋紀錄的「清空」。
class PlainTextButton extends StatelessWidget {
  const PlainTextButton({
    super.key,
    required this.label,
    required this.table,
    required this.onTap,
  });

  final String label;
  final bool table;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return ShellButton(
      onTap: onTap,
      label: label,
      builder: (context, hovered) => Container(
        height: table ? 28 : 32,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: table ? 12.5 : 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: hovered ? colors.label2 : colors.label,
          ),
        ),
      ),
    );
  }
}
