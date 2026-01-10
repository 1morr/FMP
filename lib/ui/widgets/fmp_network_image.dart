import 'package:flutter/material.dart';

/// FMP 网络图片组件
///
/// 直接使用 Image.network 加载网络图片，无缓存
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
    return Image.network(
      imageUrl,
      fit: fit,
      width: width,
      height: height,
      color: color,
      colorBlendMode: colorBlendMode,
      alignment: alignment,
      filterQuality: filterQuality,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        if (placeholder != null) {
          return placeholder!(context, imageUrl);
        }
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        if (errorWidget != null) {
          return errorWidget!(context, imageUrl, error);
        }
        return const Icon(Icons.music_note, color: Colors.grey);
      },
    );
  }
}
