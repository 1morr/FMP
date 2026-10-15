import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/debug/debug_database.dart';
import 'package:fmp/ui/debug/debug_health.dart';
import 'package:fmp/ui/debug/debug_log.dart';
import 'package:fmp/ui/debug/debug_network.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/debug/debug_overview.dart';
import 'package:fmp/ui/debug/debug_playback.dart';
import 'package:fmp/ui/debug/debug_plugin_dev.dart';
import 'package:fmp/ui/debug/debug_reset.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的區塊，依清單上的順序。ADR 0025 §決定 2 的表有八個，各自跟著實作它的 PR
/// 加（之前不放空殼）：[pluginDev] 只在平台宣告 `pluginDevTools` 時列出。新的區塊照表上
/// 的順序插進來。
enum DebugSection {
  overview(Icons.dashboard_outlined),
  log(Icons.article_outlined),
  network(Icons.swap_vert),
  playback(Icons.graphic_eq),
  health(Icons.health_and_safety_outlined),
  pluginDev(Icons.extension_outlined),
  database(Icons.storage_outlined),
  reset(Icons.restart_alt);

  const DebugSection(this.icon);

  final IconData icon;
}

/// 從設定頁開 Debug 頁（ADR 0025 §決定 1、2）。[onShowCacheSettings] 是概覽的「快取用量」：
/// 頁面先關掉自己再呼叫它（設定頁選「網路」）。推在根 Navigator 上：設定頁在外殼的巢狀
/// 導覽裡，Debug 頁不在外殼底下（播放類快捷鍵在這一頁不作用）。
Future<void> openDebugPage(
  BuildContext context, {
  required VoidCallback onShowCacheSettings,
}) => Navigator.of(context, rootNavigator: true).push(
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

  /// 「查看 log」帶進 Log 區塊的 tag 篩選（插件 id）；從清單點 Log 時是 `null`。
  String? _logTag;

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
    // 平台沒有插件開發工具：清單與內容都沒有這一塊（ADR 0025 §如何確認）。
    final sections = _sections(ref.watch(platformCapabilitiesProvider));
    final selected = _selected != null && sections.contains(_selected)
        ? _selected
        : null;
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
            ? _body(t.debug, sections, narrow: narrow, selected: selected)
            : const SizedBox.shrink(),
      ),
    );
  }

  static List<DebugSection> _sections(PlatformCapabilities capabilities) => [
    for (final section in DebugSection.values)
      if (section != DebugSection.pluginDev || capabilities.pluginDevTools)
        section,
  ];

  void _viewLog(String pluginId) => setState(() {
    _logTag = pluginId;
    _selected = DebugSection.log;
  });

  Widget _body(
    Translations$debug$zh_TW t,
    List<DebugSection> sections, {
    required bool narrow,
    required DebugSection? selected,
  }) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    Widget list(DebugSection? selected) => ListView(
      children: [
        for (final section in sections)
          ListTile(
            leading: Icon(section.icon),
            title: Text(_name(t, section)),
            selected: section == selected,
            onTap: () => setState(() {
              _selected = section;
              _logTag = null;
            }),
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
            // key：換 tag 就重建，篩選才會重設成新的 tag。
            DebugLog(key: ValueKey(_logTag), initialTag: _logTag),
            heading: heading,
          ),
          DebugSection.network => filling(
            section,
            const DebugNetwork(),
            heading: heading,
          ),
          DebugSection.playback => filling(
            section,
            const DebugPlayback(),
            heading: heading,
          ),
          DebugSection.health => filling(
            section,
            const DebugHealth(),
            heading: heading,
          ),
          DebugSection.pluginDev => filling(
            section,
            DebugPluginDev(onViewLog: _viewLog),
            heading: heading,
          ),
          DebugSection.database => filling(
            section,
            const DebugDatabase(),
            heading: heading,
          ),
          DebugSection.reset => SingleChildScrollView(
            padding: EdgeInsets.all(spacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (heading) ...[title(section), SizedBox(height: spacing.x4)],
                const DebugReset(),
              ],
            ),
          ),
        };
    if (narrow) {
      return selected == null ? list(null) : detail(selected, heading: false);
    }
    final shown = selected ?? sections.first;
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
        DebugSection.playback => t.playback,
        DebugSection.health => t.health,
        DebugSection.pluginDev => t.pluginDev,
        DebugSection.database => t.database,
        DebugSection.reset => t.reset,
      };
}
