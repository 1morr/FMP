import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/repository/plugin_downloader.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/plugins/plugin_dialogs.dart';
import 'package:fmp/ui/plugins/plugin_text.dart';
import 'package:fmp/ui/plugins/plugin_widgets.dart';
import 'package:fmp/ui/plugins/plugins_state.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

const _tag = 'plugins';

/// 首次啟動引導的狀態（ADR 0030 §決定 12，design §7.6）。只活在這次執行：「稍後再說」
/// 不寫進資料庫。
final class OnboardingState {
  const OnboardingState({
    this.dismissed = false,
    this.working = false,
    this.failures = const [],
  });

  /// 使用者按了「稍後再說」。
  final bool dismissed;

  /// 正在下載、確認或安裝。第一個插件裝好時搜尋頁就有音源了，引導要留到整批裝完。
  final bool working;

  /// 沒裝成功的插件，每個一句話（名稱與原因）。
  final List<String> failures;

  OnboardingState copyWith({
    bool? dismissed,
    bool? working,
    List<String>? failures,
  }) => OnboardingState(
    dismissed: dismissed ?? this.dismissed,
    working: working ?? this.working,
    failures: failures ?? this.failures,
  );
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
      OnboardingNotifier.new,
    );

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  /// 「稍後再說」：連同失敗的清單一起收起，否則全部失敗時引導收不掉。
  void dismiss() => state = state.copyWith(dismissed: true, failures: const []);

  void begin() => state = state.copyWith(working: true, failures: const []);

  void finish(List<String> failures) =>
      state = state.copyWith(working: false, failures: failures);

  void clearFailures() => state = state.copyWith(failures: const []);
}

/// 搜尋頁要不要顯示引導：沒有可搜尋的音源而且還沒按「稍後再說」；或者正在裝、還有沒裝成功
/// 的要讓使用者看到。
bool showOnboarding({
  required bool hasSource,
  required OnboardingState state,
}) =>
    state.working ||
    state.failures.isNotEmpty ||
    (!hasSource && !state.dismissed);

/// 搜尋頁的首次啟動引導：官方插件庫的插件清單（預設全勾）、一次確認後依序安裝。
///
/// 不做精靈（ADR 0024 §決定 9）：說明、清單與兩個按鈕就在空狀態的位置。讀不到插件庫時
/// 是離線空狀態（ADR 0016 §決定 7）或一般的失敗畫面，附「重試」。
class PluginOnboarding extends ConsumerStatefulWidget {
  const PluginOnboarding({super.key, required this.hasSource});

  /// 搜尋頁目前有沒有可搜尋的音源（裝了一部分、引導還沒收起時為真）。
  final bool hasSource;

  @override
  ConsumerState<PluginOnboarding> createState() => _PluginOnboardingState();
}

class _PluginOnboardingState extends ConsumerState<PluginOnboarding> {
  /// 使用者取消勾選的 id；沒在這裡的可安裝插件都是勾著的。
  final _unchecked = <String>{};

