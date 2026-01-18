# FMP 图片处理逻辑文档

## 概述

FMP 使用三层优先级的图片加载策略：
1. **本地图片**（已下载歌曲）
2. **网络图片**（在线歌曲）
3. **占位符**（无图片时）

---

## 核心组件

### 0. ImageLoadingService（统一图片加载服务）✅ Phase 1 新增

**文件位置**：`lib/core/services/image_loading_service.dart`

**功能**：
- 统一的图片加载优先级：本地 → 网络 → 占位符
- 集成 LocalImageCache 用于本地图片 LRU 缓存
- 提供统一的占位符和错误处理
- 图片加载完成后有淡入效果（默认 150ms）

**使用方式**：
```dart
// 通用图片加载
ImageLoadingService.loadImage(
  localPath: track.localCoverPath,
  networkUrl: track.thumbnailUrl,
  placeholder: placeholder,
  fit: BoxFit.cover,
  fadeInDuration: Duration(milliseconds: 150), // 可选，默认 150ms
);

// 专用方法
ImageLoadingService.loadTrackCover(track, size: 48);
ImageLoadingService.loadAvatar(localPath: path, networkUrl: url);
```

**内部组件**：
- `_FadeInImage` - 本地图片淡入组件
- `_FadeInNetworkImage` - 网络图片淡入组件

### 0.1. FileExistsCache（文件存在检查缓存）✅ 已重构

**文件位置**：`lib/providers/download/file_exists_cache.dart`

**功能**：
- 缓存文件是否存在的检测结果，避免在 UI build 期间执行同步 IO
- 支持通用路径检查和 Track 专用方法
- 未缓存路径会安排异步刷新，刷新完成后触发 UI 重建

**使用方式**：
```dart
// 在 ConsumerWidget 中
ref.watch(fileExistsCacheProvider); // 监听变化
final cache = ref.read(fileExistsCacheProvider.notifier);

// 通用方法
cache.exists(path);                    // 检查单个路径
cache.getFirstExisting(paths);         // 批量检查，返回第一个存在的

// Track 专用方法
cache.isDownloadedForPlaylist(track, playlistId);
cache.hasAnyDownload(track);
cache.getFirstExistingPath(track);

// 预加载缓存（进入页面时调用）
await cache.refreshCache(tracks);
await cache.preloadPaths(paths);
```

**注意**：原 `LocalImageCache` 已移除，本地图片直接使用 `FileImage`（Flutter 内置缓存）

### 0.2. NetworkImageCacheService（网络图片缓存）✅ 新增

**文件位置**：`lib/core/services/network_image_cache_service.dart`

**功能**：
- 使用 `cached_network_image` + `flutter_cache_manager` 实现
- 内存缓存（快速访问）+ 磁盘缓存（持久化）
- 缓存有效期：7 天
- 最大缓存文件数：500 个
- 用户可在设置中配置缓存大小

**使用方式**：
```dart
// 获取缓存管理器
NetworkImageCacheService.defaultCacheManager;
NetworkImageCacheService.getCacheManager(maxSizeMB: 500);

// 清除缓存
await NetworkImageCacheService.clearCache();
await NetworkImageCacheService.removeFile(url);
```

**ImageLoadingService 集成**：
网络图片自动使用 `CachedNetworkImage`，无需手动配置：
```dart
ImageLoadingService.loadImage(
  localPath: track.localCoverPath,
  networkUrl: track.thumbnailUrl,  // 自动缓存
  placeholder: placeholder,
);
```

**设置页面**：
- 图片缓存大小：100MB / 200MB / 500MB / 1GB / 2GB
- 清除图片缓存：一键清除所有网络图片缓存

### 1. TrackThumbnail（歌曲缩略图）

**文件位置**：`lib/ui/widgets/track_thumbnail.dart`

**使用场景**：歌曲列表、播放器迷你封面、队列项等

**尺寸**：通常 40-56px

**加载优先级**（使用 FileExistsCache 避免同步 IO）：
```dart
// TrackThumbnail 现在是 ConsumerWidget
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.watch(fileExistsCacheProvider); // 监听缓存变化
  final cache = ref.read(fileExistsCacheProvider.notifier);
  // ...
}

Widget _buildImage(ColorScheme colorScheme, FileExistsCache cache) {
  final placeholder = _buildPlaceholder(colorScheme);
  
  // 使用 FileExistsCache 获取本地封面路径（避免同步 IO）
  return ImageLoadingService.loadImage(
    localPath: track.getLocalCoverPath(cache),
    networkUrl: track.thumbnailUrl,
    placeholder: placeholder,
    fit: BoxFit.cover,
    width: size,
    height: size,
  );
}
```

