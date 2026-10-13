import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 連點版本列幾次開啟開發者模式（ADR 0025 §決定 1，沿用 Android 的開發人員選項）。
const developerModeTaps = 7;

/// 設定頁的「關於」（ADR 0024 §決定 9；M3 只有版本列，其餘在 M9）。
///
/// 版本列連點 [developerModeTaps] 次開啟開發者模式：第 2 次起提示還差幾次，已經開著時
/// 提示已開啟（Firefox `SecretDebugMenuTrigger`）。離開這一頁計數歸零：這個區塊被換掉
/// （State 拆掉），或外殼換到別的分頁（[visible] 變成假）。
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key, required this.visible});

  /// 設定頁是不是外殼正顯示的那一頁（外殼以 `IndexedStack` 留著沒選的頁面）。
  final bool visible;

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  var _taps = 0;

  @override
  void didUpdateWidget(AboutSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) _taps = 0;
  }

  void _onVersionTap() {
    final developer = ref.read(developerProvider).value;
    // 設定還沒讀出來：不知道是不是已經開著，不計數。
    if (developer == null) return;
    final t = ref.read(translationsProvider).about;
    final toaster = ref.read(toasterProvider);
    if (developer.developerMode) {
      _taps = 0;
      toaster.info(t.alreadyDeveloper);
      return;
    }
    _taps++;
    if (_taps < developerModeTaps) {
      if (_taps >= 2) {
        toaster.info(t.tapsLeft(count: developerModeTaps - _taps));
      }
      return;
    }
    _taps = 0;
    unawaited(
      ref
          .read(developerProvider.notifier)
          .setDeveloperMode(true)
          .then((_) => toaster.success(t.developerModeOn)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).about;
    final info = ref.watch(appInfoProvider);
    final flavor = ref.watch(appFlavorProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline),
      title: Text(t.version),
      subtitle: Text(
        t.versionValue(version: info.version, flavor: flavor.name),
      ),
      onTap: _onVersionTap,
    );
  }
}
