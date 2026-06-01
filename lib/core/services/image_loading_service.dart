import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/ui_constants.dart';
import '../../data/sources/source_http_policy.dart';
import '../utils/thumbnail_url_utils.dart';
import 'network_image_cache_service.dart';

/// 统一的图片加载服务
///
/// 功能：
/// - 统一的图片加载优先级：本地 → 网络 → 占位符
/// - 本地图片：使用 FileImage + ResizeImage（Flutter 内置内存缓存）
/// - 网络图片：使用 CachedNetworkImage 进行内存 + 磁盘缓存
/// - 提供统一的占位符和错误处理
/// - 图片加载完成后有淡入效果
///
/// 注意：调用方应通过 FileExistsCache 预先验证本地文件存在后再传入 localPath，
/// 以避免在 build 期间执行同步 IO 操作。
///
/// ## 维护说明
///
/// 当前使用 `cached_network_image` (^3.4.1) 作为网络图片缓存方案。
/// 该包上游已约 2 年无实质性更新，但功能稳定且广泛使用。
/// 若未来 Flutter 大版本升级导致兼容性问题，迁移路径：
/// - [extended_image](https://pub.dev/packages/extended_image) —
///   fluttercandies 维护，内置缓存、手势、编辑功能，API 接近
/// - 或直接使用 `flutter_cache_manager` + `Image.network` 封装
///
/// `_FmpImageCacheManager` 已整合 `ImageCacheManager` mixin，
/// 支持 `maxWidthDiskCache` / `maxHeightDiskCache` 磁盘缩放。
/// 迁移时只需替换 Widget 层（`_CachedNetworkImage` → 新实现），
/// 缓存管理层可保持不变。
class ImageLoadingService {
  ImageLoadingService._();

  /// 清空所有图片缓存（网络）
  static Future<void> clearAllCache() async {
    await NetworkImageCacheService.clearCache();
  }

  /// 清空网络图片缓存
  static Future<void> clearNetworkCache() async {
    await NetworkImageCacheService.clearCache();
  }

  /// 加载图片 Widget
  ///
  /// 按照以下优先级加载：
  /// 1. 本地图片（如果提供了 localPath）
  /// 2. 网络图片（如果提供了 networkUrl）
  /// 3. 占位符
  ///
  /// [localPath] 本地文件路径（调用方应通过 FileExistsCache 预先验证存在）
  /// [networkUrl] 网络图片 URL
  /// [placeholder] 自定义占位符 Widget
  /// [fit] 图片填充模式
  /// [width] 宽度，仅控制显示布局
  /// [height] 高度，仅控制显示布局
  /// [targetDisplaySize] 图片源和缓存目标尺寸；不会从 width/height 推导
  /// [headers] 网络请求头（用于需要认证的图片）
  /// [showLoadingIndicator] 是否显示加载指示器
  /// [fadeInDuration] 淡入动画时长
  static Widget loadImage({
    String? localPath,
    String? networkUrl,
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    required double targetDisplaySize,
    Map<String, String>? headers,
    bool showLoadingIndicator = false,
    Duration fadeInDuration = AnimationDurations.fast,
  }) {
    // 1. 尝试加载本地图片（假设调用方已验证文件存在）
    if (localPath != null) {
      final file = File(localPath);
      return Builder(
        builder: (context) {
          final imageProvider = _localImageProvider(
            context,
            file,
            width: width,
            height: height,
            targetDisplaySize: targetDisplaySize,
          );
          return _FadeInImage(
            image: imageProvider,
            fit: fit,
            width: width,
            height: height,
            placeholder: placeholder,
            fadeInDuration: fadeInDuration,
            errorBuilder: (context, error, stackTrace) {
              // 本地文件加载失败，尝试网络图片
              return _loadNetworkOrPlaceholder(
                networkUrl: networkUrl,
                placeholder: placeholder,
                fit: fit,
                width: width,
                height: height,
                targetDisplaySize: targetDisplaySize,
                headers: headers,
                showLoadingIndicator: showLoadingIndicator,
                fadeInDuration: fadeInDuration,
              );
            },
          );
        },
      );
    }

    // 2. 尝试加载网络图片或显示占位符
    return _loadNetworkOrPlaceholder(
      networkUrl: networkUrl,
      placeholder: placeholder,
      fit: fit,
      width: width,
      height: height,
      targetDisplaySize: targetDisplaySize,
      headers: headers,
      showLoadingIndicator: showLoadingIndicator,
      fadeInDuration: fadeInDuration,
    );
  }

