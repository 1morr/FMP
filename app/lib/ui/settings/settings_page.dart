import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/accounts/accounts_section.dart';
import 'package:fmp/ui/debug/debug_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/list_detail_routes.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:fmp/ui/settings/about_section.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/backup_controls.dart';
import 'package:fmp/ui/settings/library_controls.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/settings/playback_controls.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定頁的區塊，依清單上的順序（M3 design §6.7、M4 design §10.10）。外觀、播放、網路是
/// ADR 0011 的設定組；音樂庫是每個榜單的設定（`chart_settings`，之後加每音源的匹配目標），
/// 不是單列的設定組；帳號、插件、關於不是設定表，是帳號頁（ADR 0029 §決定 8）、插件頁（ADR 0030
/// §決定 11）、備份與還原（ADR 0034 §決定 5）與版本列（ADR 0024 §決定 9），同樣以 list-detail 呈現。開發者模式下清單最後
/// 多一列 Debug：它開另一個 route（Debug 頁），不是區塊。
enum SettingsSection {
  accounts(Icons.account_circle_outlined),
  appearance(Icons.palette_outlined),
  playback(Icons.play_circle_outline),
  // 不用導覽列音樂庫的圖示：整合測試以圖示找導覽項。
  library(Icons.queue_music),
  network(Icons.public),
  plugins(Icons.extension_outlined),
  backup(Icons.backup_outlined),
  about(Icons.info_outline);

  const SettingsSection(this.icon);

  final IconData icon;
}

/// 外殼要設定頁顯示某一組（搜尋頁的「前往插件頁」、帳號失效提示的「登入」、Debug 頁的快取用量）。
///
/// 外殼在建構時給設定頁一個，之後設定頁的 State 接上 [show]；不是會變的狀態，所以不是 provider（同
/// `OpenAccounts`）。返回鍵不經這裡：窄版點進的組是巢狀 Navigator 上的 route，外殼的「退出內頁」就退得掉。
final class SettingsOpener {
  void Function(SettingsSection section) _show = (_) {};

  /// 設定頁選到 [section]：寬版右欄換成它，窄版推它的 route。
  void show(SettingsSection section) => _show(section);
}

String _groupName(Translations$settings$zh_TW t, SettingsSection group) =>
    switch (group) {
      SettingsSection.accounts => t.accounts,
      SettingsSection.appearance => t.appearance,
      SettingsSection.playback => t.playback,
      SettingsSection.library => t.library,
      SettingsSection.network => t.network,
      SettingsSection.plugins => t.plugins,
      SettingsSection.backup => t.backup,
      SettingsSection.about => t.about,
    };

