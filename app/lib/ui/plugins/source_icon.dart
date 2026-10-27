import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 音源名稱的縮寫（沒有圖示時代替圖示）：多個字（以空白、`-`、`_` 分）取前兩個字的第一個字母，
/// 一個字取前兩個字元；英文轉大寫。空字串是 `?`。
String sourceAbbreviation(String name) {
  final words = name
      .split(RegExp(r'[\s\-_]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final chars = words.length > 1
      ? [words[0].runes.first, words[1].runes.first]
      : words[0].runes.take(2).toList();
  return String.fromCharCodes(chars).toUpperCase();
}

/// 音源的小圖示（ADR 0035，R7.5、R7.10）：插件 manifest 的 `icon`（`https` 網址經那個插件的媒體
/// client 讀，`data:` 網址直接解碼）；沒有、讀不到或不是點陣圖時是名稱的縮寫
/// （[sourceAbbreviation]）。插件已移除或停用時，名稱退回 [pluginId] 本身。
///
/// 語意名稱是音源名稱；圖示本身是裝飾。
class SourceIcon extends ConsumerWidget {
  const SourceIcon({
    super.key,
    required this.pluginId,
    required this.size,
    this.semanticLabel,
  });

  final String pluginId;

  /// 邊長（dp）。
  final double size;

  /// 語意名稱；預設是音源名稱。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AppTokens.of(context);
    final manifest = ref
        .watch(pluginRegistryProvider)
        .value?[pluginId]
        ?.manifest;
    // 停用或未安裝的音源沒有名稱可用（`pluginNameProvider` 給的是原因），縮寫用插件 id。
    final unavailable = ref.watch(sourceUnavailableProvider(pluginId)) != null;
    final name = unavailable
        ? pluginId
        : ref.watch(pluginNameProvider(pluginId)) ?? pluginId;
    final label = sourceAbbreviation(name);
    final abbreviation = ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.x1 / 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
    final icon = manifest?.icon;
    final Widget image;
    if (icon == null) {
      image = abbreviation;
    } else if (icon.isScheme('data')) {
      final bytes = icon.data?.contentAsBytes();
      image = bytes == null
          ? abbreviation
          : Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => abbreviation,
            );
    } else {
      image = ArtworkImage(
        pluginId: pluginId,
        artwork: [TrackArtwork(url: icon)],
        size: size,
        rounded: false,
        fallback: abbreviation,
      );
    }
    return Semantics(
      label: semanticLabel ?? name,
      image: true,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius.small),
        child: SizedBox.square(dimension: size, child: image),
      ),
    );
  }
}
