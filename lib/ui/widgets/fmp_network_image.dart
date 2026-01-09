import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/cache/fmp_cache_manager.dart';

/// FMP 网络图片组件
///
/// 封装 CachedNetworkImage，使用自定义的缓存管理器
class FmpNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;

  const FmpNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.color,
    this.colorBlendMode,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.fadeInDuration = const Duration(milliseconds: 150),
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: FmpCacheManager.instance,
      fadeInDuration: fadeInDuration,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder,
      errorWidget: errorWidget,
      color: color,
      colorBlendMode: colorBlendMode,
      alignment: alignment,
      filterQuality: filterQuality,
    );
  }
}