**占位符样式**：
- 背景色：`colorScheme.surfaceContainerHighest`
- 图标：`Icons.music_note`，大小为 `size * 0.5`

**播放中覆盖层**：
- 条件：`showPlayingIndicator && isPlaying`
- 样式：主题色半透明背景 + NowPlayingIndicator 动画

---

### 2. TrackCover（大尺寸封面）

**文件位置**：`lib/ui/widgets/track_thumbnail.dart`

**使用场景**：播放器页面、歌单详情头部、歌曲详情面板

**尺寸**：通常 16:9 或 1:1 宽高比

**加载优先级**（与 TrackThumbnail 相同）：
```dart
Widget _buildImage(ColorScheme colorScheme) {
  // 1. 本地封面
  final localPath = track?.localCoverPath;
  if (localPath != null) {
    return Image.file(File(localPath), fit: BoxFit.cover);
  }

  // 2. 网络封面（优先使用传入的 networkUrl）
  final url = networkUrl ?? track?.thumbnailUrl;
  if (url != null && url.isNotEmpty) {
    return Image.network(url, fit: BoxFit.cover);
  }

  // 3. 占位符
  return _buildPlaceholder(colorScheme);
}
```

**加载指示器**：
- 可选（`showLoadingIndicator` 参数）
- 使用 `Image.network` 的 `loadingBuilder`

---

### 3. 本地路径扩展方法

#### TrackExtensions

**文件位置**：`lib/core/extensions/track_extensions.dart`

```dart
extension TrackExtensions on Track {
  // ===== 同步方法（仅用于非 build 上下文，如音频播放）=====
  /// 获取本地音频路径（同步 IO）
  String? get localAudioPath;

  // ===== 缓存方法（用于 UI 组件）=====
  /// 获取本地封面路径（使用缓存，避免同步 IO）
  String? getLocalCoverPath(FileExistsCache cache);
  
  /// 獲取本地頭像路徑（使用集中式頭像文件夾）
  /// 需要傳入 baseDir（從 downloadBaseDirProvider 獲取）
  String? getLocalAvatarPath(FileExistsCache cache, {String? baseDir});

  // ===== 辅助属性 =====
  bool get hasLocalAudio => localAudioPath != null;
  bool get isDownloaded => hasLocalAudio;
  bool get hasNetworkCover => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;
}
```

**Track 模型新增字段**：
```dart
int? ownerId;      // Bilibili UP主 ID（用於頭像查找）
String? channelId; // YouTube 頻道 ID（用於頭像查找）
```

**使用场景**：
- **封面**：`getLocalCoverPath(cache)` - 從視頻文件夾讀取
- **頭像**：`getLocalAvatarPath(cache, baseDir: baseDir)` - 從集中式文件夾讀取
- **音频播放**：使用 `localAudioPath`（同步方法，在非 build 上下文中调用）

#### PlaylistExtensions

**文件位置**：`lib/core/extensions/playlist_extensions.dart`

```dart
extension PlaylistExtensions on Playlist {
  /// 获取本地封面路径（检查 coverLocalPath 是否实际存在）
  String? get localCoverPath;

  bool get hasLocalCover => localCoverPath != null;
  bool get hasNetworkCover => coverUrl != null && coverUrl!.isNotEmpty;
  bool get hasCover => hasLocalCover || hasNetworkCover;
}
```
```

**目录结构**：
```
下载目录/
├── avatars/                       # 集中式头像文件夾（避免重複下載）
│   ├── bilibili/
│   │   └── {ownerId}.jpg          # 例如 546195.jpg
│   └── youtube/
│       └── {channelId}.jpg        # 例如 UCq-Fj5jknLsUf-MWSy4_brA.jpg
├── 歌单名/
│   ├── playlist_cover.jpg         # 歌单封面
│   ├── {sourceId}_{视频标题}/
│   │   ├── audio.m4a              # 音频文件
│   │   ├── cover.jpg              # 视频封面
│   │   └── metadata.json          # 元数据（包含 ownerId/channelId）
```

**頭像去重機制**：
- 同一創作者的頭像只下載一次
- Bilibili 使用 `ownerId` (UP主 mid)
- YouTube 使用 `channelId` (頻道 ID)
- 每次下載會覆蓋已有頭像（獲取最新頭像）

---

## 各页面的图片处理

### 1. 歌单卡片（LibraryPage）✅ 已更新使用 ImageLoadingService

```dart
final coverAsync = ref.watch(playlistCoverProvider(playlist.id));

