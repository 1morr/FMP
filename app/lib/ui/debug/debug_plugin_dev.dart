import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/dev/dev_case_runs.dart';
import 'package:fmp/plugins/dev/dev_folder.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_widgets.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// Debug 頁的「插件開發」（M3 PR 16b，ADR 0025 §決定 7、design §3.6）：選資料夾、每個
/// 插件一張卡片（模式、重新載入、查看 log、跑案例與結果）。
///
/// 動作與狀態都在 [PluginDevelopment]（載入）與 [DevCaseRuns]（跑案例）；這裡只呈現。
/// [onViewLog] 切到 Log 區塊並把 tag 篩選設成該插件 id。
class DebugPluginDev extends ConsumerWidget {
  const DebugPluginDev({super.key, required this.onViewLog});

  final ValueChanged<String> onViewLog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    final development = ref.watch(pluginDevelopmentProvider);
    final stored = ref.watch(
      developerProvider.select((value) => value.value?.stored.pluginDevFolder),
    );
    final redactor = ref.watch(redactorProvider);
    final busy = development?.busy ?? false;
    final hasFolder = stored != null;
    final notifier = ref.read(pluginDevelopmentProvider.notifier);
    return ListView(
      padding: EdgeInsets.all(spacing.x4),
      children: [
        Text(t.pdHint, style: Theme.of(context).textTheme.bodyMedium),
        SizedBox(height: spacing.x3),
        Card.outlined(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(spacing.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.pdFolder, style: Theme.of(context).textTheme.titleSmall),
                SelectableText(
                  stored == null ? t.pdNoFolder : redactor.redact(stored),
                ),
                SizedBox(height: spacing.x2),
                Wrap(
                  spacing: spacing.x2,
                  runSpacing: spacing.x2,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.folder_open),
                      label: Text(t.pdPick),
                      onPressed: busy ? null : () => unawaited(_pick(ref)),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(t.pdRescan),
                      onPressed: busy || !hasFolder
                          ? null
                          : () => unawaited(notifier.rescan()),
                    ),
                    TextButton(
                      onPressed: busy || !hasFolder
                          ? null
                          : () => unawaited(
                              ref
                                  .read(developerProvider.notifier)
                                  .setPluginDevFolder(null),
                            ),
                      child: Text(t.pdUnload),
                    ),
                  ],
                ),
                if (busy) ...[
                  SizedBox(height: spacing.x2),
                  LinearProgressIndicator(semanticsLabel: t.pdApplying),
                ],
                for (final problem
                    in development?.problems ?? const <DevFolderProblem>[]) ...[
                  SizedBox(height: spacing.x2),
                  SelectableText(
                    switch (problem) {
                      DevFolderMissing() => t.pdFolderMissing,
                      DevFolderEmpty() => t.pdFolderEmpty,
                      DevFolderDuplicateId(
                        :final id,
                        :final first,
                        :final second,
                      ) =>
                        t.pdDuplicateId(id: id, first: first, second: second),
                    },
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        for (final plugin in development?.plugins ?? const <DevPlugin>[]) ...[
          SizedBox(height: spacing.x3),
          _PluginCard(
            key: ValueKey(plugin.id),
            plugin: plugin,
            applying: busy,
            onViewLog: () => onViewLog(plugin.id),
          ),
        ],
      ],
    );
  }

  Future<void> _pick(WidgetRef ref) async {
    final dialogs = ref.read(fileDialogsProvider);
    final developer = ref.read(developerProvider.notifier);
    final path = await dialogs?.pickDirectory();
    if (path != null) await developer.setPluginDevFolder(path);
  }
}

class _PluginCard extends ConsumerStatefulWidget {
  const _PluginCard({
    super.key,
    required this.plugin,
    required this.applying,
    required this.onViewLog,
  });

  final DevPlugin plugin;
  final bool applying;
  final VoidCallback onViewLog;

