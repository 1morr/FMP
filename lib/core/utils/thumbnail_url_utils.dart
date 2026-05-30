/// 缩略图 URL 工具类
///
/// 用于将高清图片 URL 转换为适合显示尺寸的缩略图 URL，
/// 以减少网络传输量、磁盘缓存占用和内存使用。
///
/// 支持的图片源：
/// - Bilibili (hdslb.com)
/// - YouTube (ytimg.com, yt3.ggpht.com)
/// - Netease (music.126.net)
class ThumbnailUrlUtils {
  ThumbnailUrlUtils._();

  /// 缩略图尺寸预设
  static const int smallSize = 120; // 列表小图
  static const int mediumSize = 200; // 网格卡片
  static const int largeSize = 480; // 详情页

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
    final candidates = getOptimizedUrlCandidates(
      url,
      displaySize: displaySize,
      devicePixelRatio: devicePixelRatio,
    );
    return candidates.isNotEmpty ? candidates.first : '';
  }

  /// 获取按优先级排序的缩略图候选 URL
  ///
  /// 用于先尝试优化后的 URL，失败时再回退到原始 URL。
  static List<String> getOptimizedUrlCandidates(
    String? url, {
    double? displaySize,
    double devicePixelRatio = 2.0,
  }) {
    if (url == null || url.isEmpty) return const [];

    // 计算实际需要的像素尺寸
    final targetSize = displaySize != null
        ? (displaySize * devicePixelRatio).toInt()
        : mediumSize * devicePixelRatio.toInt();

    final candidates = <String>[];

    void addCandidate(String candidate) {
      if (candidate.isNotEmpty && !candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    // 根据 URL 域名选择处理方式
    if (_isBilibiliUrl(url)) {
      for (final candidate in _optimizeBilibiliUrlCandidates(url, targetSize)) {
        addCandidate(candidate);
      }
    } else if (_isYouTubeUrl(url) && url.contains('ytimg.com')) {
      // YouTube 视频缩略图：生成从高到低多级质量候选，逐级回退
      for (final candidate
          in _optimizeYouTubeThumbnailCandidates(url, targetSize)) {
        addCandidate(candidate);
      }
    } else if (_isYouTubeUrl(url)) {
      addCandidate(_optimizeYouTubeUrl(url, targetSize));
    } else if (_isNeteaseUrl(url)) {
      for (final candidate in _optimizeNeteaseUrlCandidates(url, targetSize)) {
        addCandidate(candidate);
      }
    }

    // 最后回退到原始 URL。YouTube 的 default/hqdefault/sddefault 是 4:3
    // 档位，常带黑边；用户界面只显示 16:9 候选，避免任何黑边封面。
    if (!_isYouTubeBlackBarThumbnail(url)) {
      addCandidate(url);
    }
    return candidates;
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

  static bool _isYouTubeBlackBarThumbnail(String url) {
    final match =
        RegExp(r'/vi(?:_webp)?/[^/]+/([^/]+)\.(?:jpg|webp)').firstMatch(url);
    final quality = match?.group(1);
    return quality == 'default' ||
        quality == 'hqdefault' ||
        quality == 'sddefault';
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

  /// 生成 Bilibili 缩略图多级尺寸候选 URL（从高到低）
  ///
  /// 从期望尺寸向下逐级生成候选，避免直接回退到原始大图。
  static List<String> _optimizeBilibiliUrlCandidates(
      String url, int targetSize) {
    const sizes = [1280, 640, 400, 200];

    final baseUrl =
        url.contains('@') ? url.substring(0, url.indexOf('@')) : url;
    final desiredSize = _selectBilibiliSize(targetSize);

    final candidates = <String>[];
    var include = false;
    for (final size in sizes) {
      if (size == desiredSize) include = true;
      if (include) {
        candidates.add('$baseUrl@${size}w.jpg');
      }
    }
    // 不包含原图本身，由 getOptimizedUrlCandidates 添加
    return candidates;
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
    final quality = _selectYouTubeQuality(targetSize);
    return _buildYouTubeThumbnailUrl(url, quality);
  }

  /// 生成 YouTube 缩略图多级质量候选 URL（从高到低）
  ///
  /// 仅生成 16:9 质量档位的候选（maxresdefault、mqdefault），
  /// 排除 4:3 档位（sddefault、hqdefault、default）以避免黑边。
  /// 4:3 原始 URL 不会作为最终回退添加，以避免显示黑边。
  static List<String> _optimizeYouTubeThumbnailCandidates(
      String url, int targetSize) {
    const qualityOrder = ['maxresdefault', 'mqdefault'];

    final pattern = RegExp(r'/vi(_webp)?/([^/]+)/([^/]+)\.(jpg|webp)');
    final match = pattern.firstMatch(url);
    if (match == null) return const [];

    final originalQuality = match.group(3);
    final desiredQuality = _selectYouTubeQuality(targetSize);

    final desiredIdx = qualityOrder.indexOf(desiredQuality);
    final originalIdx = qualityOrder.indexOf(originalQuality ?? 'mqdefault');

    if (desiredIdx < 0) return const [];

    final candidates = <String>[];

    if (originalIdx < 0) {
      // 原始 URL 不是 16:9 档位（如 hqdefault/sddefault）：
      // 从期望档位向下生成所有 16:9 候选，原始 URL 作为最终回退
      for (int i = desiredIdx; i < qualityOrder.length; i++) {
        final candidate = _buildYouTubeThumbnailUrl(url, qualityOrder[i]);
        if (candidate.isNotEmpty) candidates.add(candidate);
      }
    } else if (originalIdx < desiredIdx) {
      // 原始质量高于期望：从期望档位向下生成降级候选（跳过原始档位）
      for (int i = desiredIdx; i < qualityOrder.length; i++) {
        if (i == originalIdx) continue;
        final candidate = _buildYouTubeThumbnailUrl(url, qualityOrder[i]);
        if (candidate.isNotEmpty) candidates.add(candidate);
      }
    } else {
      // 原始质量低于或等于期望：从期望档位向下生成更高画质候选，到原始档位之前停止
      for (int i = desiredIdx; i < qualityOrder.length; i++) {
        if (i >= originalIdx) break;
        final candidate = _buildYouTubeThumbnailUrl(url, qualityOrder[i]);
        if (candidate.isNotEmpty) candidates.add(candidate);
      }
    }

    return candidates;
  }

  /// 用指定质量构建 YouTube 缩略图 URL
  ///
  /// 保留原始 URL 的格式 (WebP/JPG) 以確保可靠性。
  /// 少數影片（如 JqRggTDg5Bo）完全沒有 WebP 縮圖，
  /// 強制轉換會導致所有候選 URL 404，用戶看到長時間 loading spinner。
  static String _buildYouTubeThumbnailUrl(String url, String quality) {
    final pattern = RegExp(r'/vi(_webp)?/([^/]+)/([^/]+)\.(jpg|webp)');
    final match = pattern.firstMatch(url);
    if (match == null) return '';

    final isWebp = match.group(1) != null;
    final videoId = match.group(2);
    final ext = match.group(4);
    final prefix = isWebp ? 'vi_webp' : 'vi';
    return 'https://i.ytimg.com/$prefix/$videoId/$quality.$ext';
  }

  /// 选择 YouTube 缩略图质量档位
  ///
  /// 仅使用 16:9 档位：maxresdefault (1280×720) 和 mqdefault (320×180)。
  /// sddefault/hqdefault/default 是 4:3 格式，YouTube 对 16:9 视频会在
  /// 上下添加黑边填充；因此显示候选直接排除 4:3 档位。
  ///
  /// mqdefault (320×180) 对中小显示尺寸足够；
  /// maxresdefault (1280×720) 用于大尺寸显示，但非 HD 视频可能不存在，
  /// 此时会回退到原始 URL。
  static String _selectYouTubeQuality(int targetSize) {
    if (targetSize <= 360) return 'mqdefault';
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

  /// 检查是否为网易云图片 URL
  static bool _isNeteaseUrl(String url) {
    return url.contains('music.126.net');
  }

  /// 选择网易云合适的尺寸档位
  static int _selectNeteaseSize(int targetSize) {
    if (targetSize <= 100) return 100;
    if (targetSize <= 200) return 200;
    if (targetSize <= 400) return 400;
    return 800;
  }

  /// 生成网易云缩略图多级尺寸候选 URL（从高到低）
  static List<String> _optimizeNeteaseUrlCandidates(
      String url, int targetSize) {
    const sizes = [800, 400, 200, 100];

    final baseUrl = url.split('?').first;
    final desiredSize = _selectNeteaseSize(targetSize);

    final candidates = <String>[];
    var include = false;
    for (final size in sizes) {
      if (size == desiredSize) include = true;
      if (include) {
        candidates.add('$baseUrl?param=${size}y$size');
      }
    }
    return candidates;
  }
}
