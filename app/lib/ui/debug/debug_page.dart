import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/debug/debug_log.dart';
import 'package:fmp/ui/debug/debug_network.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/debug/debug_overview.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的區塊，依清單上的順序。ADR 0025 §決定 2 的表有八個，各自跟著實作它的 PR
/// 加（之前不放空殼）：播放狀態、資料庫、重設資料（M3 PR 14），音源健康檢查、插件開發
/// （PR 16；插件開發只在平台宣告 `pluginDevTools` 時列出）。新的區塊照表上的順序插進來。
enum DebugSection {
  overview(Icons.dashboard_outlined),
  log(Icons.article_outlined),
  network(Icons.swap_vert);

  const DebugSection(this.icon);

  final IconData icon;
}

/// 從設定頁開 Debug 頁（ADR 0025 §決定 1、2）。[onShowCacheSettings] 是概覽的「快取用量」：
/// 頁面先關掉自己再呼叫它（設定頁選「網路」）。
Future<void> openDebugPage(
  BuildContext context, {
  required VoidCallback onShowCacheSettings,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => DebugPage(onShowCacheSettings: onShowCacheSettings),
  ),
);

/// Debug 頁：開發者模式的工具（ADR 0025）。
///
/// 路由閘門：開發者模式關閉時（直接開進來，或在概覽關掉總開關）頁面不顯示內容並關掉
/// 自己，回到開它的設定頁（ADR 0025 §決定 1）。設定還沒讀出來時也不顯示內容。
///
/// 版面照設定頁的 list-detail（ADR 0024 §決定 6）：整個視窗 expanded 以上左邊區塊清單、
/// 右邊那一塊的內容，預設第一個；更窄時先是清單，點進去看內容，標題列的返回鈕與系統返回鍵
/// 回到清單。這一頁是自己的 route、不在外殼底下，返回鍵由這一頁的 `PopScope` 接：外殼的
/// `PopScope` 在下面那個 route，這時不會同時動作。
class DebugPage extends ConsumerStatefulWidget {
  const DebugPage({super.key, required this.onShowCacheSettings});

  final VoidCallback onShowCacheSettings;

  @override
  ConsumerState<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends ConsumerState<DebugPage> {
  /// 使用者點進去的那一塊；`null` 是還沒選（窄版顯示清單，寬版用第一個）。
  DebugSection? _selected;

  var _leaving = false;

  /// 開發者模式關著：在這一幀之後關掉這一頁。在最上層就 pop（有轉場），被蓋住了（例如
  /// 對話框還開著）就直接移除。
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    });
  }

  void _showCacheSettings() {
    Navigator.of(context).pop();
    widget.onShowCacheSettings();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final developer = ref.watch(developerProvider);
    final open = developer.value?.developerMode;
    if (developer is AsyncError || open == false) _leave();
    final narrow = switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => true,
      _ => false,
    };
    final selected = _selected;
    final inSection = narrow && selected != null;
    return PopScope(
      canPop: !inSection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(inSection ? _name(t.debug, selected) : t.debug.title),
          leading: inSection
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: t.settings.back,
                  onPressed: () => setState(() => _selected = null),
                )
              : null,
        ),
        body: open == true && !_leaving
            ? _body(t.debug, narrow: narrow, selected: selected)
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _body(
    Translations$debug$zh_TW t, {
    required bool narrow,
    required DebugSection? selected,
  }) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    Widget list(DebugSection? selected) => ListView(
      children: [
        for (final section in DebugSection.values)
          ListTile(
            leading: Icon(section.icon),
            title: Text(_name(t, section)),
            selected: section == selected,
            onTap: () => setState(() => _selected = section),
          ),
      ],
    );
    Widget title(DebugSection section) => Semantics(
      header: true,
      child: Text(_name(t, section), style: theme.textTheme.titleLarge),
    );
    // Log 與網路自己有捲動的清單：不包在捲動的欄裡，填滿剩下的高度（設定頁的 `filling`）。
    Widget filling(
      DebugSection section,
      Widget page, {
      required bool heading,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading)
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
            child: title(section),
          ),
        Expanded(child: page),
      ],
    );
    Widget detail(DebugSection section, {required bool heading}) =>
        switch (section) {
          DebugSection.overview => SingleChildScrollView(
            padding: EdgeInsets.all(spacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heading) ...[title(section), SizedBox(height: spacing.x4)],
                DebugOverview(onShowCacheSettings: _showCacheSettings),
              ],
            ),
          ),
          DebugSection.log => filling(
            section,
            const DebugLog(),
            heading: heading,
          ),
          DebugSection.network => filling(
            section,
            const DebugNetwork(),
            heading: heading,
          ),
        };
    if (narrow) {
      return selected == null ? list(null) : detail(selected, heading: false);
    }
    final shown = selected ?? DebugSection.values.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: AppLayout.settingsListWidth, child: list(shown)),
        const VerticalDivider(),
        Expanded(child: detail(shown, heading: true)),
      ],
    );
  }

  static String _name(Translations$debug$zh_TW t, DebugSection section) =>
      switch (section) {
        DebugSection.overview => t.overview,
        DebugSection.log => t.log,
        DebugSection.network => t.network,
      };
}
