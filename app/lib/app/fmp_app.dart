import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/app_lifecycle.dart';
import 'package:fmp/app/app_material.dart';
import 'package:fmp/app/startup_maintenance.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/toast/toast_host.dart';

/// App 根元件：主題、介面語言、提示宿主與外殼（ADR 0023、0024）。
class FmpApp extends ConsumerStatefulWidget {
  const FmpApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  ConsumerState<FmpApp> createState() => _FmpAppState();
}

class _FmpAppState extends ConsumerState<FmpApp> {
  @override
  void initState() {
    super.initState();
    // 實機驗字形時對得上用的是哪個語言、哪些字型；不含個人資訊。字型清單由
    // 這次的語言算，不讀 fontFamilyFallbackProvider：它可能還沒收到通知。
    ref.listenManual(uiLocaleProvider, (_, locale) {
      ref
          .read(logProvider)
          .info(
            'UI locale applied',
            tag: 'ui',
            fields: {
              'locale': flutterLocaleOf(locale).toLanguageTag(),
              'fontFallback': fontFamilyFallbackOf(
                ref.read(platformCapabilitiesProvider).fontFallback,
                locale,
              ),
            },
          );
    }, fireImmediately: true);
    // 插件的開發入口（只在 dev 有路徑）：啟動時安裝一次。結果寫進 log，裝好
    // 的插件出現在搜尋頁的音源列。
    ref.listenManual(
      devPluginInstallProvider,
      (_, _) {},
      fireImmediately: true,
    );
    // 回到前景時再查一次網路介面：Android 8 起背景收不到介面變化
    // （connectivity_plus 的 README）。事件觸發，不輪詢。
    ref.listenManual(appLifecycleProvider, (previous, next) {
      if (next == AppLifecycleState.resumed &&
          previous != AppLifecycleState.resumed) {
        unawaited(ref.read(networkStatusProvider.notifier).recheckInterfaces());
      }
    });
    // 啟動維護在第一幀之後跑一次，不拖慢第一個畫面（ADR 0017 §決定 1）。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 宣告啟動刷新的插件，網路第一次上線時刷新憑證（design §6.5）。
      ref.read(accountStartupRefreshProvider);
      unawaited(
        runStartupMaintenance(
          ref.read(startupMaintenanceTasksProvider),
          ref.read(logProvider),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(
      appearanceProvider.select((value) => value.value?.themeMode),
    );
    return fmpMaterialApp(
      title: widget.flavor.displayName,
      locale: ref.watch(uiLocaleProvider),
      themeMode: themeModeOf(themeMode ?? ThemeModeSetting.system),
      fontFamilyFallback: ref.watch(fontFamilyFallbackProvider),
      builder: (context, navigator) =>
          WindowClassScope(child: ToastHost(child: navigator!)),
      home: const AppShell(),
    );
  }
}
