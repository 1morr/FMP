/// 缩略图 URL 工具类
///
/// 用于将高清图片 URL 转换为适合显示尺寸的缩略图 URL，
/// 以减少网络传输量、磁盘缓存占用和内存使用。
///
/// 支持的图片源：
/// - Bilibili (hdslb.com)
/// - YouTube (ytimg.com, yt3.ggpht.com)
class ThumbnailUrlUtils {
  ThumbnailUrlUtils._();

  /// 缩略图尺寸预设
  static const int smallSize = 120;   // 列表小图
  static const int mediumSize = 200;  // 网格卡片
  static const int largeSize = 480;   // 详情页

  /// 获取适合显示尺寸的缩略图 URL
  ///
  /// [url] 原始图片 URL
  /// [displaySize] 显示尺寸（像素），用于选择合适的缩略图
  /// [devicePixelRatio] 设备像素比，默认 2.0（考虑高清屏）
  ///
  /// 返回优化后的 URL，如果无法优化则返回原 URL
  static String getOptimizedUrl(
    String? url, {
    double? displaySize,
    double devicePixelRatio = 2.0,
  }) {
    if (url == null || url.isEmpty) return url ?? '';

    // 计算实际需要的像素尺寸
    final targetSize = displaySize != null
        ? (displaySize * devicePixelRatio).toInt()
        : mediumSize * devicePixelRatio.toInt();

    // 根据 URL 域名选择处理方式
    if (_isBilibiliUrl(url)) {
      return _optimizeBilibiliUrl(url, targetSize);
    } else if (_isYouTubeUrl(url)) {
      return _optimizeYouTubeUrl(url, targetSize);
    }

    // 其他 URL 原样返回
    return url;
  }

  /// 检查是否为 Bilibili 图片 URL
  static bool _isBilibiliUrl(String url) {
    return url.contains('hdslb.com') || url.contains('bilibili.com');
  }

  /// 检查是否为 YouTube 图片 URL
  static bool _isYouTubeUrl(String url) {
    return url.contains('ytimg.com') ||
        url.contains('ggpht.com') ||
        url.contains('googleusercontent.com');
  }

  /// 优化 Bilibili 图片 URL
  ///
  /// Bilibili 图片 URL 支持后缀参数：
  /// - @{width}w_{height}h.jpg - 指定宽高
  /// - @{width}w.jpg - 指定宽度，高度自适应
  /// - @{size}w_{size}h_1c.jpg - 正方形裁剪
  ///
  /// 示例：
  /// - 原始：https://i0.hdslb.com/bfs/archive/xxx.jpg
  /// - 优化：https://i0.hdslb.com/bfs/archive/xxx.jpg@200w_200h.jpg
  static String _optimizeBilibiliUrl(String url, int targetSize) {
    // 移除已有的尺寸后缀
    String baseUrl = url;
    final atIndex = url.indexOf('@');
    if (atIndex != -1) {
      baseUrl = url.substring(0, atIndex);
    }

    // 选择合适的尺寸档位
    final size = _selectBilibiliSize(targetSize);

    // 添加尺寸后缀（保持宽高比）
    return '$baseUrl@${size}w.jpg';
  }

  /// 选择 Bilibili 合适的尺寸档位
  ///
  /// Bilibili 图片服务支持任意尺寸，但为了利用 CDN 缓存，
  /// 我们使用固定的几个档位
  static int _selectBilibiliSize(int targetSize) {
    // 档位：200, 400, 640, 原图
    if (targetSize <= 200) return 200;
    if (targetSize <= 400) return 400;
    if (targetSize <= 640) return 640;
    return 1280; // 大于 640 使用 1280
  }