/// 設定頁（ADR 0024 §決定 6、ADR 0011 §決定 7 的分組）。
///
/// expanded 以上是 M3 canonical layout 的 list-detail：左邊分組清單、右邊那一組
/// 的內容，預設選第一組。更窄時一次只有一欄：先是分組清單，點進去的那一組推在設定目的地的
/// 巢狀 Navigator 上（[ListDetailRoutes]；擁有者決定 2026-11-04），所以返回鈕、系統返回鍵、Esc、
/// iOS 右滑都回到清單。選了哪一組由頁面記著，視窗寬度跨過斷點時不丟。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.visible, required this.opener});

  /// 外殼目前顯示的是不是這一頁。外殼以 `IndexedStack` 留著沒選的頁面，看不到時
  /// 「關於」的連點計數歸零。
  final bool visible;

  /// 外殼要它顯示某一組時經這裡（[SettingsOpener]）。
  final SettingsOpener opener;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with ListDetailRoutes<SettingsPage, SettingsSection> {
  /// [SettingsPage.visible]，給窄版推上去的那一組（route 不隨這一頁重建）。
  late final _visible = ValueNotifier(widget.visible);

  @override
  void initState() {
    super.initState();
    widget.opener._show = select;
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.opener._show = select;
    // 那一組在另一個 route 上：build 中不能叫它重建，排到這一幀之後。
    if (oldWidget.visible != widget.visible) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _visible.value = widget.visible;
      });
    }
  }

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget buildDetailPage(BuildContext context, SettingsSection item) =>
      _GroupPage(group: item, visible: _visible, onOpenPlugins: _openPlugins);

  void _openPlugins() => select(SettingsSection.plugins);

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider);
    final t = translations.settings;
    final narrow = switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => true,
      WindowClass.expanded ||
      WindowClass.large ||
      WindowClass.extraLarge => false,
    };
    syncNarrow(narrow: narrow);
    final developerMode =
        ref.watch(developerProvider).value?.developerMode ?? false;
    final appearance = ref.watch(appearanceProvider).value;
    final playback = ref.watch(playbackPreferencesProvider).value;
    // 分組列的一行摘要（L-33）：只有設定值能一句話說完的組有；其餘（帳號、音樂庫、
    // 網路、插件、備份、關於）沒有摘要，不放副標。設定還沒讀出來時也不放。
    String? summary(SettingsSection group) {
      final s = t.summary;
      final tAppearance = translations.appearance;
      final tPlayback = translations.playback;
      return switch (group) {
        SettingsSection.appearance when appearance != null => () {
          final theme = switch (appearance.themeMode) {
            ThemeModeSetting.system => tAppearance.themeSystem,
            ThemeModeSetting.light => tAppearance.themeLight,
            ThemeModeSetting.dark => tAppearance.themeDark,
          };
          final font = appearance.fontFamily;
          return font == null
              ? s.appearance(theme: theme)
              : s.appearanceWithFont(
                  theme: theme,
                  font: fontDisplayName(tAppearance, font),
                );
        }(),
        SettingsSection.playback when playback != null => s.playback(
          quality: switch (playback.audioQuality) {
            AudioQuality.high => tPlayback.qualityHigh,
            AudioQuality.medium => tPlayback.qualityMedium,
            AudioQuality.low => tPlayback.qualityLow,
          },
        ),
        _ => null,
      };
    }

    // 清單會捲動：開發者模式下有九列，矮的視窗（橫向的手機）放不下。
    Widget list(SettingsSection? selected) => ListView(
      children: [
        for (final group in SettingsSection.values)
          ListTile(
            leading: Icon(group.icon),
            title: Text(_groupName(t, group)),
            subtitle: switch (summary(group)) {
              final text? => Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              null => null,
            },
            selected: group == selected,
            onTap: () => select(group),
          ),
        if (developerMode)
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(t.debug),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(
              openDebugPage(
                context,
                // 外殼的 SettingsOpener 指向目前的 State：Debug 頁開著時這一頁可能換位置重建。
                onShowCacheSettings: () =>
                    widget.opener.show(SettingsSection.network),
              ),
            ),
          ),
      ],
    );
    if (narrow || detailOpen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageAppBar(title: t.title),
          Expanded(child: list(null)),
        ],
      );
    }
    final shown = selected ?? SettingsSection.values.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageAppBar(title: t.title),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: AppLayout.settingsListWidth, child: list(shown)),
              const VerticalDivider(),
              Expanded(
                child: _GroupDetail(
                  group: shown,
                  heading: true,
                  visible: widget.visible,
                  onOpenPlugins: _openPlugins,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 窄版推上去的那一組：頁頂是組名（巢狀導覽的內頁，[PageAppBar] 自己放返回鈕）。
class _GroupPage extends ConsumerWidget {
  const _GroupPage({
    required this.group,
    required this.visible,
    required this.onOpenPlugins,
  });

  final SettingsSection group;
  final ValueListenable<bool> visible;
  final VoidCallback onOpenPlugins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).settings;
    return PageSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageAppBar(title: _groupName(t, group)),
          // 標題已經在上面那一列。
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: visible,
              builder: (context, visible, _) => _GroupDetail(
                group: group,
                heading: false,
                visible: visible,
                onOpenPlugins: onOpenPlugins,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一組的內容；寬版的右欄（[heading] 是組名）與窄版的那一頁共用。
class _GroupDetail extends ConsumerWidget {
  const _GroupDetail({
    required this.group,
    required this.heading,
    required this.visible,
    required this.onOpenPlugins,
  });

  final SettingsSection group;
  final bool heading;

  /// 設定頁在外殼裡看得到（「關於」的連點計數用）。
  final bool visible;
  final VoidCallback onOpenPlugins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).settings;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    Widget sectionTitle() => Semantics(
      header: true,
      child: Text(_groupName(t, group), style: theme.textTheme.titleLarge),
    );
    // 設定組：控制項放在捲動的欄裡。
    Widget scrolling(Widget controls) => SingleChildScrollView(
      padding: EdgeInsets.all(spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading) ...[sectionTitle(), SizedBox(height: spacing.x4)],
          controls,
        ],
      ),
    );
    // 帳號頁與插件頁自己有捲動的清單（與置中的空狀態）：不包在捲動的欄裡，填滿剩下的
    // 高度。
    Widget filling(Widget page) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading)
          Padding(
            padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
            child: sectionTitle(),
          ),
        Expanded(child: page),
      ],
    );
    return switch (group) {
      SettingsSection.accounts => filling(
        AccountsSection(onOpenPlugins: onOpenPlugins),
      ),
      SettingsSection.plugins => filling(const PluginsPage()),
      SettingsSection.appearance => scrolling(const AppearanceControls()),
      SettingsSection.playback => scrolling(const PlaybackControls()),
      SettingsSection.library => scrolling(const LibraryControls()),
      SettingsSection.network => scrolling(const NetworkControls()),
      SettingsSection.backup => scrolling(const BackupControls()),
      SettingsSection.about => scrolling(AboutSection(visible: visible)),
    };
  }
}