  /// 建立图片 Provider 候选列表，用于需要先预加载再显示的场景。
  ///
  /// 顺序与 [loadImage] 一致：本地图片优先，网络缩略图候选随后。
  /// 调用方可以逐个 `precacheImage`，成功后再显示，避免加载期间露出占位符。
  static List<ImageProvider> imageProviderCandidates({
    required BuildContext context,
    String? localPath,
    String? networkUrl,
    double? width,
    double? height,
    required double targetDisplaySize,
    Map<String, String>? headers,
  }) {
    final providers = <ImageProvider>[];

    if (localPath != null) {
      providers.add(
        _localImageProvider(
          context,
          File(localPath),
          width: width,
          height: height,
          targetDisplaySize: targetDisplaySize,
        ),
      );
    }

    if (networkUrl != null && networkUrl.isNotEmpty) {
      final request = _NetworkImageRequest.from(
        context: context,
        networkUrl: networkUrl,
        targetDisplaySize: targetDisplaySize,
        headers: headers,
      );

      for (final url in request.urls) {
        providers.add(
          CachedNetworkImageProvider(
            url,
            cacheKey: request.cacheKey(url),
            maxWidth: request.cacheExtent,
            maxHeight: request.cacheExtent,
            headers: request.headers,
            cacheManager: NetworkImageCacheService.defaultCacheManager,
          ),
        );
      }
    }

    return providers;
  }

  /// 逐一预加载图片候选，返回第一个成功加载的 provider。
  static Future<ImageProvider?> precacheImageCandidates({
    required BuildContext context,
    String? localPath,
    String? networkUrl,
    double? width,
    double? height,
    required double targetDisplaySize,
    Map<String, String>? headers,
  }) async {
    final candidates = imageProviderCandidates(
      context: context,
      localPath: localPath,
      networkUrl: networkUrl,
      width: width,
      height: height,
      targetDisplaySize: targetDisplaySize,
      headers: headers,
    );

    for (final candidate in candidates) {
      var failed = false;
      await precacheImage(
        candidate,
        context,
        onError: (_, __) => failed = true,
      );
      if (!failed) return candidate;
    }

    return null;
  }

  /// 加载网络图片或显示占位符
  static Widget _loadNetworkOrPlaceholder({
    String? networkUrl,
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    required double targetDisplaySize,
    Map<String, String>? headers,
    bool showLoadingIndicator = false,
    Duration fadeInDuration = AnimationDurations.fast,
  }) {
    if (networkUrl != null && networkUrl.isNotEmpty) {
      return Builder(
        builder: (context) {
          final request = _NetworkImageRequest.from(
            context: context,
            networkUrl: networkUrl,
            targetDisplaySize: targetDisplaySize,
            headers: headers,
          );

          return _CachedNetworkImage(
            request: request,
            fit: fit,
            width: width,
            height: height,
            placeholder: placeholder,
            showLoadingIndicator: showLoadingIndicator,
            fadeInDuration: fadeInDuration,
          );
        },
      );
    }

    return placeholder;
  }

  /// 加载头像图片
  ///
  /// 专门用于 UP主/艺术家头像
  ///
  /// [localPath] 本地头像路径
  /// [networkUrl] 网络头像 URL
  /// [size] 头像尺寸（直径）
  /// [targetDisplaySize] 图片源和缓存目标尺寸；必须由调用方显式传入
  static Widget loadAvatar({
    String? localPath,
    String? networkUrl,
    double size = 40,
    required double targetDisplaySize,
  }) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        // 头像使用圆形裁剪
        return ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: loadImage(
              localPath: localPath,
              networkUrl: networkUrl,
              placeholder: Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: colorScheme.outline,
                ),
              ),
              fit: BoxFit.cover,
              width: size,
              height: size,
              targetDisplaySize: targetDisplaySize,
            ),
          ),
        );
      },
    );
  }

  /// 构建图标占位符
  static Widget _buildIconPlaceholder({
    required ColorScheme colorScheme,
    required IconData icon,
    required double iconSize,
    Color? backgroundColor,
  }) {
    return Container(
      color: backgroundColor ?? colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: colorScheme.outline,
        ),
      ),
    );
  }

  /// 构建主题化占位符
  ///
  /// 用于需要自定义背景色或样式的场景
  static Widget buildPlaceholder({
    required BuildContext context,
    IconData icon = Icons.music_note,
    double? iconSize,
    Color? backgroundColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildIconPlaceholder(
      colorScheme: colorScheme,
      icon: icon,
      iconSize: iconSize ?? 24,
      backgroundColor: backgroundColor,
    );
  }

  static ImageProvider _localImageProvider(
    BuildContext context,
    File file, {
    double? width,
    double? height,
    required double targetDisplaySize,
  }) {
    final fileImage = FileImage(file);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheExtent = _cacheExtent(targetDisplaySize, devicePixelRatio);
    return ResizeImage(fileImage, width: cacheExtent, height: cacheExtent);
  }

  static int _cacheExtent(double logicalSize, double devicePixelRatio) {
    return (logicalSize * devicePixelRatio).round().clamp(1, 8192).toInt();
  }

  static String? _networkImageCacheKey(
    String url, {
    required int cacheExtent,
  }) {
    return 'fmp_s${cacheExtent}_$url';
  }

  /// 根据图片 URL 域名返回默认的 Referer/Origin 请求头
  ///
  /// Bilibili / YouTube / Netease 的图片 CDN 可能檢查 Referer，
  /// 預設帶上對應平台的 Referer 以避免請求被拒絕。
  static Map<String, String>? _defaultImageHeaders(String url) {
    return SourceHttpPolicy.imageHeadersForUrl(url);
  }
}

