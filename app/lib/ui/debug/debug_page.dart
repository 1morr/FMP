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
import 'package:fmp/ui/layout/list_detail_routes.dart';
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
/// 右邊那一塊的內容，預設第一個；更窄時先是清單，點進去的那一塊推在根 Navigator 上
/// （[ListDetailRoutes]，同設定頁），標題列的返回鈕、系統返回鍵、iOS 右滑都回到清單。這一頁沒有
/// `PopScope`。
class DebugPage extends ConsumerStatefulWidget {
  const DebugPage({super.key, required this.onShowCacheSettings});

  final VoidCallback onShowCacheSettings;

  @override
  ConsumerState<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends ConsumerState<DebugPage>
    with ListDetailRoutes<DebugPage, DebugSection> {
  /// 「查看 log」帶進 Log 區塊的 tag 篩選（插件 id）；從清單點 Log 時是 `null`。
  String? _logTag;

  var _leaving = false;

  /// 開發者模式關著：在這一幀之後關掉這一頁（連同窄版推上去的那一塊）。在最上層就 pop（有轉場），
  /// 被蓋住了（例如對話框還開著）就直接移除。
  void _leave() {
    if (_leaving) return;
    _leaving = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      removeDetail();
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        route.navigator?.pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    });
  }

  /// 概覽的「快取用量」：關掉這一頁（窄版先拿掉那一塊）再請設定頁選「網路」。
  void _showCacheSettings() {
    removeDetail();
    Navigator.of(context).pop();
    widget.onShowCacheSettings();
  }

  void _open(DebugSection section) {
    _logTag = null;
    select(section);
  }

  void _viewLog(String pluginId) {
    _logTag = pluginId;
    select(DebugSection.log);
  }

  @override
  Widget buildDetailPage(BuildContext context, DebugSection item) => Consumer(
    builder: (context, ref, _) {
      final t = ref.watch(translationsProvider).debug;
      // 被這一頁蓋住的 Debug 頁看不到設定的變化（Riverpod 暫停看不見的 widget 的訂閱）：路由閘門
      // 在這裡也要看一次。
      final developer = ref.watch(developerProvider);
      if (developer is AsyncError || developer.value?.developerMode == false) {
        _leave();
      }
      return Scaffold(
        appBar: AppBar(title: Text(_name(t, item))),
        body: _detail(context, t, item, heading: false),
      );
    },
  );

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
    syncNarrow(narrow: narrow);
    // 平台沒有插件開發工具：清單與內容都沒有這一塊（ADR 0025 §如何確認）。
    final sections = _sections(ref.watch(platformCapabilitiesProvider));
    final chosen = selected != null && sections.contains(selected)
        ? selected
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(t.debug.title)),
      body: open == true && !_leaving
          ? _body(t.debug, sections, narrow: narrow, selected: chosen)
          : const SizedBox.shrink(),
    );
  }

  static List<DebugSection> _sections(PlatformCapabilities capabilities) => [
    for (final section in DebugSection.values)
      if (section != DebugSection.pluginDev || capabilities.pluginDevTools)
        section,
  ];

  Widget _body(
    Translations$debug$zh_TW t,
    List<DebugSection> sections, {
    required bool narrow,
    required DebugSection? selected,
  }) {
    Widget list(DebugSection? selected) => ListView(
      children: [
        for (final section in sections)
          ListTile(
            leading: Icon(section.icon),
            title: Text(_name(t, section)),
            selected: section == selected,
            onTap: () => _open(section),
          ),
      ],
    );
    if (narrow || detailOpen) return list(null);
    final shown = selected ?? sections.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: AppLayout.settingsListWidth, child: list(shown)),
        const VerticalDivider(),
        Expanded(child: _detail(context, t, shown, heading: true)),
      ],
    );
  }

  /// 一塊的內容；寬版的右欄（[heading] 是區塊名）與窄版推上去的那一頁共用。
  Widget _detail(
    BuildContext context,
    Translations$debug$zh_TW t,
    DebugSection section, {
    required bool heading,
  }) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    Widget title() => Semantics(
      header: true,
      child: Text(_name(t, section), style: theme.textTheme.titleLarge),
    );
    // Log 與網路自己有捲動的清單：不包在捲動的欄裡，填滿剩下的高度（設定頁的 `filling`）。
    Widget filling(Widget page) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading)
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
            child: title(),
          ),
        Expanded(child: page),
      ],
    );
    Widget scrolling(Widget child) => SingleChildScrollView(
      padding: EdgeInsets.all(spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading) ...[title(), SizedBox(height: spacing.x4)],
          child,
        ],
      ),
    );
    return switch (section) {
      DebugSection.overview => scrolling(
        DebugOverview(onShowCacheSettings: _showCacheSettings),
      ),
      // key：換 tag 就重建，篩選才會重設成新的 tag。
      DebugSection.log => filling(
        DebugLog(key: ValueKey(_logTag), initialTag: _logTag),
      ),
      DebugSection.network => filling(const DebugNetwork()),
      DebugSection.playback => filling(const DebugPlayback()),
      DebugSection.health => filling(const DebugHealth()),
      DebugSection.pluginDev => filling(DebugPluginDev(onViewLog: _viewLog)),
      DebugSection.database => filling(const DebugDatabase()),
      DebugSection.reset => scrolling(const DebugReset()),
    };
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
