import 'dart:async';

import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 只有 `resolveStream` 的插件，回傳由 [respond] 決定；記下每次請求。
final class FakeSourcePlugin implements SourcePlugin {
  FakeSourcePlugin(this.respond, {String id = 'fmp-test'})
    : manifest = PluginManifest(
        id: id,
        name: 'Fake',
        version: '1.0.0',
        author: 'FMP tests',
        capabilities: const {PluginCapability.resolveStream},
        allowedHosts: const ['cdn.example'],
      );

  FutureOr<List<StreamCandidate>> Function(StreamRequest request) respond;

  final requests = <StreamRequest>[];

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
  Future<SearchPage> search(SearchQuery query) =>
      throw UnimplementedError('search');

  @override
  Future<List<StreamCandidate>> resolveStream(StreamRequest request) async {
    requests.add(request);
    return respond(request);
  }

  @override
  void close() {}
}

/// `https://cdn.example/<name>` 的候選。
StreamCandidate candidate(
  String name, {
  Map<String, String> headers = const {},
  DateTime? expiresAt,
}) => StreamCandidate(
  url: Uri.parse('https://cdn.example/$name'),
  headers: headers,
  container: 'mp4',
  codec: 'aac',
  expiresAt: expiresAt,
);