  @override
  ConsumerState<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends ConsumerState<_PluginCard> {
  /// 展開的結果列。
  final _expanded = <PluginCapability>{};

  Future<void> _reload() async {
    final t = ref.read(translationsProvider).debug;
    final toaster = ref.read(toasterProvider);
    final notifier = ref.read(pluginDevelopmentProvider.notifier);
    final id = widget.plugin.id;
    await notifier.reload(id);
    final plugin = ref
        .read(pluginDevelopmentProvider)
        ?.plugins
        .where((plugin) => plugin.id == id)
        .firstOrNull;
    if (plugin == null) return;
    final manifest = plugin.manifest;
    if (plugin.load == DevLoad.loaded && manifest != null) {
      toaster.success(
        t.pdReloaded(name: manifest.name, version: manifest.version),
      );
    } else {
      toaster.warning(
        t.pdReloadFailed(name: plugin.manifest?.name ?? plugin.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final d = t.debug;
    final plugin = widget.plugin;
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    final runs = ref.watch(devCaseRunsProvider);
    final mode = runs.modeOf(plugin.id);
    final results = runs.results[plugin.id] ?? const {};
    final manifest = plugin.manifest;
    final failed = plugin.load == DevLoad.failed;
    final runsNotifier = ref.read(devCaseRunsProvider.notifier);
    final runningHere =
        runs.running?.pluginId == plugin.id || runs.batch == plugin.id;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(spacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PluginHeading(
              name: manifest?.name ?? plugin.id,
              byline: manifest == null
                  ? plugin.id
                  : '${plugin.id} · ${manifest.version}',
              description: '',
              tags: [
                if (failed)
                  PluginTag(text: d.pdTagFailed, tone: PluginTagTone.error)
                else
                  PluginTag(
                    text: t.plugins.tagDev,
                    tone: PluginTagTone.primary,
                  ),
                if (plugin.replacedVersion case final version?)
                  PluginTag(text: d.pdTagReplaces(version: version)),
              ],
            ),
            if (plugin.changedId case final changedId?) ...[
              SizedBox(height: spacing.x2),
              SelectableText(
                d.pdIdChanged(id: changedId),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (plugin.problem case final problem?) ...[
              SizedBox(height: spacing.x2),
              SelectableText(
                problem,
                style: TextStyle(
                  color: failed ? theme.colorScheme.error : null,
                ),
              ),
            ],
            SizedBox(height: spacing.x3),
            Wrap(
              spacing: spacing.x2,
              runSpacing: spacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<CaseMode>(
                  segments: [
                    ButtonSegment(
                      value: CaseMode.replay,
                      label: Text(d.pdReplay),
                    ),
                    ButtonSegment(
                      value: CaseMode.record,
                      label: Text(d.pdRecord),
                    ),
                    ButtonSegment(value: CaseMode.real, label: Text(d.pdReal)),
                  ],
                  selected: {mode},
                  onSelectionChanged: runningHere
                      ? null
                      : (selection) =>
                            runsNotifier.setMode(plugin.id, selection.single),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(d.pdReload),
                  onPressed: widget.applying
                      ? null
                      : () => unawaited(_reload()),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.article_outlined),
                  label: Text(d.pdViewLog),
                  onPressed: widget.onViewLog,
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(d.pdRunAll),
                  onPressed: runs.busy || plugin.cases.isEmpty
                      ? null
                      : () => unawaited(runsNotifier.runAll(plugin.id)),
                ),
              ],
            ),
            if (mode == CaseMode.record) ...[
              SizedBox(height: spacing.x2),
              Text(
                d.pdRecordWarning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const Divider(),
            if (plugin.cases.isEmpty)
              Text(d.pdNoCases, style: theme.textTheme.bodyMedium),
            for (final capability in plugin.cases)
              _CaseRow(
                pluginId: plugin.id,
                capability: capability,
                result: results[capability],
                running:
                    runs.running?.pluginId == plugin.id &&
                    runs.running?.capability == capability,
                busy: runs.busy,
                expanded: _expanded.contains(capability),
                onToggle: () => setState(() {
                  if (!_expanded.remove(capability)) _expanded.add(capability);
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _CaseRow extends ConsumerWidget {
  const _CaseRow({
    required this.pluginId,
    required this.capability,
    required this.result,
    required this.running,
    required this.busy,
    required this.expanded,
    required this.onToggle,
  });

  final String pluginId;
  final PluginCapability capability;
  final DevCaseResult? result;
  final bool running;
  final bool busy;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(translationsProvider).debug;
    final scheme = Theme.of(context).colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final shown = result;
    final (icon, color) = switch (shown?.outcome) {
      null => (Icons.radio_button_unchecked, scheme.onSurfaceVariant),
      DevCaseOutcome.passed => (Icons.check_circle_outline, null),
      DevCaseOutcome.failed => (Icons.error_outline, scheme.error),
      DevCaseOutcome.skipped => (
        Icons.remove_circle_outline,
        scheme.onSurfaceVariant,
      ),
    };
    final summary = switch (shown) {
      null => d.pdNotRun,
      DevCaseResult(outcome: DevCaseOutcome.skipped, :final skip) =>
        skip == DevSkip.handEdited ? d.pdSkippedEdited : d.pdSkippedLogin,
      final result => [
        d.pdCaseLine(
          outcome: result.outcome == DevCaseOutcome.passed
              ? d.pdPassed
              : d.pdFailed,
          ms: result.elapsed.inMilliseconds,
          mode: _modeName(d, result.mode),
        ),
        ?result.errorType,
      ].join(' · '),
    };
    final runnable = !busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color),
          title: Text(capability.wireName),
          subtitle: Text(summary),
          onTap: shown == null ? null : onToggle,
          trailing: running
              ? Semantics(
                  label: d.pdRunning,
                  child: SizedBox.square(
                    dimension: spacing.x6,
                    child: const CircularProgressIndicator(),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: d.pdRun,
                  onPressed: runnable
                      ? () => unawaited(
                          ref
                              .read(devCaseRunsProvider.notifier)
                              .run(pluginId, capability),
                        )
                      : null,
                ),
        ),
        if (expanded && shown != null) _Detail(result: shown),
      ],
    );
  }

  static String _modeName(Translations$debug$zh_TW d, CaseMode mode) =>
      switch (mode) {
        CaseMode.replay => d.pdReplay,
        CaseMode.record => d.pdRecord,
        CaseMode.real => d.pdReal,
      };
}

/// 展開的結果：錯誤、問題清單、錄製的寫檔結果、回傳值。全部可選取，已遮蔽。
class _Detail extends ConsumerWidget {
  const _Detail({required this.result});

  final DevCaseResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    final theme = Theme.of(context);
    final value = result.value;
    final lines = [
      if (result.errorType case final type?) d.pdErrorType(type: type),
      ...result.problems,
    ];
    return Padding(
      padding: EdgeInsets.only(left: spacing.x8, bottom: spacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isNotEmpty) SelectableText(lines.join('\n')),
          if (result.written case final count?)
            SelectableText(d.pdWritten(count: count)),
          if (result.notWritten) SelectableText(d.pdNotWritten),
          if (value != null) ...[
            SizedBox(height: spacing.x2),
            Row(
              children: [
                Text(d.pdValue, style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: d.pdCopy,
                  onPressed: () =>
                      unawaited(Clipboard.setData(ClipboardData(text: value))),
                ),
              ],
            ),
            SelectableText(value, style: theme.textTheme.bodySmall),
            if (result.truncated) Text(d.pdTruncated),
          ],
        ],
      ),
    );
  }
}
