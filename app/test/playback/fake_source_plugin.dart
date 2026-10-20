import 'dart:async';

import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 假的插件：`resolveStream` 的候選由 [respond] 決定、是不是試聽片段由
/// [previewOnly] 決定；給了 [onSearch] 才有 `search` 能力。記下每次請求。
final class FakeSourcePlugin implements SourcePlugin {
  FakeSourcePlugin(
    this.respond, {
    String id = 'fmp-test',
    String name = 'Fake',
    this.onSearch,
    bool live = false,
    bool mix = false,
    bool multiPart = false,
    bool trackDetail = false,
    bool libraryRead = false,
    bool libraryWrite = false,
  }) : manifest = PluginManifest(
         id: id,
         name: name,
         version: '1.0.0',
         author: 'FMP tests',
         capabilities: {
           PluginCapability.resolveStream,
           if (onSearch != null) PluginCapability.search,
           if (live) PluginCapability.live,
           if (mix) PluginCapability.mix,
           if (multiPart) PluginCapability.multiPart,
           if (trackDetail) PluginCapability.trackDetail,
           if (libraryRead) PluginCapability.libraryRead,
           if (libraryWrite) PluginCapability.libraryWrite,
         },
         allowedHosts: const ['cdn.example'],
       );

  FutureOr<List<StreamCandidate>> Function(StreamRequest request) respond;

  /// 回傳的 [StreamResult.previewOnly]。
  bool Function(StreamRequest request) previewOnly = (_) => false;

  /// 搜尋的回傳；`null` 表示沒有 `search` 能力。
  final FutureOr<SearchPage> Function(SearchQuery query)? onSearch;

  final requests = <StreamRequest>[];
  final searches = <SearchQuery>[];

  // 直播（`live: true` 時才有能力）：沒設定的處理函式呼叫就拋 UnimplementedError。
  FutureOr<LiveRoom> Function(LiveRoomQuery query)? onLiveStatus;
  FutureOr<List<StreamCandidate>> Function(LiveStreamRequest request)?
  onResolveLive;
  FutureOr<LiveRoomRef?> Function(LiveUrlQuery query)? onLiveRoomFromUrl;
  FutureOr<LiveSearchPage> Function(LiveSearchQuery query)? onLiveSearch;
  final liveSearches = <LiveSearchQuery>[];
  final liveStatusQueries = <LiveRoomQuery>[];
  final liveRequests = <LiveStreamRequest>[];
  final liveUrlQueries = <LiveUrlQuery>[];

  // Mix（`mix: true` 時才有能力）：沒設定處理函式就拋 UnimplementedError。
  FutureOr<MixBatch> Function(MixQuery query)? onMix;
  final mixQueries = <MixQuery>[];

  // 分 P（`multiPart: true` 時才有能力）：沒設定處理函式就拋 UnimplementedError。
  FutureOr<MultiPartResult> Function(MultiPartQuery query)? onMultiPart;
  final multiPartQueries = <MultiPartQuery>[];

  // 曲目詳細（`trackDetail: true` 時才有能力）：沒設定處理函式就拋 UnimplementedError。
  FutureOr<TrackDetail> Function(TrackDetailQuery query)? onTrackDetail;
  final trackDetailQueries = <TrackDetailQuery>[];

  // 帳號歌單（`libraryRead: true` 時才有能力）：沒設定處理函式就拋 UnimplementedError。
  FutureOr<LibraryPlaylistPage> Function(LibraryPlaylistsQuery query)?
  onLibraryPlaylists;
  final libraryPlaylistQueries = <LibraryPlaylistsQuery>[];

  // 遠端寫入（`libraryWrite: true` 時才有能力）：沒設定處理函式就拋 UnimplementedError。
  FutureOr<CreatePlaylistResult> Function(CreatePlaylistQuery query)?
  onCreatePlaylist;
  FutureOr<AddToPlaylistResponse> Function(AddToPlaylistQuery query)?
  onAddToPlaylist;
  FutureOr<RemoveFromPlaylistResponse> Function(RemoveFromPlaylistQuery query)?
  onRemoveFromPlaylist;
  final createPlaylistQueries = <CreatePlaylistQuery>[];
  final addToPlaylistQueries = <AddToPlaylistQuery>[];
  final removeFromPlaylistQueries = <RemoveFromPlaylistQuery>[];

  /// 對 [sourceId] 解析了幾次。
  int resolvedCount(String sourceId) =>
      requests.where((r) => r.sourceId == sourceId).length;

  @override
  final PluginManifest manifest;

  @override
  PluginHealth get health => PluginHealth.ready;

  @override
  Future<void> get whenUnresponsive => Completer<void>().future;

