import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
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

/// Mix 歌單的「Mix 播放」為什麼不能按；能按是 `null`：清單還沒載入是「正在載入音源」，
/// 插件停用或移除是「音源已停用／未安裝」，在清單上但沒宣告 `mix` 是「不支援 Mix」。
final mixUnavailableReasonProvider = Provider.family<String?, String>((
  ref,
  pluginId,
) {
  if (ref.watch(canStartMixProvider(pluginId))) return null;
  final t = ref.watch(translationsProvider);
  if (!ref.watch(pluginRegistryProvider.select((p) => p.hasValue))) {
    return t.search.loadingSources;
  }
  return ref.watch(sourceUnavailableProvider(pluginId)) ??
      t.library.mixUnsupported;
});

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

/// 以 Mix 歌單 [playlist] 存的種子開始 Mix（取代整個佇列）。失敗的提示同 [startMixFrom]。
/// 不是 Mix 歌單（沒有種子）什麼都不做。
Future<void> startMixFromPlaylist(WidgetRef ref, Playlist playlist) async {
  final pluginId = playlist.mixPluginId;
  final sourceId = playlist.mixSeedSourceId;
  if (pluginId == null || sourceId == null) return;
  final toaster = ref.read(toasterProvider);
  try {
    await ref
        .read(playbackControllerProvider)
        .startMixFromSeed(
          pluginId,
          MixSeedQuery(sourceId: sourceId, cid: playlist.mixSeedCid),
        );
  } on Object catch (error, stackTrace) {
    toaster.error(
      AppError.wrap(error, stackTrace),
      operation: 'Failed to start a mix',
      tag: 'mix',
    );
  }
}