coverAsync.when(
  data: (coverData) => coverData.hasCover
      ? ImageLoadingService.loadImage(
          localPath: coverData.localPath,
          networkUrl: coverData.networkUrl,
          placeholder: _buildPlaceholder(colorScheme),
          fit: BoxFit.cover,
        )
      : _buildPlaceholder(colorScheme),
  loading: () => _buildPlaceholder(colorScheme),
  error: (_, __) => _buildPlaceholder(colorScheme),
)
```

**playlistCoverProvider 实现**（已更新）：
- 返回 `PlaylistCoverData`，包含 `localPath` 和 `networkUrl`
- 优先级：
  1. 本地已下载的歌单封面（`playlist_cover.jpg`）
  2. 第一首已下载歌曲的本地封面
  3. 歌单的网络封面 URL
  4. 第一首歌曲的网络封面 URL

**歌单封面动态更新机制**（2026-01-18 新增）：

| 歌单类型 | coverUrl 来源 | 更新时机 |
|----------|--------------|----------|
| Bilibili 歌单 | API 返回的收藏夹封面 | 每次刷新歌单时更新 |
| YouTube 歌单 | 第一首歌曲的 thumbnailUrl | 刷新/添加/移除/重排序歌曲时更新 |
| 手动创建歌单 | 第一首歌曲的 thumbnailUrl | 添加/移除/重排序歌曲时更新 |

**触发封面更新的操作**：
- `ImportService.refreshPlaylist()` - YouTube 更新为第一首歌封面，Bilibili 更新为 API 封面
- `PlaylistService.addTrackToPlaylist()` - 如果歌单之前为空，更新封面
- `PlaylistService.addTracksToPlaylist()` - 如果歌单之前为空，更新封面
- `PlaylistService.removeTrackFromPlaylist()` - 如果移除的是第一首歌，更新封面
- `PlaylistService.reorderPlaylistTracks()` - 如果第一首歌变了，更新封面

**关键方法**：`PlaylistService._updateCoverUrlForNonBilibiliPlaylist()`
- 仅对非 Bilibili 歌单生效
- 将 `coverUrl` 设为第一首歌曲的 `thumbnailUrl`（如果歌单为空则设为 null）

### 2. 已下载分类卡片（DownloadedPage）✅ 已更新使用 ImageLoadingService

```dart
Widget _buildCover(ColorScheme colorScheme) {
  if (category.coverPath != null) {
    return ImageLoadingService.loadImage(
      localPath: category.coverPath,
      networkUrl: null,
      placeholder: _buildDefaultCover(colorScheme),
      fit: BoxFit.cover,
    );
  }
  return _buildDefaultCover(colorScheme);
}
```

**封面查找顺序**：
```dart
Future<String?> _findFirstCover(Directory folder) async {
  // 1. 优先检查歌单封面
  final playlistCoverFile = File(p.join(folder.path, 'playlist_cover.jpg'));
  if (await playlistCoverFile.exists()) {
    return playlistCoverFile.path;
  }
  // 2. 遍历子文件夹查找第一首歌的封面
  await for (final entity in folder.list()) {
    if (entity is Directory) {
      final coverFile = File(p.join(entity.path, 'cover.jpg'));
      if (await coverFile.exists()) {
        return coverFile.path;
      }
    }
  }
  return null;
}
```

### 3. 歌曲详情面板头像（TrackDetailPanel）✅ 使用集中式頭像

```dart
// build 方法中获取缓存和 baseDir
ref.watch(fileExistsCacheProvider);
final cache = ref.read(fileExistsCacheProvider.notifier);
final baseDirAsync = ref.watch(downloadBaseDirProvider);
final baseDir = baseDirAsync.valueOrNull;

