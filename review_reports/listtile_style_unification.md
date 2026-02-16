# ListTile vs InkWell 样式对比分析

## 当前差异

### ListTile (playlist_detail_page.dart)
```dart
ListTile(
  leading: TrackThumbnail(size: 48),
  title: Text(...),
  subtitle: Text(...),
  trailing: PopupMenuButton(...),
)
```

**默认样式**：
- **垂直内边距**: 8dp (dense: false) 或 4dp (dense: true)
- **水平内边距**: 16dp
- **最小高度**: 56dp (dense: false) 或 48dp (dense: true)
- **leading 宽度**: 56dp (包含右侧 16dp 间距)
- **title 字体**: bodyLarge (16sp)
- **subtitle 字体**: bodyMedium (14sp)
- **title-subtitle 间距**: 2dp

### InkWell (explore_page.dart - 修改后)
```dart
InkWell(
  child: Padding(
    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(
      children: [
        SizedBox(width: 28, child: Text(rank)),
        SizedBox(width: 12),
        TrackThumbnail(size: 48),
        SizedBox(width: 12),
        Expanded(child: Column(...)),
        PopupMenuButton(...),
      ],
    ),
  ),
)
```

**当前样式**：
- **垂直内边距**: 6dp ❌ (ListTile 是 8dp)
- **水平内边距**: 16dp ✅
- **排名宽度**: 28dp + 12dp 间距
- **封面大小**: 48dp ✅
- **封面间距**: 12dp ❌ (ListTile leading 右侧是 16dp)
- **title 字体**: bodyMedium (14sp) ❌ (ListTile 是 bodyLarge 16sp)
- **subtitle 字体**: bodySmall (12sp) ❌ (ListTile 是 bodyMedium 14sp)
- **title-subtitle 间距**: 2dp ✅

## 问题总结

| 属性 | ListTile | InkWell (当前) | 差异 |
|------|----------|----------------|------|
| 垂直内边距 | 8dp | 6dp | ❌ 不一致 |
| 封面右侧间距 | 16dp | 12dp | ❌ 不一致 |
| title 字体 | bodyLarge (16sp) | bodyMedium (14sp) | ❌ 不一致 |
| subtitle 字体 | bodyMedium (14sp) | bodySmall (12sp) | ❌ 不一致 |
| 最小高度 | 56dp | 自动 | ❌ 可能不一致 |

## 解决方案

### 方案 1: 手动匹配 ListTile 样式（推荐）

修改 InkWell 的样式参数，使其与 ListTile 完全一致：

```dart
InkWell(
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),  // ← 改为 8dp
    child: Row(
      children: [
        // 排名
        SizedBox(
          width: 28,
          child: Text(
            '$rank',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ),
        const SizedBox(width: 16),  // ← 改为 16dp，与 ListTile leading 间距一致

        // 缩略图
        TrackThumbnail(
          track: track,
          size: 48,
          borderRadius: 4,
          isPlaying: isPlaying,
        ),
        const SizedBox(width: 16),  // ← 改为 16dp

        // 歌曲信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(  // ← 改为 bodyLarge
                      color: isPlaying ? colorScheme.primary : null,
                      fontWeight: isPlaying ? FontWeight.w600 : null,
                    ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      track.artist ?? t.general.unknownArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(  // ← 改为 bodyMedium
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  // ... 其他内容
                ],
              ),
            ],
          ),
        ),

        // 菜单按钮
        PopupMenuButton(...),
      ],
    ),
  ),
)
```

### 方案 2: 创建统一的 TrackTile 组件（最佳实践）

创建一个可复用的组件，封装 ListTile 的样式规范：