  /// 优化 YouTube 图片 URL
  ///
  /// YouTube 缩略图 URL 格式：
  /// - https://i.ytimg.com/vi/{videoId}/{quality}.jpg
  ///
  /// 可用的质量档位：
  /// - default.jpg (120x90)
  /// - mqdefault.jpg (320x180)
  /// - hqdefault.jpg (480x360)
  /// - sddefault.jpg (640x480)
  /// - maxresdefault.jpg (1280x720)
  ///
  /// 频道头像 URL 格式（ggpht.com）：
  /// - https://yt3.ggpht.com/xxx=s{size}-c-k-c0x00ffffff-no-rj
  static String _optimizeYouTubeUrl(String url, int targetSize) {
    // 处理视频缩略图
    if (url.contains('ytimg.com')) {
      return _optimizeYouTubeThumbnail(url, targetSize);
    }

    // 处理频道头像
    if (url.contains('ggpht.com') || url.contains('googleusercontent.com')) {
      return _optimizeYouTubeAvatar(url, targetSize);
    }

    return url;
  }

  /// 优化 YouTube 视频缩略图
  static String _optimizeYouTubeThumbnail(String url, int targetSize) {
    // 选择合适的质量档位
    final quality = _selectYouTubeQuality(targetSize);

    // 替换 URL 中的质量参数
    // 常见格式：/vi/{videoId}/hqdefault.jpg 或 /vi_webp/{videoId}/hqdefault.webp
    final pattern = RegExp(r'/vi(_webp)?/([^/]+)/[^/]+\.(jpg|webp)');

    final match = pattern.firstMatch(url);
    if (match != null) {
      final isWebp = match.group(1) != null; // 原始 URL 是否使用 webp
      final videoId = match.group(2);
      final ext = match.group(3); // 保持原始扩展名

      // 保持原始格式（不强制转换为 webp，因为不是所有视频都支持）
      if (isWebp) {
        return 'https://i.ytimg.com/vi_webp/$videoId/$quality.webp';
      } else {
        return 'https://i.ytimg.com/vi/$videoId/$quality.$ext';
      }
    }

    // 无法解析的 URL 原样返回
    return url;
  }

  /// 选择 YouTube 缩略图质量档位
  static String _selectYouTubeQuality(int targetSize) {
    // 档位对应的短边尺寸
    // default: 90, mq: 180, hq: 360, sd: 480, maxres: 720
    if (targetSize <= 90) return 'default';
    if (targetSize <= 180) return 'mqdefault';
    if (targetSize <= 360) return 'hqdefault';
    if (targetSize <= 480) return 'sddefault';
    return 'maxresdefault';
  }

  /// 优化 YouTube 频道头像
  static String _optimizeYouTubeAvatar(String url, int targetSize) {
    // 频道头像 URL 格式：
    // https://yt3.ggpht.com/xxx=s{size}-c-k-c0x00ffffff-no-rj
    // 或者：https://yt3.ggpht.com/xxx=s176-c-k-c0x00ffffff-no-rj

    // 选择合适的尺寸
    final size = _selectAvatarSize(targetSize);

    // 替换尺寸参数
    final sizePattern = RegExp(r'=s\d+');
    if (sizePattern.hasMatch(url)) {
      return url.replaceFirst(sizePattern, '=s$size');
    }

    // 如果没有尺寸参数，尝试添加
    if (url.contains('ggpht.com') && !url.contains('=s')) {
      return '$url=s$size';
    }

    return url;
  }

  /// 选择头像尺寸
  static int _selectAvatarSize(int targetSize) {
    // 头像常用尺寸：48, 88, 176, 240
    if (targetSize <= 48) return 48;
    if (targetSize <= 88) return 88;
    if (targetSize <= 176) return 176;
    return 240;
  }

  /// 获取小尺寸缩略图 URL（用于列表项）
  static String getSmallThumbnail(String? url) {
    return getOptimizedUrl(url, displaySize: smallSize.toDouble());
  }

  /// 获取中等尺寸缩略图 URL（用于网格卡片）
  static String getMediumThumbnail(String? url) {
    return getOptimizedUrl(url, displaySize: mediumSize.toDouble());
  }

  /// 获取大尺寸缩略图 URL（用于详情页）
  static String getLargeThumbnail(String? url) {
    return getOptimizedUrl(url, displaySize: largeSize.toDouble());
  }
}
