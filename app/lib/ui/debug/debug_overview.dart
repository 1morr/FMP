import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/domain/developer.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/debug/debug_export.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/format/home_path.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的「概覽」（ADR 0025 §決定 2）：最上方是開發者模式的總開關，接著 log 層級、
/// App 與平台的資訊、快取用量的連結、診斷包。
class DebugOverview extends ConsumerWidget {
  const DebugOverview({super.key, required this.onShowCacheSettings});

  /// 「快取用量」：關掉 Debug 頁、到設定頁的「網路」（快取的清除入口在那裡，ADR 0016）。
  final VoidCallback onShowCacheSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final developer = ref.watch(developerProvider).value;
    if (developer == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).debug;
    final notifier = ref.read(developerProvider.notifier);
    final info = ref.watch(appInfoProvider);
    final flavor = ref.watch(appFlavorProvider);
    final directory = ref.watch(dataDirectoryProvider);
    final usage = ref.watch(cacheUsageProvider).value;
    final capabilities = ref.watch(platformCapabilitiesProvider);
    final spacing = AppTokens.of(context).spacing;
    final textTheme = Theme.of(context).textTheme;
    Widget fact(String label, String value) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
    );
    final cacheBytes =
        usage?.values.fold<int>(0, (sum, bytes) => sum + bytes) ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 總開關（Android 開發人員選項的頁首開關）。關掉時這一頁自己關閉（DebugPage 的
        // 路由閘門）。
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.developerMode),
          subtitle: Text(t.developerModeHint),
          value: developer.developerMode,
          onChanged: (on) => unawaited(notifier.setDeveloperMode(on)),
        ),
        SizedBox(height: spacing.x4),
        Text(t.logLevel, style: textTheme.titleSmall),
        // 顯示生效的層級；這個建置的預設（debug build 是 debug，release 是 info）標「（預設）」。
        RadioGroup<LogLevelSetting>(
          groupValue: developer.logLevel,
          onChanged: (level) {
            if (level == null) return;
            unawaited(notifier.setLogLevel(level));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (level, name, hint) in [
                (LogLevelSetting.info, t.logLevelInfo, null),
                (LogLevelSetting.debug, t.logLevelDebug, t.logLevelDebugHint),
              ])
                RadioListTile<LogLevelSetting>(
                  value: level,
                  title: Text(
                    level == developer.defaultLogLevel
                        ? t.logLevelDefault(level: name)
                        : name,
                  ),
                  subtitle: hint == null ? null : Text(hint),
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.x4),
        Text(t.app, style: textTheme.titleSmall),
        fact(t.version, info.version),
        fact(t.flavor, flavor.name),
        fact(t.platform, info.platform),
        fact(
          t.dataDirectory,
          homeRelativePath(directory.path, info.homeDirectory),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.cacheUsage),
          subtitle: Text(t.cacheUsageValue(size: formatByteSize(cacheBytes))),
          trailing: const Icon(Icons.chevron_right),
          onTap: onShowCacheSettings,
        ),
        SizedBox(height: spacing.x4),
        Text(t.diagnostics, style: textTheme.titleSmall),
        SizedBox(height: spacing.x1),
        Text(t.diagnosticsHint, style: textTheme.bodySmall),
        SizedBox(height: spacing.x2),
        Wrap(
          spacing: spacing.x2,
          runSpacing: spacing.x2,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: Text(t.diagnosticsCopy),
              onPressed: () => unawaited(copyDiagnosticsSummary(ref)),
            ),
            if (capabilities.files)
              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: Text(t.diagnosticsSave),
                onPressed: () => unawaited(
                  exportBundle(
                    context,
                    ref,
                    kind: ExportKind.diagnostics,
                    action: ExportAction.save,
                  ),
                ),
              ),
            if (capabilities.shareFiles)
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: Text(t.diagnosticsShare),
                onPressed: () => unawaited(
                  exportBundle(
                    context,
                    ref,
                    kind: ExportKind.diagnostics,
                    action: ExportAction.share,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
