import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/plugin_registry.dart';

// 播放的開發入口（M1 PR 10 第 7 項）：啟動時直接播一個清單，給還沒有播放 UI
// （PR 12）的這段期間在實機上驗證前瞻交接與 Android 的音訊焦點。PR 12 的播放列
// 能走同一條路之後刪掉；交接與出聲的 log 留在 PlaybackController。
//
// 只在 dev flavor 生效（[devPlaybackRequest]）：prod 不讀參數，理由同插件的
// 開發入口（dev_plugin_entry.dart）——它會安裝插件。

/// 命令列參數。只寫 `--fmp-dev-playback` 是播內附測試插件的三個音檔；
/// `--fmp-dev-playback=<曲目鍵>` 播指定的曲目，要幾首就重複幾次（插件要已安裝，
/// 或同時以 `--fmp-dev-plugin` 安裝）。不用逗號分隔：Android 的
/// `am start --esal` 以逗號切陣列。
const devPlaybackArgument = '--fmp-dev-playback';

/// 內附測試插件的安裝檔（dev flavor 的 asset）。
const devTestPluginAsset = 'test/fixtures/plugins/test_plugin/test_plugin.js';

/// 測試插件的三首（`resolveStream` 都回同一個 2 秒的音檔）。
const devTestTracks = ['tone-220', 'tone-440', 'tone-880'];

/// 從 [arguments] 找播放的開發入口：沒有、或 [flavor] 不是 dev 就是 `null`；
/// 只有旗標是空清單；否則是依序的每個值。
List<String>? devPlaybackRequest(AppFlavor flavor, List<String> arguments) {
  if (flavor != AppFlavor.dev) return null;
  List<String>? values;
  for (final argument in arguments) {
    if (argument == devPlaybackArgument) {
      values ??= [];
    } else if (argument.startsWith('$devPlaybackArgument=')) {
      (values ??= []).add(argument.substring(devPlaybackArgument.length + 1));
    }
  }
  return values;
}

/// 把 `--fmp-dev-playback=` 的值轉成曲目鍵；有任何一個格式不對就拋
/// [FormatException]。
List<TrackKeyParts> parseDevPlaybackTracks(List<String> values) => [
  for (final raw in values)
    TrackKey.tryParse(raw.trim()) ??
        (throw FormatException('Not a track key', raw)),
];

/// `main()` 以 [devPlaybackRequest] override；預設 `null`（不播）。
final devPlaybackRequestProvider = Provider<List<String>?>((ref) => null);

/// 播放的開發入口：照 [devPlaybackRequestProvider] 開始播放；沒有要求時什麼都
/// 不做。
final devPlaybackProvider = FutureProvider<void>((ref) async {
  final request = ref.watch(devPlaybackRequestProvider);
  if (request == null) return;
  final List<TrackKeyParts> tracks;
  if (request.isEmpty) {
    final plugin = await ref
        .watch(pluginInstallerProvider)
        .installSource(await rootBundle.loadString(devTestPluginAsset));
    tracks = [
      for (final sourceId in devTestTracks)
        TrackKeyParts(sourceTypeId: plugin.manifest.id, sourceId: sourceId),
    ];
  } else {
    tracks = parseDevPlaybackTracks(request);
    await ref.watch(devPluginInstallProvider.future);
    await ref.watch(pluginRegistryProvider.future);
  }
  ref
      .watch(logProvider)
      .info(
        'Development playback started',
        tag: 'playback',
        fields: {
          'tracks': [for (final track in tracks) '$track'],
        },
      );
  await ref.watch(playbackControllerProvider).playQueue(tracks);
});
