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

**使用方式**：
```dart
// 通用图片加载
ImageLoadingService.loadImage(
  localPath: track.localCoverPath,
  networkUrl: track.thumbnailUrl,
  placeholder: placeholder,
  fit: BoxFit.cover,
);

// 专用方法
ImageLoadingService.loadTrackCover(track, size: 48);
ImageLoadingService.loadAvatar(localPath: path, networkUrl: url);
```

### 0.1. LocalImageCache（本地图片LRU缓存）✅ Phase 1 新增

**文件位置**：`lib/core/services/local_image_cache.dart`

**功能**：
- 缓存本地图片的 ImageProvider，避免重复从文件系统读取
- 使用 LRU 策略，限制缓存大小（默认 100 条）
- 自动跳过不存在的文件

**使用方式**：
```dart
final imageProvider = LocalImageCache.getLocalImage(path);
LocalImageCache.remove(path); // 清理单个缓存
LocalImageCache.clear(); // 清空所有缓存
```

### 1. TrackThumbnail（歌曲缩略图）

**文件位置**：`lib/ui/widgets/track_thumbnail.dart`

**使用场景**：歌曲列表、播放器迷你封面、队列项等

**尺寸**：通常 40-56px

**加载优先级**（已更新为使用 ImageLoadingService）：
```dart
Widget _buildImage(ColorScheme colorScheme) {
  final placeholder = _buildPlaceholder(colorScheme);
  
  // 使用 ImageLoadingService 加载图片（集成 LocalImageCache）
  return ImageLoadingService.loadImage(
    localPath: track.localCoverPath,
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

**文件位置**：`lib/core/extensions/track_extensions.dart`

```dart
extension TrackExtensions on Track {
  /// 获取本地封面路径
  String? get localCoverPath {
    if (downloadedPath == null) return null;
    final dir = Directory(downloadedPath!).parent;
    final coverPath = '${dir.path}/cover.jpg';
    return File(coverPath).existsSync() ? coverPath : null;
  }

  /// 获取本地头像路径
  String? get localAvatarPath {
    if (downloadedPath == null) return null;
    final dir = Directory(downloadedPath!).parent;
    final avatarPath = '${dir.path}/avatar.jpg';
    return File(avatarPath).existsSync() ? avatarPath : null;
  }

  bool get hasLocalCover => localCoverPath != null;
  bool get hasNetworkCover => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;
  bool get hasCover => hasLocalCover || hasNetworkCover;
}
```

**目录结构**：
```
下载目录/
├── 歌单名_ID/
│   ├── playlist_cover.jpg    # 歌单封面
│   ├── 视频标题/
│   │   ├── audio.m4a         # 音频文件
│   │   ├── cover.jpg         # 视频封面
│   │   ├── avatar.jpg        # UP主头像（可选）
│   │   └── metadata.json     # 元数据
```

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

### 2. 已下载分类卡片（DownloadedPage）

```dart
Widget _buildCover(ColorScheme colorScheme) {
  // 1. 有本地封面
  if (category.coverPath != null) {
    final coverFile = File(category.coverPath!);
    if (coverFile.existsSync()) {
      return Image.file(coverFile, fit: BoxFit.cover);
    }
  }
  // 2. 无本地封面 -> 渐变背景 + 文件夹图标
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(...),
    ),
    child: Icon(Icons.folder, size: 48),
  );
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

### 3. 歌曲详情面板头像（TrackDetailPanel）

```dart
Widget _buildAvatar(Track? track, VideoDetail detail) {
  // 1. 本地头像
  final localAvatarPath = track?.localAvatarPath;
  if (localAvatarPath != null) {
    return CircleAvatar(backgroundImage: FileImage(File(localAvatarPath)));
  }
  // 2. 网络头像
  if (detail.ownerFace.isNotEmpty) {
    return CircleAvatar(backgroundImage: NetworkImage(detail.ownerFace));
  }
  // 3. 占位符
  return CircleAvatar(child: Icon(Icons.person, size: 16));
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

  // 下载封面
  if (settings.downloadImageOption != DownloadImageOption.none && track.thumbnailUrl != null) {
    final coverPath = p.join(videoDir.path, 'cover.jpg');
    await _dio.download(track.thumbnailUrl!, coverPath);
  }

  // 下载头像
  if (settings.downloadImageOption == DownloadImageOption.coverAndAvatar &&
      videoDetail != null && videoDetail.ownerFace.isNotEmpty) {
    final avatarPath = p.join(videoDir.path, 'avatar.jpg');
    await _dio.download(videoDetail.ownerFace, avatarPath);
  }
}
```

### 歌单封面下载

```dart
Future<void> _downloadPlaylistCover(Playlist playlist, PlaylistDownloadTask task) async {
  if (playlist.coverUrl == null) return;
  
  final playlistFolder = Directory(p.join(baseDir, subDir));
  final coverPath = p.join(playlistFolder.path, 'playlist_cover.jpg');
  await _dio.download(playlist.coverUrl!, coverPath);
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
