import 'package:fmp/legacy_import/legacy_source_ids.dart';

// 舊版匯入歌單的 `sourceUrl` → 新版 `playlist_remote` 的（插件, 遠端 id）（M5 design §5.3）。
//
// 只認不需要連網的形式，規則照官方插件的 `playlistFromUrl`（寫成 Dart 版）：
// - bilibili 1.10.0：`bilibili/src/plugin.js` 的 `playlistFromUrl`（約 :412）；
// - youtube 1.6.0：`youtube/src/playlist.js` 的 `playlistFromUrl`（約 :30）；
// - netease 1.7.0：`netease/src/plugin.js` 的 `playlistFromUrl`（約 :300）及 `playlistIdIn`。
// 網易的 `163cn.tv` 短網址要連網，認不出來。
// 兩個 repo 沒有自動的一致性檢查：插件改了輸出形狀要回頭改這裡（閘門：
// `test/legacy_import/remote_playlist_url_test.dart` 的表格，期望值取自各插件的單元測試）。

/// 認出來的遠端歌單。
final class RecognizedRemote {
  const RecognizedRemote({required this.pluginId, required this.remoteId});

  final String pluginId;
  final String remoteId;

  @override
  bool operator ==(Object other) =>
      other is RecognizedRemote &&
      other.pluginId == pluginId &&
      other.remoteId == remoteId;

  @override
  int get hashCode => Object.hash(pluginId, remoteId);

  @override
  String toString() => 'RecognizedRemote($pluginId, $remoteId)';
}

/// 依序試三個插件的規則（網域互不重疊，順序不影響結果）；都認不出回 `null`。
RecognizedRemote? recognizeRemotePlaylistUrl(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  final bilibili = _bilibili(raw);
  if (bilibili != null) {
    return RecognizedRemote(pluginId: legacyBilibili, remoteId: bilibili);
  }
  final youtube = _youtube(raw);
  if (youtube != null) {
    return RecognizedRemote(pluginId: legacyYoutube, remoteId: youtube);
  }
  final netease = _netease(raw);
  if (netease != null) {
    return RecognizedRemote(pluginId: legacyNetease, remoteId: netease);
  }
  return null;
}

// ---------------------------------------------------------------- 共用

/// 沒有 scheme 的輸入當成 https（插件也是）。
const _defaultScheme = 'https';
final _hasScheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
final _splitPattern = RegExp(
  r'^https?://([^/?#]+)([^?#]*)(?:\?([^#]*))?(?:#([\s\S]*))?$',
  caseSensitive: false,
);
final _port = RegExp(r':\d+$');
final _trailingDots = RegExp(r'\.+$');

/// 網址拆成 host（小寫、去連接埠與結尾的點）、path、query、fragment；沒有 scheme 當 https，
/// 不是 http(s) 或 host 帶 `@` 回 `null`（插件的 `splitUrl`）。
({String host, String path, String query, String fragment})? _split(
  String raw,
) {
  final text = _hasScheme.hasMatch(raw) ? raw : '$_defaultScheme://$raw';
  final match = _splitPattern.firstMatch(text);
  if (match == null || match.group(1)!.contains('@')) return null;
  return (
    host: match
        .group(1)!
        .replaceFirst(_port, '')
        .toLowerCase()
        .replaceFirst(_trailingDots, ''),
    path: match.group(2) ?? '',
    query: match.group(3) ?? '',
    fragment: match.group(4) ?? '',
  );
}

// ---------------------------------------------------------------- bilibili

const _bilibiliHosts = {
  'bilibili.com',
  'www.bilibili.com',
  'm.bilibili.com',
  'space.bilibili.com',
};
final _mediaId = RegExp(r'^[1-9]\d{0,17}$');
final _fid = RegExp(r'(?:^|&)fid=(\d+)(?:&|$)');
final _mlSegment = RegExp(r'^ml(\d+)$');

String? _bilibili(String raw) {
  final parts = _split(raw);
  if (parts == null || !_bilibiliHosts.contains(parts.host)) return null;
  final fid = _fid.firstMatch(parts.query);
  if (fid != null && _mediaId.hasMatch(fid.group(1)!)) return fid.group(1);
  for (final segment in parts.path.split('/')) {
    final ml = _mlSegment.firstMatch(segment);
    if (ml != null && _mediaId.hasMatch(ml.group(1)!)) return ml.group(1);
  }
  return null;
}

// ---------------------------------------------------------------- youtube

const _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};
final _youtubeId = RegExp(r'^[A-Za-z0-9_-]+$');
const _maxYoutubePlaylistIdLength = 100;

String? _youtube(String raw) {
  // `mix:<id>` 簡寫與 `list=RD…` 是 Mix（插件回 mixSeed），不是歌單。
  if (raw.toLowerCase().startsWith('mix:')) return null;
  final uri = Uri.tryParse(
    _hasScheme.hasMatch(raw) ? raw : '$_defaultScheme://$raw',
  );
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  if (!_youtubeHosts.contains(
    uri.host.toLowerCase().replaceFirst(_trailingDots, ''),
  )) {
    return null;
  }
  final String? list;
  try {
    list = uri.queryParametersAll['list']?.first;
  } on FormatException {
    return null;
  }
  if (list == null || list.isEmpty || list.startsWith('RD')) return null;
  if (list.length > _maxYoutubePlaylistIdLength || !_youtubeId.hasMatch(list)) {
    return null;
  }
  return list;
}

// ---------------------------------------------------------------- netease

const _neteaseHosts = {'music.163.com', 'y.music.163.com'};
final _neteasePlaylistId = RegExp(r'^[1-9]\d{0,17}$');
final _idParam = RegExp(r'(?:^|&)id=(\d+)(?:&|$)');
final _fragmentSplit = RegExp(r'^([^?]*)(?:\?(.*))?$');

String? _neteaseIn(String path, String query) {
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final at = segments.indexOf('playlist');
  if (at < 0) return null;
  final fromQuery = _idParam.firstMatch(query);
  final id = fromQuery != null
      ? fromQuery.group(1)
      : (at + 1 < segments.length ? segments[at + 1] : null);
  return id != null && _neteasePlaylistId.hasMatch(id) ? id : null;
}

String? _netease(String raw) {
  final parts = _split(raw);
  if (parts == null || !_neteaseHosts.contains(parts.host)) return null;
  final direct = _neteaseIn(parts.path, parts.query);
  if (direct != null) return direct;
  final fragment = _fragmentSplit.firstMatch(parts.fragment);
  return fragment == null
      ? null
      : _neteaseIn(fragment.group(1) ?? '', fragment.group(2) ?? '');
}
