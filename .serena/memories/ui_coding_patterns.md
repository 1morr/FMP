# FMP UI 编码模式与规范

本文档定义了 FMP 项目中 UI 页面开发的统一编码模式，确保各页面逻辑一致性。

---

## 1. 页面结构模式

### 1.1 基础页面模板

```dart
class XXXPage extends ConsumerStatefulWidget {
  const XXXPage({super.key});
  
  @override
  ConsumerState<XXXPage> createState() => _XXXPageState();
}

class _XXXPageState extends ConsumerState<XXXPage> {
  // 1. 控制器（如需要）
  final _scrollController = ScrollController();
  
  // 2. 本地状态（用于防闪烁等）
  List<Track>? _cachedData;
  
  @override
  void initState() {
    super.initState();
    // 初始化逻辑
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // watch providers...
    
    return Scaffold(
      appBar: AppBar(...),
      body: _buildBody(context),
    );
  }
}
```

### 1.2 简单页面（无本地状态）

使用 `ConsumerWidget` 而非 `ConsumerStatefulWidget`：

```dart
class SimplePage extends ConsumerWidget {
  const SimplePage({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // ...
  }
}
```

---

## 2. 图片加载模式

### 2.1 歌曲封面图片

**始终使用 `TrackThumbnail` 组件**，不要直接使用 `Image.network` 或 `Image.file`：

```dart
// ✅ 正确
TrackThumbnail(
  track: track,
  size: 48,
  borderRadius: 4,
  isPlaying: isPlaying,
)

// ❌ 错误
Image.network(track.thumbnailUrl!)
Image.file(File(track.localCoverPath!))
```

### 2.2 大尺寸封面

使用 `TrackCover` 组件：

```dart
TrackCover(
  track: track,
  aspectRatio: 16 / 9,
  borderRadius: 16,
  showLoadingIndicator: true,
  highResolution: false, // 背景图片设为 true
)
```

### 2.3 头像图片

使用 `ImageLoadingService.loadAvatar()`：

```dart
// 在 build 中获取缓存和 baseDir
ref.watch(fileExistsCacheProvider);
final cache = ref.read(fileExistsCacheProvider.notifier);
final baseDir = ref.watch(downloadBaseDirProvider).valueOrNull;

ImageLoadingService.loadAvatar(
  localPath: track?.getLocalAvatarPath(cache, baseDir: baseDir),
  networkUrl: avatarUrl,
  size: 32,
)
```

### 2.4 其他图片

使用 `ImageLoadingService.loadImage()`：

```dart
ImageLoadingService.loadImage(
  localPath: localPath,
  networkUrl: networkUrl,
  placeholder: ImagePlaceholder.track(),
  fit: BoxFit.cover,
  width: 100,
  height: 100,
)
```

### 2.5 FileExistsCache 使用模式

在需要检查本地文件存在性的 Widget 中：

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  // 1. Watch 缓存以响应变化
  ref.watch(fileExistsCacheProvider);
  // 2. 获取缓存实例用于读取
  final cache = ref.read(fileExistsCacheProvider.notifier);
  
  // 3. 使用缓存方法
  final localCoverPath = track.getLocalCoverPath(cache);
  final isDownloaded = cache.hasAnyDownload(track);
  
  // ...
}
```

**进入页面时预加载缓存**（用于列表页面）：

```dart
void initState() {
  super.initState();
  // 异步预加载缓存
  Future.microtask(() async {
    final cache = ref.read(fileExistsCacheProvider.notifier);
    await cache.refreshCache(tracks);
  });
}
```

---

## 3. 列表刷新模式

### 3.1 下拉刷新

使用 `RefreshIndicator`：

```dart
RefreshIndicator(
  onRefresh: () async {
    // 执行刷新逻辑
    await ref.read(someProvider.notifier).refresh();
  },
  child: ListView.builder(
    padding: const EdgeInsets.only(bottom: 100), // 为迷你播放器留空间
    itemCount: items.length,
    itemBuilder: (context, index) => _buildItem(items[index]),
  ),
)
```

### 3.2 StreamProvider/FutureProvider 刷新

使用 `ref.invalidate()` 或 `ref.refresh()`：

```dart
// 强制重新获取数据
await ref.refresh(dataProvider.future);

// 或使用 invalidate（让 provider 在下次读取时重新计算）
ref.invalidate(dataProvider);
```

### 3.3 缓存数据刷新（如排行榜）

```dart
// 通过 cache service 刷新
ref.read(rankingCacheServiceProvider).refresh();
```

---

## 4. 歌曲列表项模式

### 4.1 基本歌曲项组件

所有歌曲列表项应遵循相同的结构：

```dart
class _TrackTile extends ConsumerWidget {
  final Track track;
  final int? rank;          // 可选：排名
  final VoidCallback? onTap;
  final bool isPartOfGroup; // 是否属于多P分组
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;
    
    return ListTile(
      leading: _buildLeading(colorScheme, isPlaying),
      title: _buildTitle(colorScheme, isPlaying),
      subtitle: _buildSubtitle(colorScheme),
      trailing: _buildTrailing(context, ref),
      onTap: onTap ?? () => _playTrack(ref),
    );
  }
}
```

### 4.2 判断当前播放状态

**统一比较逻辑**：

```dart
final currentTrack = ref.watch(currentTrackProvider);

