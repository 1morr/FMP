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
  }) : manifest = PluginManifest(
         id: id,
         name: name,
         version: '1.0.0',
         author: 'FMP tests',
         capabilities: {
           PluginCapability.resolveStream,
           if (onSearch != null) PluginCapability.search,
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
