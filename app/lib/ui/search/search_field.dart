import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/ui/search/search_query.dart';
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
    final field = TextField(
      controller: controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _submit(),
      onTap: widget.onTap,
      style: TextStyle(fontSize: fontSize, color: ink),
      cursorColor: colors.accent,
      decoration: InputDecoration.collapsed(
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
      SearchFieldPlacement.page when touch => _ClearButton(
        controller: controller,
        tapSize: 28,
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
      SearchFieldPlacement.sidebar => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: colors.glassInk.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(9),
        ),
        // 作用中時的強調色外框（稿是 inset box-shadow，不推擠內容）。
        foregroundDecoration: widget.active || _focus.hasFocus
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: colors.accent, width: 1.5),
              )
            : null,
        child: row,
      ),
      SearchFieldPlacement.page => Container(
        height: touch ? 40 : 30,
        width: touch ? null : 360,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(touch ? 12 : 8),
        ),
        child: row,
      ),
    };
  }
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
        return Tooltip(
          message: context.t.shell.search.clear,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.clear,
            child: SizedBox.square(
              dimension: tapSize,
              child: Center(
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                  ),
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
