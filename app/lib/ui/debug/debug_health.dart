import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/plugins/health/health_check.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugins_state.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的「音源健康檢查」（ADR 0025 §決定 6）：每個已安裝的插件一列，手動檢查單一插件
/// 或全部（一次一個，流程在 [HealthCheck]）；結果留在記憶體，另以 tag `health` 寫進 log。
class DebugHealth extends ConsumerWidget {
  const DebugHealth({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final installed = ref.watch(installedPluginsProvider).value;
    final health = ref.watch(healthCheckProvider);
    // 開發中的插件案例數讀資料夾的 checks.json（M3 PR 16b）；狀態變了就重畫。
    ref.watch(pluginDevelopmentProvider);
    final spacing = AppTokens.of(context).spacing;
    if (installed == null) return const SizedBox.shrink();
    if (installed.isEmpty) {
      return EmptyState(
        icon: Icons.health_and_safety_outlined,
        title: t.hcEmpty,
      );
    }
    final notifier = ref.read(healthCheckProvider.notifier);
    return ListView(
      padding: EdgeInsets.all(spacing.x4),
      children: [
        Text(t.hcHint, style: Theme.of(context).textTheme.bodyMedium),
        SizedBox(height: spacing.x2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(t.hcAll),
            onPressed: health.busy ? null : () => unawaited(notifier.runAll()),
          ),
        ),
        const Divider(),
        for (final plugin in installed)
          _PluginRow(plugin: plugin, health: health),
      ],
    );
  }
}

class _PluginRow extends ConsumerWidget {
  const _PluginRow({required this.plugin, required this.health});

  final InstalledPlugin plugin;
  final HealthState health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    final result = health.results[plugin.id];
    final running = health.running == plugin.id;
    final name = _name(plugin);
    final count = _caseCount(ref, plugin);
    // checks_json 讀不懂（-1）仍可以按「檢查」：跑了才看得到哪裡不對（hcProblem）。
    final runnable = plugin.enabled && count != 0;
    final subtitle = [
      plugin.version,
      if (!plugin.enabled)
        t.hcDisabled
      else if (count == 0)
        t.hcNone
      else if (count < 0)
        t.hcUnreadable
      else
        t.hcCount(count: count),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(name),
          subtitle: Text(subtitle),
          trailing: running
              ? Text(t.hcChecking)
              : OutlinedButton(
                  onPressed: health.busy || !runnable
                      ? null
                      : () => unawaited(
                          ref
                              .read(healthCheckProvider.notifier)
                              .runOne(plugin.id),
                        ),
                  child: Text(t.hcCheck),
                ),
        ),
        if (running) const LinearProgressIndicator(),
        if (result != null) ...[
          if (result.problem case final problem?)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.x2),
              child: Text(t.hcProblem(problem: problem)),
            ),
          if (result.notLoaded)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.x2),
              child: Text(t.hcNotLoaded),
            ),
          for (final item in result.cases) _CaseRow(item: item),
        ],
        const Divider(),
      ],
    );
  }

  static String _name(InstalledPlugin plugin) {
    try {
      return PluginManifest.parse(plugin.manifestJson).name;
    } on Object {
      // manifest 讀不懂時用 id；列表不因為一個壞插件而空白。
      return plugin.id;
    }
  }

  /// 案例數；沒有 checks_json 是 0，讀不懂是 -1。
  static int _caseCount(WidgetRef ref, InstalledPlugin plugin) {
    try {
      final json = ref
          .read(pluginDevelopmentProvider.notifier)
          .checksJsonFor(plugin);
      return readChecks(json)?.length ?? 0;
    } on FormatException {
      return -1;
    }
  }
}

class _CaseRow extends ConsumerWidget {
  const _CaseRow({required this.item});

  final HealthCaseResult item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (item.outcome) {
      HealthOutcome.passed => (Icons.check_circle_outline, null, t.hcPassed),
      HealthOutcome.failed => (Icons.error_outline, scheme.error, t.hcFailed),
      HealthOutcome.skipped => (
        Icons.remove_circle_outline,
        scheme.onSurfaceVariant,
        t.hcSkipped,
      ),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        t.hcCase(
          capability: item.capability.wireName,
          outcome: label,
          ms: item.elapsed.inMilliseconds,
        ),
      ),
      subtitle: item.outcome == HealthOutcome.failed
          ? SelectableText(
              [
                if (item.errorType case final type?) t.hcErrorType(type: type),
                ...item.problems,
              ].join('\n'),
            )
          : null,
    );
  }
}
