import 'dart:async';

import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 假的 `importPlaylist` 插件：歌單的頁由 [onPage] 決定、網址的判斷由 [onUrl] 決定（預設
/// 全部不認得）。記下每次呼叫。其他能力一律拋 [UnimplementedError]。
final class FakeImportPlugin implements SourcePlugin {
  FakeImportPlugin({
    String id = 'fmp-test',
    bool resolveStream = true,
    bool mix = false,
    FutureOr<PlaylistPage> Function(PlaylistPageQuery query)? onPage,
    FutureOr<PlaylistRef?> Function(PlaylistUrlQuery query)? onUrl,
  }) : onPage = onPage ?? ((_) => throw UnimplementedError('onPage')),
       onUrl = onUrl ?? ((_) => null),
       manifest = PluginManifest(
         id: id,
         name: 'Fake $id',
         version: '1.0.0',
         author: 'FMP tests',
         capabilities: {
           PluginCapability.importPlaylist,
           if (resolveStream) PluginCapability.resolveStream,
           if (mix) PluginCapability.mix,
         },
         allowedHosts: const ['fmp.test'],
       );

  FutureOr<PlaylistPage> Function(PlaylistPageQuery query) onPage;
  FutureOr<PlaylistRef?> Function(PlaylistUrlQuery query) onUrl;

  final pageQueries = <PlaylistPageQuery>[];
  final urlQueries = <PlaylistUrlQuery>[];

  @override
  final PluginManifest manifest;

  @override
  PluginHealth get health => PluginHealth.ready;

  @override
  Future<void> get whenUnresponsive => Completer<void>().future;

  @override
  Future<PlaylistRef?> playlistFromUrl(PlaylistUrlQuery query) async {
    urlQueries.add(query);
    return onUrl(query);
  }

  @override
  Future<PlaylistPage> importPlaylist(PlaylistPageQuery query) async {
    pageQueries.add(query);
    return onPage(query);
  }

  @override
  void close() {}

  // 其他能力沒有人呼叫：一律拋，不寫空殼。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 一頁：[ids] 是曲目的音源 id（同 id 同曲目鍵）；[remoteIds] 給了就依序當 `remoteItemId`。
PlaylistPage page(
  List<String> ids, {
  String title = 'Remote title',
  String? description,
  String? ownerName = 'Owner',
  bool? writable,
  String? cursor,
  int? total,
  List<String>? remoteIds,
  Set<int> unavailable = const {},
  String Function(String id)? trackTitle,
}) => PlaylistPage(
  playlist: RemotePlaylist(
    title: title,
    description: description,
    ownerName: ownerName,
    writable: writable,
  ),
  items: [
    for (final (index, id) in ids.indexed)
      RemotePlaylistItem(
        track: TrackSummary(
          sourceTypeId: 'fmp-test',
          sourceId: id,
          title: trackTitle?.call(id) ?? 'Song $id',
        ),
        remoteItemId: remoteIds?[index],
        unavailable: unavailable.contains(index),
      ),
  ],
  cursor: cursor,
  total: total,
);