  void _retry() => ref.invalidate(indexOutcomeProvider(officialPluginIndexUrl));

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final o = t.onboarding;
    final state = ref.watch(onboardingProvider);
    final hasSource = widget.hasSource;
    final network = ref.watch(networkStatusProvider);
    final outcome = ref.watch(indexOutcomeProvider(officialPluginIndexUrl));
    final later = TextButton(
      onPressed: () => ref.read(onboardingProvider.notifier).dismiss(),
      child: Text(o.later),
    );
    Widget retryActions() => Wrap(
      spacing: AppTokens.of(context).spacing.x2,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonal(onPressed: _retry, child: Text(t.plugins.retry)),
        later,
      ],
    );
    return switch (outcome) {
      AsyncData(value: IndexLoaded(:final index)) when index.plugins.isEmpty =>
        EmptyState(
          icon: Icons.extension_off_outlined,
          title: t.plugins.indexEmpty,
          action: later,
        ),
      AsyncData(value: IndexLoaded(:final index)) => _list(
        t,
        state,
        index.plugins,
        hasSource: hasSource,
        later: later,
      ),
      AsyncData(value: IndexTooNew()) => EmptyState(
        icon: Icons.system_update_alt,
        title: t.plugins.indexNeedsAppUpdate,
        action: later,
      ),
      // 一份讀不到：不在 online 時是共用的離線空狀態，online 時是一般的失敗畫面。
      AsyncData(value: IndexFailed()) || AsyncError() =>
        network == NetworkStatus.online
            ? EmptyState(
                icon: Icons.error_outline,
                title: t.plugins.allFailed,
                action: retryActions(),
              )
            : OfflineMessage(status: network, action: retryActions()),
      AsyncLoading() => Center(
        child: CircularProgressIndicator(semanticsLabel: o.loading),
      ),
    };
  }

  Widget _list(
    Translations t,
    OnboardingState state,
    List<PluginIndexEntry> entries, {
    required bool hasSource,
    required Widget later,
  }) {
    final o = t.onboarding;
    final p = t.plugins;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final installedIds = {
      for (final plugin
          in ref.watch(installedPluginsProvider).value ?? const [])
        plugin.id,
    };
    bool installable(PluginIndexEntry entry) =>
        entry.isCompatible && !installedIds.contains(entry.id);
    final selected = [
      for (final entry in entries)
        if (installable(entry) && !_unchecked.contains(entry.id)) entry,
    ];
    return ListView(
      padding: EdgeInsets.all(spacing.x4),
      children: [
        // 不忙時是透明的空條：出現與消失不改變下方的位置（同插件頁）。
        Opacity(
          opacity: state.working ? 1 : 0,
          child: LinearProgressIndicator(
            value: state.working ? null : 0,
            semanticsLabel: p.working,
          ),
        ),
        SizedBox(height: spacing.x4),
        Text(o.title, style: theme.textTheme.titleMedium),
        SizedBox(height: spacing.x2),
        Text(
          o.body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: spacing.x4),
        if (state.failures.isNotEmpty) ...[
          Text(o.failedTitle, style: theme.textTheme.titleSmall),
          SizedBox(height: spacing.x2),
          for (final line in state.failures) ...[
            WarningNote(text: line),
            SizedBox(height: spacing.x2),
          ],
          SizedBox(height: spacing.x2),
        ],
        for (final entry in entries) ...[
          Card.outlined(
            margin: EdgeInsets.zero,
            child: CheckboxListTile(
              value: installable(entry) && !_unchecked.contains(entry.id),
              onChanged: installable(entry) && !state.working
                  ? (checked) => setState(() {
                      if (checked ?? false) {
                        _unchecked.remove(entry.id);
                      } else {
                        _unchecked.add(entry.id);
                      }
                    })
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              title: PluginHeading(
                name: entry.name,
                byline: p.versionAuthor(
                  version: entry.version,
                  author: entry.author,
                ),
                description: entry.description,
                tags: [
                  if (installedIds.contains(entry.id))
                    PluginTag(text: p.tagInstalled)
                  else if (!entry.isCompatible)
                    PluginTag(
                      text: p.needsAppUpdate,
                      tone: PluginTagTone.error,
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: spacing.x3),
        ],
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            FilledButton(
              onPressed: state.working || selected.isEmpty
                  ? null
                  : () => _install({for (final entry in selected) entry.id}),
              child: Text(p.install),
            ),
            // 已經有音源（裝了一部分）時，這顆只是關掉失敗的清單。
            if (hasSource)
              TextButton(
                onPressed: state.working
                    ? null
                    : () =>
                          ref.read(onboardingProvider.notifier).clearFailures(),
                child: Text(p.close),
              )
            else
              later,
          ],
        ),
      ],
    );
  }

  /// 重讀官方 index，下載並驗證勾選的 [ids]，一次確認後依序安裝；失敗的記下來、其餘照裝。
  /// 整批結束前引導一直顯示（[OnboardingState.working]），所以這個 State 不會在中途被拆掉。
  ///
  /// 先重讀 index：SHA 不符多半是插件庫剛更新（「請稍後再試」），再按一次要比的是新的那
  /// 一份，不是畫面打開時讀的。讀不到時畫面換成離線或失敗的狀態（附「重試」），不裝。
  Future<void> _install(Set<String> ids) async {
    final t = ref.read(translationsProvider);
    final repository = ref.read(pluginRepositoryProvider);
    final downloader = ref.read(pluginDownloaderProvider);
    final installer = ref.read(pluginInstallerProvider);
    final log = ref.read(logProvider);
    final toaster = ref.read(toasterProvider);
    final notifier = ref.read(onboardingProvider.notifier);
    final failures = <String>[];
    void fail(String name, String reason) =>
        failures.add(t.plugins.installFailed(name: name, reason: reason));
    var installed = 0;
    notifier.begin();
    try {
      final outcome = await ref.refresh(
        indexOutcomeProvider(officialPluginIndexUrl).future,
      );
      if (outcome is! IndexLoaded) return;
      final installedIds = {for (final p in await repository.list()) p.id};
      final entries = [
        for (final entry in outcome.index.plugins)
          if (ids.contains(entry.id) && !installedIds.contains(entry.id)) entry,
      ];
      final ready = <PreparedPlugin>[];
      for (final entry in entries) {
        try {
          final result = await downloader.prepare(
            entry,
            indexUrl: Uri.parse(officialPluginIndexUrl),
          );
          switch (result) {
            case PrepareRejected(:final reason):
              log.warning(
                'A plugin was refused',
                tag: _tag,
                fields: {'pluginId': entry.id, 'reason': reason.name},
              );
              fail(entry.name, rejectionMessage(t, reason));
            case Prepared(:final plugin):
              ready.add(plugin);
          }
        } on AppError catch (error) {
          log.report('Failed to download a plugin', error, tag: _tag);
          fail(entry.name, errorMessage(t, error, sourceName: entry.name));
        }
      }
      if (ready.isEmpty) return;
      if (!mounted) return;
      final confirmed = await confirmInstallAll(context, t, [
        for (final plugin in ready)
          InstallConfirmation(
            manifest: plugin.file.manifest,
            isUpdate: false,
            capabilities: plugin.file.manifest.capabilities,
            hosts: plugin.file.manifest.allowedHosts.toSet(),
            unofficial: false,
          ),
      ]);
      if (!confirmed) {
        // 取消：什麼都不裝，下載階段的失敗也不留（使用者退出了這次安裝）。
        failures.clear();
        return;
      }
      for (final plugin in ready) {
        final name = plugin.file.manifest.name;
        try {
          await installer.installPrepared(plugin, confirmed: true);
          installed++;
        } on AppError catch (error) {
          log.report('Failed to install a plugin', error, tag: _tag);
          fail(name, errorMessage(t, error, sourceName: name));
        }
      }
    } finally {
      // 在 finally 裡：全部在下載階段失敗時上面是提早 return。
      notifier.finish(failures);
      // 有失敗時引導留著、裝好的標「已安裝」：頁面本身就是結果，不另跳提示（它會蓋住
      // 底部的按鈕）。
      if (failures.isEmpty && installed > 0) {
        toaster.success(t.onboarding.installedCount(count: installed));
      }
    }
  }
}