class _NetworkImageRequest {
  final List<String> urls;
  final int cacheExtent;
  final Map<String, String>? headers;

  const _NetworkImageRequest({
    required this.urls,
    required this.cacheExtent,
    required this.headers,
  });

  factory _NetworkImageRequest.from({
    required BuildContext context,
    required String networkUrl,
    required double targetDisplaySize,
    Map<String, String>? headers,
  }) {
    return _NetworkImageRequest(
      urls: ThumbnailUrlUtils.getOptimizedUrlCandidates(
        networkUrl,
        displaySize: targetDisplaySize,
      ),
      cacheExtent: ImageLoadingService._cacheExtent(
        targetDisplaySize,
        MediaQuery.devicePixelRatioOf(context),
      ),
      headers: headers ?? ImageLoadingService._defaultImageHeaders(networkUrl),
    );
  }

  String? cacheKey(String url) {
    return ImageLoadingService._networkImageCacheKey(
      url,
      cacheExtent: cacheExtent,
    );
  }
}

/// 带淡入效果的本地图片组件
class _FadeInImage extends StatefulWidget {
  final ImageProvider image;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final Duration fadeInDuration;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  const _FadeInImage({
    required this.image,
    required this.fit,
    this.width,
    this.height,
    required this.placeholder,
    required this.fadeInDuration,
    this.errorBuilder,
  });

  @override
  State<_FadeInImage> createState() => _FadeInImageState();
}

class _FadeInImageState extends State<_FadeInImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _isLoaded = false;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.fadeInDuration,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    // 预加载图片
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _FadeInImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.fadeInDuration != widget.fadeInDuration) {
      _stream?.removeListener(_listener!);
      _controller.duration = widget.fadeInDuration;
      _controller.reset();
      setState(() {
        _isLoaded = false;
        _error = null;
        _stackTrace = null;
      });
      _loadImage();
    }
  }

  void _loadImage() {
    final ImageStream stream = widget.image.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (mounted) {
          setState(() {
            _isLoaded = true;
          });
          // 如果是同步加載（從緩存），跳過動畫直接顯示
          if (synchronousCall) {
            _controller.value = 1.0;
          } else {
            _controller.forward();
          }
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (mounted) {
          setState(() {
            _error = error;
            _stackTrace = stackTrace;
          });
        }
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果有错误，使用 errorBuilder
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!, _stackTrace);
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 占位符
        if (!_isLoaded) widget.placeholder,
        // 图片（带淡入动画）
        if (_isLoaded)
          FadeTransition(
            opacity: _animation,
            child: Image(
              image: widget.image,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
            ),
          ),
      ],
    );
  }
}

/// 带缓存和淡入效果的网络图片组件
///
/// 使用 CachedNetworkImage 实现：
/// - 内存缓存（快速访问）
/// - 磁盘缓存（持久化存储）
/// - 淡入动画效果
/// - 限制内存缓存尺寸（减少内存占用）
///
/// 使用 StatefulWidget 确保 onImageLoaded() 只在首次加载时通知一次，
/// 避免 widget rebuild 时重复触发缓存大小估算和清理检查。
class _CachedNetworkImage extends StatefulWidget {
  final _NetworkImageRequest request;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final bool showLoadingIndicator;
  final Duration fadeInDuration;

  const _CachedNetworkImage({
    required this.request,
    required this.fit,
    this.width,
    this.height,
    required this.placeholder,
    required this.showLoadingIndicator,
    required this.fadeInDuration,
  });