Widget _buildAvatar(BuildContext context, Track? track, VideoDetail detail, 
                    FileExistsCache cache, String? baseDir) {
  // 使用 ImageLoadingService 加载头像
  // 優先級：本地頭像（集中式文件夾） → 网络头像 → 占位符
  return ImageLoadingService.loadAvatar(
    localPath: track?.getLocalAvatarPath(cache, baseDir: baseDir),
    networkUrl: detail.ownerFace.isNotEmpty ? detail.ownerFace : null,
    size: 32,
  );
}
```

---

## 下载时的图片保存

**文件位置**：`lib/services/download/download_service.dart`

### 设置选项

```dart
enum DownloadImageOption {
  none,            // 不下载任何图片
  coverOnly,       // 仅下载视频封面
  coverAndAvatar,  // 下载封面和UP主头像
}
```

### 保存逻辑

```dart
Future<void> _saveMetadata(Track track, String audioPath, {VideoDetail? videoDetail, int? order}) async {
  final settings = await _settingsRepository.get();
  final videoDir = Directory(p.dirname(audioPath));

  // 下载封面（保存到視頻文件夾）
  if (settings.downloadImageOption != DownloadImageOption.none && track.thumbnailUrl != null) {
    final coverPath = p.join(videoDir.path, 'cover.jpg');
    await _dio.download(track.thumbnailUrl!, coverPath);
  }

  // 下載創作者頭像到集中式文件夾（避免重複下載）
  if (settings.downloadImageOption == DownloadImageOption.coverAndAvatar &&
      videoDetail != null && videoDetail.ownerFace.isNotEmpty) {
    final creatorId = track.sourceType == SourceType.bilibili
        ? videoDetail.ownerId.toString()
        : videoDetail.channelId;
    
    if (creatorId.isNotEmpty && creatorId != '0') {
      final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
      await DownloadPathUtils.ensureAvatarDirExists(baseDir, track.sourceType);
      
      final avatarPath = DownloadPathUtils.getAvatarPath(
        baseDir: baseDir,
        sourceType: track.sourceType,
        creatorId: creatorId,
      );
      await _dio.download(videoDetail.ownerFace, avatarPath);  // 總是覆蓋獲取最新
    }
  }
}
```

**DownloadPathUtils 頭像相關方法**：
```dart
// 計算頭像路徑
static String getAvatarPath({
  required String baseDir,
  required SourceType sourceType,
  required String creatorId,
});

// 確保頭像目錄存在
static Future<void> ensureAvatarDirExists(String baseDir, SourceType sourceType);
```

### 歌单封面下载

歌单封面来源根据歌单类型不同：
- **Bilibili 歌单**：使用 `playlist.coverUrl`（API 返回的收藏夹封面）
- **YouTube/手动创建歌单**：使用第一首歌曲的 `thumbnailUrl`

总是覆盖已存在的 `playlist_cover.jpg`（获取最新封面）。

```dart
Future<void> _downloadPlaylistCover(Playlist playlist) async {
  String? coverUrl;

  // 根据歌单类型选择封面来源
  if (playlist.importSourceType == SourceType.bilibili) {
    coverUrl = playlist.coverUrl;  // Bilibili: API 封面
  } else {
    // YouTube/手动创建: 第一首歌曲的封面
    if (playlist.trackIds.isNotEmpty) {
      final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
      coverUrl = firstTrack?.thumbnailUrl;
    }
  }
  
  if (coverUrl == null || coverUrl.isEmpty) return;
  
  final playlistFolder = Directory(p.join(baseDir, subDir));
  final coverPath = p.join(playlistFolder.path, 'playlist_cover.jpg');
  await _dio.download(coverUrl, coverPath);  // 总是覆盖
}
```

---

## 占位符样式汇总

| 场景 | 背景 | 图标 | 图标大小 |
|------|------|------|----------|
| TrackThumbnail | surfaceContainerHighest | music_note | size * 0.5 |
| TrackCover | surfaceContainerHigh | music_note | 48 |
| 歌单卡片 | surfaceContainerHighest | music_note | 48 |
| 已下载分类 | 渐变背景 | folder | 48 |
| 头像 | surfaceContainerHighest | person | 16 |

---

## 图片加载最佳实践

### 1. 使用 TrackThumbnail/TrackCover 组件

```dart
// ✅ 正确：使用统一组件
TrackThumbnail(track: track, size: 48)
TrackCover(track: track, aspectRatio: 16/9)

// ❌ 错误：直接使用 Image.network
Image.network(track.thumbnailUrl!)
```

### 2. 处理加载错误

```dart
// 组件内部已处理
Image.file(
  file,
  errorBuilder: (_, __, ___) => _buildPlaceholder(colorScheme),
)
```

### 3. 检查本地文件存在

```dart
// 扩展方法已包含检查
if (track.localCoverPath != null) {
  // 此时文件一定存在
}
```
