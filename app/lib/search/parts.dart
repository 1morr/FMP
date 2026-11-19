import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

/// [track] 是不是一支多 P 影片（`GLOSSARY.md`〈分 P〉）：插件說它有兩個以上的
/// 分 P，而且宣告了 `listParts`（ADR 0039），畫面才標分 P 數、可以展開。
bool hasParts(Track track, PluginManifest? manifest) =>
    (track.partCount ?? 1) > 1 &&
    (manifest?.capabilities.contains(PluginCapability.listParts) ?? false);

/// 一首曲目所屬影片的每個分 P，依順序（插件能力 `listParts`）。失敗時丟
/// `AppError`；失敗的結果由 [readParts] 丟掉重列。
final partsProvider = FutureProvider.family<List<Track>, Track>((
  ref,
  track,
) async {
  final host = await ref.watch(pluginHostProvider.future);
  final plugin = host.pluginFor(track.ref);
  if (plugin == null) throw const Unsupported();
  return plugin.listParts(track);
});

/// 讀 [track] 的分 P；上次列失敗的先丟掉再重列。用 container 而不是
/// WidgetRef：選單收起時畫面可能已經換掉。
Future<List<Track>> readParts(ProviderContainer container, Track track) {
  final provider = partsProvider(track);
  if (container.read(provider).hasError) container.invalidate(provider);
  return container.read(provider.future);
}
