import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/domain/developer.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// [path] 在家目錄 [home] 底下時把那一段換成 `~`（M3 design §12.4：畫面與截圖不帶使用者
/// 名稱）。比對不分大小寫、`/` 與 `\` 都算分隔：家目錄只有 Windows 有，它的路徑不分大小寫。
/// 只比對整段目錄名稱（`C:\Users\a` 不吃掉 `C:\Users\ab\…` 的前綴）。
String homeRelativePath(String path, String? home) {
  if (home == null) return path;
  final base = home.replaceFirst(RegExp(r'[\\/]+$'), '');
  if (base.isEmpty || path.length < base.length) return path;
  if (path.substring(0, base.length).toLowerCase() != base.toLowerCase()) {
    return path;
  }
  final rest = path.substring(base.length);
  if (rest.isEmpty) return '~';
  return rest.startsWith('/') || rest.startsWith(r'\') ? '~$rest' : path;
}

/// Debug 頁的「概覽」（ADR 0025 §決定 2）：最上方是開發者模式的總開關，接著 log 層級、
/// App 與平台的資訊、快取用量的連結。診斷包在 M3 PR 15 加在這裡。
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
      ],
    );
  }
}
