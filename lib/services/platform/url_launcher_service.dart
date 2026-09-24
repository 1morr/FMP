import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fmp/data/models/track.dart';

/// 一個外部頁面的 App scheme 與網頁網址。
typedef ExternalLink = ({String app, String web});

/// 外部連結都是「前綴 + id」。
typedef _LinkPrefixes = ({String app, String web});

extension on _LinkPrefixes {
  ExternalLink withId(String id) => (app: '$app$id', web: '$web$id');
}

/// 影片（歌曲）頁，以音源 id 為鍵。
const Map<String, _LinkPrefixes> _videoLinks = {
  SourceIds.bilibili: (
    app: 'bilibili://video/',
    web: 'https://www.bilibili.com/video/',
  ),
  SourceIds.youtube: (
    app: 'youtube://watch?v=',
    web: 'https://www.youtube.com/watch?v=',
  ),
  SourceIds.netease: (
    app: 'orpheus://song/',
    web: 'https://music.163.com/song?id=',
  ),
};

/// UP 主／頻道頁。網易雲沒有這一頁。Bilibili 用數字的 UP 主 id
/// （[Track.ownerId]），YouTube 用頻道 id（[Track.channelId]）。
const Map<String, ({_LinkPrefixes links, bool byOwnerId})> _channelLinks = {
  SourceIds.bilibili: (
    links: (app: 'bilibili://space/', web: 'https://space.bilibili.com/'),
    byOwnerId: true,
  ),
  SourceIds.youtube: (
    links: (app: 'youtube://channel/', web: 'https://www.youtube.com/channel/'),
    byOwnerId: false,
  ),
};

/// URL 启动服务
///
/// 负责处理跨平台的 URL 跳转逻辑：
/// - 桌面平台：始终打开网页
/// - 移动平台：优先尝试打开 App，失败则打开网页
class UrlLauncherService {
  UrlLauncherService._();

  static final UrlLauncherService instance = UrlLauncherService._();

  /// 打开视频页面
  ///
  /// [track] - 歌曲信息
  /// [bvid] - Bilibili 视频 ID（可选，优先使用 track.sourceId）
  Future<bool> openVideo(Track track, {String? bvid}) async {
    final link = videoLinkFor(track.sourceType, bvid ?? track.sourceId);
    return link != null && await _open(link);
  }

  /// 打开 UP主/频道页面
  ///
  /// [track] - 歌曲信息
  /// [ownerId] - Bilibili UP主 ID（可选，优先使用 track.ownerId）
  /// [channelId] - YouTube 频道 ID（可选，优先使用 track.channelId）
  Future<bool> openChannel(
    Track track, {
    int? ownerId,
    String? channelId,
  }) async {
    final link = channelLinkFor(track, ownerId: ownerId, channelId: channelId);
    return link != null && await _open(link);
  }

  /// 影片頁的連結；這個音源沒有影片頁時回 null。
  @visibleForTesting
  static ExternalLink? videoLinkFor(String sourceType, String videoId) =>
      _videoLinks[sourceType]?.withId(videoId);

  /// UP 主／頻道頁的連結；音源沒有這一頁、或曲目缺那個 id 時回 null。
  @visibleForTesting
  static ExternalLink? channelLinkFor(
    Track track, {
    int? ownerId,
    String? channelId,
  }) {
    final channel = _channelLinks[track.sourceType];
    if (channel == null) return null;
    final id = channel.byOwnerId
        ? (ownerId ?? track.ownerId)?.toString()
        : channelId ?? track.channelId;
    if (id == null || id.isEmpty) return null;
    return channel.links.withId(id);
  }

  /// 打開 Bilibili 直播間
  ///
  /// [roomId] - 直播間房間號
  Future<bool> openBilibiliLive(String roomId) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 移動平台：優先嘗試 App
      final appScheme = 'bilibili://live/$roomId';
      final appLaunched = await _launchUrl(appScheme);
      if (appLaunched) return true;
    }

    // 桌面平台或 App 啟動失敗：打開網頁
    return _launchUrl('https://live.bilibili.com/$roomId');
  }

  /// 打開 Bilibili 用戶空間
  ///
  /// [uid] - 用戶 UID
  Future<bool> openBilibiliSpace(int uid) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 移動平台：優先嘗試 App
      final appScheme = 'bilibili://space/$uid';
      final appLaunched = await _launchUrl(appScheme);
      if (appLaunched) return true;
    }

    // 桌面平台或 App 啟動失敗：打開網頁
    return _launchUrl('https://space.bilibili.com/$uid');
  }

  /// 移動平台先試 App，沒裝再開網頁；桌面平台直接開網頁。
  Future<bool> _open(ExternalLink link) async {
    if (Platform.isAndroid || Platform.isIOS) {
      if (await _launchUrl(link.app)) return true;
    }
    return _launchUrl(link.web);
  }

  /// 启动 URL
  Future<bool> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      return false;
    }
  }
}
