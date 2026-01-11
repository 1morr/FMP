import 'package:flutter/material.dart';

import '../../data/models/track.dart';
import '../extensions/track_extensions.dart';
import 'local_image_cache.dart';

/// 默认淡入动画时长
const _kDefaultFadeInDuration = Duration(milliseconds: 150);

/// 统一的图片加载服务
///
/// 功能：
/// - 统一的图片加载优先级：本地 → 网络 → 占位符
/// - 集成 LocalImageCache 用于本地图片缓存
/// - 提供统一的占位符和错误处理
/// - 图片加载完成后有淡入效果
class ImageLoadingService {
  ImageLoadingService._();

  /// 加载图片 Widget
  ///
  /// 按照以下优先级加载：
  /// 1. 本地图片（如果提供了 localPath 且文件存在）
  /// 2. 网络图片（如果提供了 networkUrl）
  /// 3. 占位符
  ///
  /// [localPath] 本地文件路径
  /// [networkUrl] 网络图片 URL
  /// [placeholder] 自定义占位符 Widget
  /// [fit] 图片填充模式
  /// [width] 宽度
  /// [height] 高度
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
    Map<String, String>? headers,
    bool showLoadingIndicator = false,
    Duration fadeInDuration = _kDefaultFadeInDuration,
  }) {
    // 1. 尝试加载本地图片
    if (localPath != null) {
      final imageProvider = LocalImageCache.getLocalImage(localPath);
      if (imageProvider != null) {
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
              headers: headers,
              showLoadingIndicator: showLoadingIndicator,
              fadeInDuration: fadeInDuration,
            );
          },
        );
      }
    }

    // 2. 尝试加载网络图片或显示占位符
    return _loadNetworkOrPlaceholder(
      networkUrl: networkUrl,
      placeholder: placeholder,
      fit: fit,
      width: width,
      height: height,
      headers: headers,
      showLoadingIndicator: showLoadingIndicator,
      fadeInDuration: fadeInDuration,
    );
  }

  /// 加载网络图片或显示占位符
  static Widget _loadNetworkOrPlaceholder({
    String? networkUrl,
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Map<String, String>? headers,
    bool showLoadingIndicator = false,
    Duration fadeInDuration = _kDefaultFadeInDuration,
  }) {
    if (networkUrl != null && networkUrl.isNotEmpty) {
      return _FadeInNetworkImage(
        url: networkUrl,
        fit: fit,
        width: width,
        height: height,
        headers: headers,
        placeholder: placeholder,
        showLoadingIndicator: showLoadingIndicator,
        fadeInDuration: fadeInDuration,
      );
    }

    return placeholder;
  }

  /// 加载歌曲封面
  ///
  /// 专门用于 Track 的封面图片加载，自动处理本地/网络优先级
  ///
  /// [track] 歌曲数据
  /// [size] 图片尺寸（正方形）
  /// [borderRadius] 圆角半径
  /// [placeholderIcon] 占位符图标
  /// [placeholderIconSize] 占位符图标大小（默认为 size 的一半）
  static Widget loadTrackCover(
    Track track, {
    double? size,
    double borderRadius = 4,
    IconData placeholderIcon = Icons.music_note,
    double? placeholderIconSize,
  }) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        final placeholder = _buildIconPlaceholder(
          colorScheme: colorScheme,
          icon: placeholderIcon,
          iconSize: placeholderIconSize ?? (size != null ? size * 0.5 : 24),
        );

        return loadImage(
          localPath: track.localCoverPath,
          networkUrl: track.thumbnailUrl,
          placeholder: placeholder,
          fit: BoxFit.cover,
          width: size,
          height: size,
        );
      },
    );
  }

  /// 加载头像图片
  ///
  /// 专门用于 UP主/艺术家头像
  ///
  /// [localPath] 本地头像路径
  /// [networkUrl] 网络头像 URL
  /// [size] 头像尺寸（直径）
  static Widget loadAvatar({
    String? localPath,
    String? networkUrl,
    double size = 40,
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

  void _loadImage() {
    final ImageStream stream = widget.image.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (mounted) {
          setState(() {
            _isLoaded = true;
          });
          _controller.forward();
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
    ));
  }

  @override
  void dispose() {
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

/// 带淡入效果的网络图片组件
class _FadeInNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Map<String, String>? headers;
  final Widget placeholder;
  final bool showLoadingIndicator;
  final Duration fadeInDuration;

  const _FadeInNetworkImage({
    required this.url,
    required this.fit,
    this.width,
    this.height,
    this.headers,
    required this.placeholder,
    required this.showLoadingIndicator,
    required this.fadeInDuration,
  });

  @override
  State<_FadeInNetworkImage> createState() => _FadeInNetworkImageState();
}

class _FadeInNetworkImageState extends State<_FadeInNetworkImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isLoaded = false;
  bool _hasError = false;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onImageLoaded() {
    if (!_isLoaded && mounted) {
      setState(() {
        _isLoaded = true;
      });
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.placeholder;
    }

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 占位符或加载指示器
        if (!_isLoaded)
          widget.showLoadingIndicator
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : widget.placeholder,
        // 图片
        Opacity(
          opacity: _isLoaded ? 1.0 : 0.0,
          child: FadeTransition(
            opacity: _animation,
            child: Image.network(
              widget.url,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
              headers: widget.headers,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  // 图片帧加载完成
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _onImageLoaded();
                  });
                }
                return child;
              },
              errorBuilder: (context, error, stackTrace) {
                if (mounted && !_hasError) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _hasError = true;
                      });
                    }
                  });
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ],
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
    final effectiveIconSize = iconSize ?? (size != null ? size! * 0.5 : 24);

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
}
