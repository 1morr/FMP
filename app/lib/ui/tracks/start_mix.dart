import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 佇列現在是 Mix：隨機、加入佇列、下一首播放停用（ADR 0031 §決定 9）。
final inMixProvider = Provider<bool>(
  (ref) => ref.watch(
    playbackQueueProvider.select((queue) => queue.value?.mix != null),
  ),
);

/// 曲目選單的「開始 Mix」要不要出現：曲目所屬的插件宣告了 `mix`（ADR 0031 §決定 8）。
/// 插件停用、移除或清單還沒載入時為假。
final canStartMixProvider = Provider.family<bool, String>(
  (ref, pluginId) => ref.watch(
    pluginRegistryProvider.select(
      (plugins) =>
          plugins.value?[pluginId]?.manifest.capabilities.contains(
            PluginCapability.mix,
          ) ??
          false,
    ),
  ),
);

/// 以 [track] 開始 Mix（取代整個佇列）。失敗照統一提示顯示。
Future<void> startMixFrom(WidgetRef ref, TrackInfo track) async {
  final toaster = ref.read(toasterProvider);
  try {
    await ref.read(playbackControllerProvider).startMix(track);
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to start a mix',
      tag: 'mix',
    );
  }
}
