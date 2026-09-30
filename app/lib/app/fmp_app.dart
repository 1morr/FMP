import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/app/app_material.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/dev_playback_entry.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toast_host.dart';

/// App 根元件：主題、介面語言與提示宿主（ADR 0023、0024）。
///
/// 畫面目前只有身分頁：App 名稱、flavor、資料目錄、外觀設定、字形樣本與載入的
/// 插件，供實機確認身分、開發入口（插件、播放）與 CJK 字形；正式的外殼在 M1
/// PR 12b。
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
      home: _IdentityPage(flavor: widget.flavor),
    );
  }
}

class _IdentityPage extends ConsumerWidget {
  const _IdentityPage({required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = AppTokens.of(context).spacing;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(spacing.x4),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  flavor.displayName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(flavor.name),
                SelectableText(ref.watch(dataDirectoryProvider).path),
                const _PluginList(),
                const _DevPlayback(),
                SizedBox(height: spacing.x4),
                const _FontSample(),
                SizedBox(height: spacing.x4),
                const AppearanceControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 實機比對 CJK 字形用（M1 PR 12a）：同一串字以介面的樣式、指定繁中、指定
/// 簡中各顯示一行。
///
/// 指定的那兩行帶該語言的 locale 與平台的字型清單，是參照；第一行（介面實際
/// 用的樣式）應該和介面語言那一行相同。挑的字在台灣與大陸的標準字形不同：
/// 「草」的艹、「骨」上半、「令」的末筆、「值」「角」「這」「說」。
class _FontSample extends ConsumerWidget {
  const _FontSample();

  static const _sample = '草骨令值角這說';
  static const _traditional = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
  );
  static const _simplified = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hans',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = Theme.of(context).textTheme.headlineSmall!;
    final fonts = ref.watch(platformCapabilitiesProvider).fontFallback;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('UI  $_sample', style: style),
        Text(
          'zh-Hant  $_sample',
          style: style.copyWith(
            locale: _traditional,
            fontFamilyFallback: fonts.familiesFor(FontLanguage.zhTw),
          ),
        ),
        Text(
          'zh-Hans  $_sample',
          style: style.copyWith(
            locale: _simplified,
            fontFamilyFallback: fonts.familiesFor(FontLanguage.zhCn),
          ),
        ),
      ],
    );
  }
}

/// 載入的插件（`id version`，沒有回應的加註），以及開發入口安裝失敗時的錯誤類別。
class _PluginList extends ConsumerWidget {
  const _PluginList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final install = ref.watch(devPluginInstallProvider);
    final plugins = ref.watch(pluginRegistryProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (install case AsyncError(error: final AppError error))
          Text('Dev plugin: ${error.typeName}'),
        ...switch (plugins) {
          AsyncData(:final value) => [
            for (final plugin in value.values)
              Text(
                '${plugin.manifest.id} ${plugin.manifest.version}'
                '${plugin.health == PluginHealth.unresponsive ? ' (unresponsive)' : ''}',
              ),
          ],
          AsyncError(:final error) => [Text('Plugins: $error')],
          _ => const <Widget>[],
        },
      ],
    );
  }
}

/// 播放的開發入口（只在帶了 `--fmp-dev-playback` 時）：目前的播放狀態與第幾首，
/// 或開始失敗的錯誤類別。
class _DevPlayback extends ConsumerWidget {
  const _DevPlayback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(devPlaybackRequestProvider) == null) {
      return const SizedBox.shrink();
    }
    final start = ref.watch(devPlaybackProvider);
    if (start case AsyncError(:final error)) {
      return Text(
        'Dev playback: ${error is AppError ? error.typeName : 'failed'}',
      );
    }
    final state = switch (ref.watch(playbackStateProvider).value) {
      null => '-',
      Idle() => 'idle',
      Loading() => 'loading',
      Playing() => 'playing',
      Paused() => 'paused',
      Buffering() => 'buffering',
      Retrying(:final error, :final attempt) =>
        'retrying ${error.typeName} #$attempt',
      Failed(:final error) => 'failed ${error.typeName}',
    };
    final queue = ref.watch(playbackQueueProvider).value;
    final index = queue?.currentIndex;
    return Text(
      'Dev playback: $state'
      '${index == null ? '' : ' ${index + 1}/${queue!.tracks.length}'}',
    );
  }
}