  @override
  State<_CachedNetworkImage> createState() => _CachedNetworkImageState();
}

class _CachedNetworkImageState extends State<_CachedNetworkImage> {
  /// 是否已通知过 onImageLoaded，避免 rebuild 时重复触发
  bool _notified = false;
  bool _retryScheduled = false;
  int _urlIndex = 0;

  String get _currentUrl => widget.request.urls[_urlIndex];

  @override
  void didUpdateWidget(covariant _CachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL 候选变化时重置，允许新图片再次通知
    if (!_sameUrlList(oldWidget.request.urls, widget.request.urls)) {
      _notified = false;
      _retryScheduled = false;
      _urlIndex = 0;
    } else if (_urlIndex >= widget.request.urls.length) {
      _retryScheduled = false;
      _urlIndex = 0;
    }
  }

  bool _sameUrlList(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _advanceToNextUrl() {
    if (_urlIndex >= widget.request.urls.length - 1) return;
    setState(() {
      _urlIndex += 1;
      _notified = false;
      _retryScheduled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.request.urls.isEmpty) {
      return widget.placeholder;
    }

    return CachedNetworkImage(
      imageUrl: _currentUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      httpHeaders: widget.request.headers,
      cacheKey: widget.request.cacheKey(_currentUrl),
      cacheManager: NetworkImageCacheService.defaultCacheManager,
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: AnimationDurations.fastest,
      // 限制内存缓存中的图片尺寸，减少内存占用
      memCacheWidth: widget.request.cacheExtent,
      memCacheHeight: widget.request.cacheExtent,
      // 限制磁盘缓存中的图片尺寸，减少磁盘占用
      maxWidthDiskCache: widget.request.cacheExtent,
      maxHeightDiskCache: widget.request.cacheExtent,
      placeholder: (context, url) => widget.showLoadingIndicator
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.placeholder,
      errorWidget: (context, url, error) {
        if (_urlIndex < widget.request.urls.length - 1 && !_retryScheduled) {
          _retryScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _advanceToNextUrl();
            }
          });
        }
        return widget.placeholder;
      },
      imageBuilder: (context, imageProvider) {
        _retryScheduled = false;
        // 仅首次加载时通知缓存服务，避免 rebuild 时重复累加估算值
        if (!_notified) {
          _notified = true;
          NetworkImageCacheService.onImageLoaded();
        }
        return Image(
          image: imageProvider,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
        );
      },
    );
  }
}

/// 图片占位符样式
enum ImagePlaceholderStyle {
  /// 音乐封面（music_note 图标）
  track,

  /// 头像（person 图标）
  avatar,

  /// 文件夹（folder 图标）
  folder,

  /// 歌单（album 图标）
  playlist,
}

/// 图片占位符 Widget
///
/// 统一的占位符样式，用于图片加载失败或无图片时显示
class ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;

  const ImagePlaceholder({
    super.key,
    required this.icon,
    this.size,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  });

  /// 音乐封面占位符
  const ImagePlaceholder.track({
    super.key,
    this.size,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  }) : icon = Icons.music_note;

  /// 头像占位符
  const ImagePlaceholder.avatar({
    super.key,
    this.size,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  }) : icon = Icons.person;

  /// 文件夹占位符
  const ImagePlaceholder.folder({
    super.key,
    this.size,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  }) : icon = Icons.folder;

  /// 歌单占位符
  const ImagePlaceholder.playlist({
    super.key,
    this.size,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
  }) : icon = Icons.album;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 如果指定了固定大小，使用固定布局
    if (size != null) {
      final effectiveIconSize = iconSize ?? size! * 0.5;
      return Container(
        width: size,
        height: size,
        color: backgroundColor ?? colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            icon,
            size: effectiveIconSize,
            color: iconColor ?? colorScheme.outline,
          ),
        ),
      );
    }

    // 没有指定固定大小时，使用 LayoutBuilder 让图标根据容器大小自适应
    return LayoutBuilder(
      builder: (context, constraints) {
        // 取容器较小边的 40% 作为图标大小，最小 24，最大 64
        final containerSize = constraints.biggest.shortestSide;
        final effectiveIconSize = iconSize ??
            (containerSize.isFinite
                ? (containerSize * 0.4).clamp(24.0, 64.0)
                : 24.0);

        return Container(
          color: backgroundColor ?? colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              icon,
              size: effectiveIconSize,
              color: iconColor ?? colorScheme.outline,
            ),
          ),
        );
      },
    );
  }
}
