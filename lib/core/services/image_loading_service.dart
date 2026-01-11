import 'package:flutter/material.dart';

import '../../data/models/track.dart';
import '../extensions/track_extensions.dart';
import 'local_image_cache.dart';

/// 统一的图片加载服务
///
/// 功能：
/// - 统一的图片加载优先级：本地 → 网络 → 占位符
/// - 集成 LocalImageCache 用于本地图片缓存
/// - 提供统一的占位符和错误处理
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
  static Widget loadImage({
    String? localPath,
    String? networkUrl,
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    Map<String, String>? headers,
    bool showLoadingIndicator = false,
  }) {
    // 1. 尝试加载本地图片
    if (localPath != null) {
      final imageProvider = LocalImageCache.getLocalImage(localPath);
      if (imageProvider != null) {
        return Image(
          image: imageProvider,
          fit: fit,
          width: width,
          height: height,
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
  }) {
    if (networkUrl != null && networkUrl.isNotEmpty) {
      return Image.network(
        networkUrl,
        fit: fit,
        width: width,
        height: height,
        headers: headers,
        loadingBuilder: showLoadingIndicator
            ? (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              }
            : null,
        errorBuilder: (context, error, stackTrace) => placeholder,
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