// 标准比较（有数据库 ID）
final isPlaying = currentTrack != null &&
    currentTrack.sourceId == track.sourceId &&
    currentTrack.pageNum == track.pageNum;

// 本地文件比较（无数据库 ID，如已下载分类页）
final isPlaying = currentTrack?.downloadedPath == track.downloadedPath;
```

### 4.3 菜单操作统一处理

```dart
void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
  final controller = ref.read(audioControllerProvider.notifier);
  
  switch (action) {
    case 'play':
      controller.playTemporary(track);
      break;
    case 'play_next':
      controller.addNext(track);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加到下一首')),
      );
      break;
    case 'add_to_queue':
      controller.addToQueue(track);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加到隊列')),
      );
      break;
    case 'add_to_playlist':
      _showAddToPlaylistDialog(context, ref, track);
      break;
    case 'download':
      _startDownload(context, ref, track);
      break;
  }
}
```

### 4.4 临时播放 vs 直接播放

- **搜索/排行榜/探索**：使用 `controller.playTemporary(track)` - 临时播放，不影响队列
- **歌单/队列**：使用 `controller.playTrackInQueue(index)` - 播放队列中的歌曲

---

## 5. 多P分组模式

### 5.1 使用 TrackGroup 工具

```dart
import '../../widgets/track_group/track_group.dart';

// 获取分组
final groups = groupTracks(tracks);

// 构建列表
ListView.builder(
  itemCount: groups.length,
  itemBuilder: (context, index) {
    final group = groups[index];
    if (group.hasMultipleParts) {
      return _GroupHeader(group: group, ...);
    } else {
      return _TrackTile(track: group.firstTrack, ...);
    }
  },
)
```

### 5.2 分组展开/折叠

```dart
// 状态管理
final Set<String> _expandedGroups = {};

void _toggleGroup(String groupKey) {
  setState(() {
    if (_expandedGroups.contains(groupKey)) {
      _expandedGroups.remove(groupKey);
    } else {
      _expandedGroups.add(groupKey);
    }
  });
}
```

---

## 6. 错误处理模式

### 6.1 AsyncValue 处理

```dart
final dataAsync = ref.watch(someAsyncProvider);

return dataAsync.when(
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (error, stack) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('加載失敗: $error'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => ref.invalidate(someAsyncProvider),
          child: const Text('重試'),
        ),
      ],
    ),
  ),
  data: (data) => _buildContent(data),
);
```

### 6.2 空状态处理

```dart
if (items.isEmpty) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.music_off, size: 64, color: colorScheme.outline),
        const SizedBox(height: 16),
        Text('暫無數據', style: TextStyle(color: colorScheme.outline)),
        if (canRefresh) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _refresh,
            child: const Text('刷新'),
          ),
        ],
      ],
    ),
  );
}
```

---

## 7. 可复用组件清单

| 组件 | 位置 | 用途 |
|------|------|------|
| `TrackThumbnail` | `widgets/track_thumbnail.dart` | 歌曲封面缩略图 |
| `TrackCover` | `widgets/track_thumbnail.dart` | 大尺寸封面 |
| `NowPlayingIndicator` | `widgets/now_playing_indicator.dart` | 播放中动画指示器 |
| `ImagePlaceholder` | `services/image_loading_service.dart` | 图片占位符 |
| `TrackGroup` / `groupTracks()` | `widgets/track_group/track_group.dart` | 多P分组工具 |
| `RefreshProgressIndicator` | `widgets/refresh_progress_indicator.dart` | 刷新进度指示器 |
| `ErrorDisplay` | `widgets/error_display.dart` | 错误展示组件 |

---

## 8. Provider 使用模式

### 8.1 常用 Provider

```dart
// 播放器状态
final playerState = ref.watch(audioControllerProvider);
final controller = ref.read(audioControllerProvider.notifier);

// 当前歌曲
final currentTrack = ref.watch(currentTrackProvider);

// 文件缓存
ref.watch(fileExistsCacheProvider);
final cache = ref.read(fileExistsCacheProvider.notifier);

// 下载基础目录
final baseDir = ref.watch(downloadBaseDirProvider).valueOrNull;
```

### 8.2 避免在 build 中调用 notifier 方法

```dart
// ✅ 正确：在事件处理中调用
onTap: () => ref.read(provider.notifier).doSomething()

// ❌ 错误：在 build 中直接调用
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.read(provider.notifier).doSomething(); // 不要这样做！
}
```

---

## 9. 页面间代码统一检查清单

创建或修改页面时，请检查：

- [ ] 图片加载是否使用 `TrackThumbnail` / `TrackCover` / `ImageLoadingService`
- [ ] 是否正确使用 `FileExistsCache`（watch + read 模式）
- [ ] 播放状态判断是否使用统一的比较逻辑
- [ ] 菜单操作是否与其他页面一致
- [ ] 错误状态和空状态处理是否符合规范
- [ ] 列表是否留出底部 padding（迷你播放器）
- [ ] 是否使用了相似页面的现有组件和模式

---

## 10. 相似页面对照表

| 页面 | 相似页面 | 应统一的模式 |
|------|---------|-------------|
| ExplorePage | HomePage (排行榜部分) | TrackTile 样式、菜单操作 |
| PlaylistDetailPage | DownloadedCategoryPage | 多P分组、操作按钮 |
| SearchPage | - | 搜索结果项与排行榜项应风格统一 |
| LibraryPage | DownloadedPage | 卡片网格、长按菜单 |