  @override
  Future<SearchPage> search(SearchQuery query) async {
    final onSearch = this.onSearch;
    if (onSearch == null) throw UnimplementedError('search');
    searches.add(query);
    return onSearch(query);
  }

  @override
  Future<StreamResult> resolveStream(StreamRequest request) async {
    requests.add(request);
    return StreamResult(
      candidates: await respond(request),
      previewOnly: previewOnly(request),
    );
  }

  @override
  Future<LiveSearchPage> liveSearch(LiveSearchQuery query) async {
    final handler = onLiveSearch;
    if (handler == null) throw UnimplementedError('live');
    liveSearches.add(query);
    return handler(query);
  }

  @override
  Future<LiveRoomRef?> liveRoomFromUrl(LiveUrlQuery query) async {
    final handler = onLiveRoomFromUrl;
    if (handler == null) throw UnimplementedError('live');
    liveUrlQueries.add(query);
    return handler(query);
  }

  @override
  Future<LiveRoom> liveStatus(LiveRoomQuery query) async {
    final handler = onLiveStatus;
    if (handler == null) throw UnimplementedError('live');
    liveStatusQueries.add(query);
    return handler(query);
  }

  @override
  Future<StreamResult> resolveLive(LiveStreamRequest request) async {
    final handler = onResolveLive;
    if (handler == null) throw UnimplementedError('live');
    liveRequests.add(request);
    return StreamResult(candidates: await handler(request));
  }

  @override
  Future<MixBatch> mix(MixQuery query) async {
    final handler = onMix;
    if (handler == null) throw UnimplementedError('mix');
    mixQueries.add(query);
    return handler(query);
  }

  @override
  Future<MultiPartResult> multiPart(MultiPartQuery query) async {
    final handler = onMultiPart;
    if (handler == null) throw UnimplementedError('multiPart');
    multiPartQueries.add(query);
    return handler(query);
  }

  @override
  Future<PlaylistRef?> playlistFromUrl(PlaylistUrlQuery query) =>
      throw UnimplementedError('importPlaylist');

  @override
  Future<PlaylistPage> importPlaylist(PlaylistPageQuery query) =>
      throw UnimplementedError('importPlaylist');

  @override
  Future<LibraryPlaylistPage> libraryPlaylists(
    LibraryPlaylistsQuery query,
  ) async {
    final handler = onLibraryPlaylists;
    if (handler == null) throw UnimplementedError('libraryRead');
    libraryPlaylistQueries.add(query);
    return handler(query);
  }

  @override
  Future<CreatePlaylistResult> createPlaylist(CreatePlaylistQuery query) async {
    final handler = onCreatePlaylist;
    if (handler == null) throw UnimplementedError('libraryWrite');
    createPlaylistQueries.add(query);
    return handler(query);
  }

  @override
  Future<AddToPlaylistResponse> addToPlaylist(AddToPlaylistQuery query) async {
    final handler = onAddToPlaylist;
    if (handler == null) throw UnimplementedError('libraryWrite');
    addToPlaylistQueries.add(query);
    return handler(query);
  }

  @override
  Future<RemoveFromPlaylistResponse> removeFromPlaylist(
    RemoveFromPlaylistQuery query,
  ) async {
    final handler = onRemoveFromPlaylist;
    if (handler == null) throw UnimplementedError('libraryWrite');
    removeFromPlaylistQueries.add(query);
    return handler(query);
  }

  @override
  Future<ChartList> chartList() => throw UnimplementedError('charts');

  @override
  Future<ChartPage> chart(ChartQuery query) =>
      throw UnimplementedError('charts');

  @override
  Future<TrackDetail> trackDetail(TrackDetailQuery query) async {
    final handler = onTrackDetail;
    if (handler == null) throw UnimplementedError('trackDetail');
    trackDetailQueries.add(query);
    return handler(query);
  }

  @override
  Future<LoginQrCode> loginQrStart() => throw UnimplementedError('login');

  @override
  Future<LoginQrPoll> loginQrPoll(String token) =>
      throw UnimplementedError('login');

  @override
  Future<LoginAccount> loginVerify(LoginCredentials credentials) =>
      throw UnimplementedError('login');

  @override
  Future<LoginCredentials?> loginRefresh(LoginCredentials credentials) =>
      throw UnimplementedError('login');

  @override
  void close() {}
}

/// `https://cdn.example/<name>` 的候選。
StreamCandidate candidate(
  String name, {
  Map<String, String> headers = const {},
  DateTime? expiresAt,
  int? bitrate,
}) => StreamCandidate(
  url: Uri.parse('https://cdn.example/$name'),
  headers: headers,
  container: 'mp4',
  codec: 'aac',
  bitrate: bitrate,
  expiresAt: expiresAt,
);
