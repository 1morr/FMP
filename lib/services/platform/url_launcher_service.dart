import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../data/models/track.dart';

/// 启动类型
enum _LaunchType {
  /// 视频页面
  video,

  /// UP主/频道页面
  channel,
}

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
    final videoId = bvid ?? track.sourceId;
    return _launch(
      type: _LaunchType.video,
      sourceType: track.sourceType,
      videoId: videoId,
    );
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
    final owner = ownerId ?? track.ownerId;
    final channel = channelId ?? track.channelId;

    if (track.sourceType == SourceType.bilibili && owner == null) {
      return false;
    }
    if (track.sourceType == SourceType.youtube && (channel == null || channel.isEmpty)) {
      return false;
    }

    return _launch(
      type: _LaunchType.channel,
      sourceType: track.sourceType,
      ownerId: owner,
      channelId: channel,
    );
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

  /// 内部启动方法
  Future<bool> _launch({
    required _LaunchType type,
    required SourceType sourceType,
    String? videoId,
    int? ownerId,
    String? channelId,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 移动平台：优先尝试 App Scheme
      final appScheme = _getAppScheme(
        type: type,
        sourceType: sourceType,
        videoId: videoId,
        ownerId: ownerId,
        channelId: channelId,
      );

      if (appScheme != null) {
        final appLaunched = await _launchUrl(appScheme);
        if (appLaunched) return true;
        // App 未安装，继续尝试网页
      }
    }

    // 桌面平台或 App 启动失败：打开网页
    final webUrl = _getWebUrl(
      type: type,
      sourceType: sourceType,
      videoId: videoId,
      ownerId: ownerId,
      channelId: channelId,
    );

    if (webUrl == null) return false;
    return _launchUrl(webUrl);
  }

  /// 获取 App Scheme URL（仅移动平台）
  String? _getAppScheme({
    required _LaunchType type,
    required SourceType sourceType,
    String? videoId,
    int? ownerId,
    String? channelId,
  }) {
    if (sourceType == SourceType.bilibili) {
      if (type == _LaunchType.video && videoId != null) {
        return 'bilibili://video/$videoId';
      } else if (type == _LaunchType.channel && ownerId != null) {
        return 'bilibili://space/$ownerId';
      }
    } else if (sourceType == SourceType.youtube) {
      if (type == _LaunchType.video && videoId != null) {
        return 'youtube://watch?v=$videoId';
      } else if (type == _LaunchType.channel && channelId != null && channelId.isNotEmpty) {
        return 'youtube://channel/$channelId';
      }
    }
    return null;
  }

  /// 获取网页 URL
  String? _getWebUrl({
    required _LaunchType type,
    required SourceType sourceType,
    String? videoId,
    int? ownerId,
    String? channelId,
  }) {
    if (sourceType == SourceType.bilibili) {
      if (type == _LaunchType.video && videoId != null) {
        return 'https://www.bilibili.com/video/$videoId';
      } else if (type == _LaunchType.channel && ownerId != null) {
        return 'https://space.bilibili.com/$ownerId';
      }
    } else if (sourceType == SourceType.youtube) {
      if (type == _LaunchType.video && videoId != null) {
        return 'https://www.youtube.com/watch?v=$videoId';
      } else if (type == _LaunchType.channel && channelId != null && channelId.isNotEmpty) {
        return 'https://www.youtube.com/channel/$channelId';
      }
    }
    return null;
  }

  /// 启动 URL
  Future<bool> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      return false;
    }
  }
}
