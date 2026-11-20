import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 搜尋欄放在哪裡，決定它的樣子（`docs/design/search.html`、`shell.html`）。
enum SearchFieldPlacement {
  /// 手機的 dock：玻璃上的大欄位（17pt）。
  dock,

  /// 桌面側欄頂端（30pt，⌘K）。
  sidebar,

  /// 中寬度搜尋頁的頂端（細欄只有搜尋項目）。
  page,
}

/// 搜尋欄：文字在 [searchQueryProvider]，送出時搜尋。[onTap] 在點欄位時呼叫
/// （桌面側欄要先進搜尋頁），[onFocusChanged] 回報焦點（手機鍵盤升起時 dock
/// 換形狀）。
class SearchField extends ConsumerStatefulWidget {
  const SearchField({
    super.key,
    required this.placement,
    this.onTap,
    this.onFocusChanged,
    this.onSubmitted,
    this.active = false,
  });

  final SearchFieldPlacement placement;

  /// 在搜尋頁上：側欄的欄位照稿加強調色外框（`.sfield.on`）。
  final bool active;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    // 進搜尋頁之前就要求了焦點（中寬度按 ⌘K）：建出來後接手。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(searchFocusRequestProvider)) _takeFocus();
    });
  }

  void _takeFocus() {
    ref.read(searchFocusRequestProvider.notifier).consume();
    _focus.requestFocus();
    // 從側欄的欄位點進搜尋頁時，新頁的路由在 push 之後才拿焦點（它的
    // focus scope）：下一個 frame 再要回來，游標留在欄位裡。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  void _focusChanged() {
    widget.onFocusChanged?.call(_focus.hasFocus);
    setState(() {});
  }

  void _submit() {
    submitSearch(ref);
    widget.onSubmitted?.call();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(searchFocusRequestProvider, (_, pending) {
      if (pending) _takeFocus();
    });
    final controller = ref.watch(searchQueryProvider);
    final t = context.t;
    final colors = context.fmpColors;
    final placement = widget.placement;
    final touch = FormFactor.of(context).density == Density.touch;
    final onGlass = placement != SearchFieldPlacement.page;
    final ink = onGlass ? colors.glassInk : colors.label;
    final ink2 = onGlass ? colors.glassInk2 : colors.label2;
    final (double fontSize, double iconSize, double gap) = switch (placement) {
      SearchFieldPlacement.dock => (17, 21, 10),
      SearchFieldPlacement.sidebar => (13, 15, 6),
      SearchFieldPlacement.page when touch => (16, 18, 8),
      SearchFieldPlacement.page => (13, 18, 8),
    };
    // 看得到的欄位高，與點得到的高（`DESIGN.md`〈無障礙〉：觸控 44、滑鼠
    // 28）：輸入框撐滿點擊區，點欄位的上下空白也會聚焦，螢幕閱讀器的框也是
    // 這麼大。觸控比欄位高的部分是透明的，上下各一半。
    final visual = switch (placement) {
      SearchFieldPlacement.dock => 44.0,
      SearchFieldPlacement.sidebar => 30.0,
      SearchFieldPlacement.page => touch ? 40.0 : 30.0,
    };
    final hit = touch ? math.max(visual, 44.0) : visual;
    final field = TextField(
      controller: controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _submit(),
      onTap: widget.onTap,
      style: TextStyle(fontSize: fontSize, color: ink),
      cursorColor: colors.accent,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration.collapsed(
        constraints: BoxConstraints(minHeight: hit),
        hintText: t.shell.search.hint,
        hintStyle: TextStyle(
          fontSize: fontSize,
          color: placement == SearchFieldPlacement.page ? colors.label3 : ink2,
        ),
      ),
    );
    final trailing = switch (placement) {
      SearchFieldPlacement.dock => _ClearButton(
        controller: controller,
        tapSize: 44,
        dot: 22,
        icon: 13,
        fill: colors.glassInk.withValues(alpha: .18),
        color: colors.glassInk,
      ),
      // 點擊區 44（`DESIGN.md`〈無障礙〉；稿 28），看得到的圓點照稿。
      SearchFieldPlacement.page when touch => _ClearButton(
        controller: controller,
        tapSize: 44,
        dot: 18,
        icon: 11,
        fill: colors.fill2,
        color: colors.label2,
      ),
      _ => _Kbd(
        WindowChrome.shortcutLabel('K'),
        color: ink2,
        boxed: placement == SearchFieldPlacement.page,
      ),
    };
    final row = Row(
      children: [
        FmpIcon(FmpIcons.search, size: iconSize, color: ink2),
        SizedBox(width: gap),
        Expanded(child: field),
        trailing,
      ],
    );
    return switch (placement) {
      SearchFieldPlacement.dock => Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: row,
      ),
      SearchFieldPlacement.sidebar => _Field(
        visual: visual,
        hit: hit,
        padding: 9,
        pill: Container(
          decoration: BoxDecoration(
            color: colors.glassInk.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(9),
          ),
          // 作用中時的強調色外框（稿是 inset box-shadow，不推擠內容）。外框
          // 一直都在、不作用時透明：換成 null 會讓 Container 少一層，整個
          // TextField 重建，點擊的手勢與輸入連線跟著丟掉（點一下只聚焦、
          // 進頁後打不進字）。
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: widget.active || _focus.hasFocus
                  ? colors.accent
                  : colors.accent.withValues(alpha: 0),
              width: 1.5,
            ),
          ),
        ),
        row: row,
      ),
      SearchFieldPlacement.page => SizedBox(
        width: touch ? null : 360,
        child: _Field(
          visual: visual,
          hit: hit,
          padding: 12,
          pill: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.fill,
              borderRadius: BorderRadius.circular(touch ? 12 : 8),
            ),
          ),
          row: row,
        ),
      ),
    };
  }
}

/// 欄位：[visual] 高的底（[pill]）在 [hit] 高的點擊區正中，[row] 撐滿點擊區。
class _Field extends StatelessWidget {
  const _Field({
    required this.visual,
    required this.hit,
    required this.padding,
    required this.pill,
    required this.row,
  });

  final double visual;
  final double hit;
  final double padding;
  final Widget pill;
  final Widget row;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: hit,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned(left: 0, right: 0, height: visual, child: pill),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: row,
        ),
      ],
    ),
  );
}

/// 有字時才出現的清除鈕：圓點裡一個 ×，點擊區 [tapSize]。
class _ClearButton extends StatelessWidget {
  const _ClearButton({
    required this.controller,
    required this.tapSize,
    required this.dot,
    required this.icon,
    required this.fill,
    required this.color,
  });

  final TextEditingController controller;
  final double tapSize;
  final double dot;
  final double icon;
  final Color fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.text.isEmpty) return SizedBox(width: tapSize);
        final label = context.t.shell.search.clear;
        return ShellButton(
          tooltip: label,
          label: label,
          onTap: controller.clear,
          focusRadius: 999,
          builder: (context, _) => SizedBox.square(
            dimension: tapSize,
            child: Center(
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: FmpIcon(
                  FmpIcons.close,
                  size: icon,
                  color: color,
                  strokeWidth: 2.6,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 快捷鍵提示（`kbd`）。
class _Kbd extends StatelessWidget {
  const _Kbd(this.label, {required this.color, required this.boxed});

  final String label;
  final Color color;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: context.fmpText.cap2.tabular.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: boxed ? context.fmpColors.label2 : color.withValues(alpha: .8),
      ),
    );
    if (!boxed) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: context.fmpColors.fill2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: text,
    );
  }
}