```dart
// lib/ui/widgets/track_tile.dart

/// 统一的歌曲列表项组件
///
/// 支持两种模式：
/// - 标准模式：封面 + 信息（使用 ListTile）
/// - 排名模式：排名 + 封面 + 信息（使用 InkWell，样式匹配 ListTile）
class TrackTile extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final int? rank;  // 如果提供排名，使用 InkWell 布局
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? subtitle;

  const TrackTile({
    super.key,
    required this.track,
    this.isPlaying = false,
    this.rank,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (rank != null) {
      // 排名模式：使用 InkWell，样式匹配 ListTile
      return _buildRankingTile(context);
    } else {
      // 标准模式：使用 ListTile
      return _buildStandardTile(context);
    }
  }

  Widget _buildStandardTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: TrackThumbnail(
        track: track,
        size: 48,
        isPlaying: isPlaying,
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlaying ? colorScheme.primary : null,
          fontWeight: isPlaying ? FontWeight.w600 : null,
        ),
      ),
      subtitle: subtitle ?? Text(
        track.artist ?? t.general.unknownArtist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }

  Widget _buildRankingTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        // 匹配 ListTile 的内边距
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            // 排名（宽度 28dp，与 ListTile leading 的 40dp 相比更紧凑）
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ),
            // 匹配 ListTile leading 的右侧间距
            const SizedBox(width: 16),

            // 封面
            TrackThumbnail(
              track: track,
              size: 48,
              borderRadius: 4,
              isPlaying: isPlaying,
            ),
            // 匹配 ListTile leading 的右侧间距
            const SizedBox(width: 16),

            // 歌曲信息（匹配 ListTile 的 title + subtitle）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title - 使用 bodyLarge 匹配 ListTile
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                          color: isPlaying ? colorScheme.primary : null,
                          fontWeight: isPlaying ? FontWeight.w600 : null,
                        ),
                  ),
                  // 匹配 ListTile title-subtitle 间距
                  const SizedBox(height: 2),
                  // Subtitle - 使用 bodyMedium 匹配 ListTile
                  subtitle ?? Text(
                    track.artist ?? t.general.unknownArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),

            // Trailing
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
```

### 使用示例

```dart
// Explore Page - 带排名
TrackTile(
  track: track,
  rank: rank,
  isPlaying: isPlaying,
  onTap: () => controller.playTemporary(track),
  trailing: PopupMenuButton(...),
)

// Playlist Detail Page - 标准模式
TrackTile(
  track: track,
  isPlaying: isPlaying,
  onTap: () => controller.playAt(index),
  trailing: PopupMenuButton(...),
)
```

## 推荐方案

我推荐 **方案 2（创建统一组件）**，原因：

1. **一致性保证**：所有页面使用同一个组件，样式自动统一
2. **易于维护**：修改样式只需改一个地方
3. **代码复用**：减少重复代码
4. **类型安全**：统一的 API，减少错误

## 实施步骤

1. 创建 `lib/ui/widgets/track_tile.dart`
2. 实现 `TrackTile` 组件（上面的代码）
3. 逐步替换各页面的实现：
   - `explore_page.dart` - `_ExploreTrackTile` → `TrackTile(rank: ...)`
   - `home_page.dart` - `_RankingTrackTile` → `TrackTile(rank: ...)`
   - `playlist_detail_page.dart` - `_TrackListTile` → `TrackTile()`
   - `search_page.dart` - 各种 TrackTile → `TrackTile()`
4. 删除旧的自定义 TrackTile 实现

## 样式参数对照表

| 参数 | ListTile 默认值 | 推荐值 |
|------|----------------|--------|
| 垂直内边距 | 8dp | 8dp |
| 水平内边距 | 16dp | 16dp |
| leading 右侧间距 | 16dp | 16dp |
| title 字体 | bodyLarge (16sp) | bodyLarge |
| subtitle 字体 | bodyMedium (14sp) | bodyMedium |
| title-subtitle 间距 | 2dp | 2dp |
| 最小高度 | 56dp | 自动（约 64dp） |

注意：排名模式的总高度会略高于标准 ListTile（因为有排名数字），这是正常的。
