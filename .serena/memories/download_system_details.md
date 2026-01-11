# FMP 下载系统详细文档

## 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                       UI 层                                  │
│  download_manager_page, playlist_detail_page, search_page   │
│                            │                                 │
│                            ▼                                 │
│              downloadServiceProvider                         │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    DownloadService                           │
│              (lib/services/download/download_service.dart)   │
│                                                              │
│  职责：                                                       │
│  - 任务调度（并发控制）                                        │
│  - 文件下载（带进度）                                          │
│  - 元数据保存                                                 │
│  - 封面/头像下载                                              │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                   DownloadRepository                         │
│              (lib/data/repositories/download_repository.dart)│
│                                                              │
│  职责：                                                       │
│  - DownloadTask CRUD                                        │
│  - PlaylistDownloadTask CRUD                                │
│  - 任务状态管理                                               │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      Isar Database                           │
│  DownloadTask, PlaylistDownloadTask                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 数据模型

### DownloadTask（单曲下载任务）

```dart
class DownloadTask {
  int id;
  int trackId;                    // 关联的歌曲ID
  int? playlistDownloadTaskId;    // 关联的歌单下载任务（可选）
  DownloadStatus status;          // pending/downloading/completed/failed/paused
  double progress;                // 0.0 - 1.0
  int downloadedBytes;
  int? totalBytes;
  String? errorMessage;
  int priority;                   // 优先级（越小越优先）
  DateTime createdAt;
}
```

### PlaylistDownloadTask（歌单下载任务）

```dart
class PlaylistDownloadTask {
  int id;
  int playlistId;                 // 关联的歌单ID
  String playlistName;            // 歌单名称（用于文件夹命名）
  List<int> trackIds;             // 歌单中的所有歌曲ID
  DownloadStatus status;
  int priority;
  DateTime createdAt;
}
```

### DownloadStatus 枚举

```dart
enum DownloadStatus {
  pending,      // 等待下载
  downloading,  // 下载中
  completed,    // 已完成
  failed,       // 失败
  paused,       // 已暂停
}
```

---

## 下载服务核心逻辑

### 1. 初始化

```dart
Future<void> initialize() async {
  // 重置所有 downloading 状态的任务为 paused（防止意外中断）
  await _downloadRepository.resetDownloadingToPaused();
  // 启动调度器
  _startScheduler();
}
```

### 2. 调度器

```dart
// 每500ms检查一次
Timer.periodic(const Duration(milliseconds: 500), (_) {
  _scheduleDownloads();
});

Future<void> _scheduleDownloads() async {
  final settings = await _settingsRepository.get();
  final maxConcurrent = settings.maxConcurrentDownloads;  // 默认3
  
  final availableSlots = maxConcurrent - _activeDownloads;
  if (availableSlots <= 0) return;
  
  final pendingTasks = await _downloadRepository.getTasksByStatus(DownloadStatus.pending);
  
  for (int i = 0; i < availableSlots && i < pendingTasks.length; i++) {
    _startDownload(pendingTasks[i]);
  }
}
```

### 3. 单曲下载流程

```dart
void _startDownload(DownloadTask task) async {
  // 1. 更新状态为下载中
  await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.downloading);
  
  // 2. 获取歌曲信息
  final track = await _trackRepository.getById(task.trackId);
  
  // 3. 获取音频URL（需要刷新）
  String audioUrl;
  if (!_sourceManager.needsRefresh(track) && track.audioUrl != null) {
    audioUrl = track.audioUrl!;
  } else {
    final refreshedTrack = await _sourceManager.refreshAudioUrl(track);
    audioUrl = refreshedTrack.audioUrl!;
  }
  
  // 4. 确定保存路径
  final savePath = await _getDownloadPath(track, task);
  
  // 5. 下载文件（带进度回调）
  await _dio.download(
    audioUrl,
    savePath,
    onReceiveProgress: (received, total) {
      // 节流更新（500ms 或 5% 进度变化）
      if (shouldUpdate) {
        _downloadRepository.updateTaskProgress(task.id, progress, received, total);
        _progressController.add(DownloadProgressEvent(...));
      }
    },
  );
  
  // 6. 获取 VideoDetail（用于完整元数据）
  VideoDetail? videoDetail = await source.getVideoDetail(track.sourceId);
  
  // 7. 保存元数据
  await _saveMetadata(track, savePath, videoDetail: videoDetail, order: trackOrder);
  
  // 8. 更新歌曲的 downloadedPath
  track.downloadedPath = savePath;
  await _trackRepository.save(track);
  
  // 9. 更新任务状态为完成
  await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.completed);
}
```

### 4. 歌单下载流程

```dart
Future<PlaylistDownloadTask?> addPlaylistDownload(Playlist playlist) async {
  // 1. 检查重复
  final existingTask = await _downloadRepository.getPlaylistTaskByPlaylistId(playlist.id);
  if (existingTask?.status == DownloadStatus.downloading) {
    return existingTask;  // 正在下载中，不重复添加
  }
  
  // 2. 获取歌单中的所有歌曲
  final tracks = await _trackRepository.getByIds(playlist.trackIds);
  
  // 3. 创建歌单下载任务
  final playlistTask = PlaylistDownloadTask()
    ..playlistId = playlist.id
    ..playlistName = playlist.name
    ..trackIds = playlist.trackIds
    ..status = DownloadStatus.pending;
  
  // 4. 下载歌单封面
  await _downloadPlaylistCover(playlist, savedPlaylistTask);
  
  // 5. 为每个歌曲创建下载任务
  for (final track in tracks) {
    await addTrackDownload(
      track,
      fromPlaylist: playlist,
      playlistDownloadTaskId: savedPlaylistTask.id,
    );
  }
}
```

---

## 文件存储结构

### 目录结构

```
下载目录/
├── 歌单名_歌单ID/
│   ├── playlist_cover.jpg        # 歌单封面
│   ├── 视频标题A/
│   │   ├── audio.m4a             # 单P视频音频
│   │   ├── cover.jpg             # 视频封面
│   │   ├── avatar.jpg            # UP主头像（可选）
│   │   └── metadata.json         # 元数据
│   ├── 视频标题B_多P/
│   │   ├── P01 - 分P标题1.m4a    # 多P视频
│   │   ├── P02 - 分P标题2.m4a
│   │   ├── cover.jpg
│   │   ├── avatar.jpg
│   │   └── metadata.json
├── 未分类/                        # 单独下载的歌曲
│   ├── 视频标题/
│   │   └── ...
```

### 路径生成逻辑

```dart
Future<String> _getDownloadPath(Track track, DownloadTask task) async {
  final baseDir = settings.customDownloadDir ?? await _getDefaultDownloadDir();
  
  // 子目录
  String subDir;
  if (task.playlistDownloadTaskId != null) {
    final playlistTask = await _downloadRepository.getPlaylistTaskById(task.playlistDownloadTaskId!);
    subDir = _sanitizeFileName('${playlistTask.playlistName}_${playlistTask.playlistId}');
  } else {
    subDir = '未分类';
  }
  
  // 视频文件夹名
  final videoFolder = _sanitizeFileName(track.parentTitle ?? track.title);
  
  // 音频文件名
  String fileName;
  if (track.isPartOfMultiPage && track.pageNum != null) {
    fileName = 'P${track.pageNum!.toString().padLeft(2, '0')} - ${_sanitizeFileName(track.title)}.m4a';
  } else {
    fileName = 'audio.m4a';
  }
  
  return p.join(baseDir, subDir, videoFolder, fileName);
}
```

### 文件名清理

```dart
String _sanitizeFileName(String name) {
  // 将特殊字符转换为全角字符
  const replacements = {
    '/': '／', '\\': '＼', ':': '：', '*': '＊',
    '?': '？', '"': '＂', '<': '＜', '>': '＞', '|': '｜',
  };
  
  String result = name;
  for (final entry in replacements.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  
  // 限制长度
  if (result.length > 200) {
    result = result.substring(0, 200);
  }
  
  return result.isEmpty ? 'untitled' : result;
}
```

---

## 元数据存储

### metadata.json 结构

```json
{
  "sourceId": "BV1xxx",
  "sourceType": "bilibili",
  "title": "视频标题",
  "artist": "UP主名称",
  "durationMs": 180000,
  "cid": 12345678,
  "pageNum": 1,
  "parentTitle": "父视频标题",
  "thumbnailUrl": "https://...",
  "downloadedAt": "2025-01-11T10:00:00Z",
  "order": 0,
  
  // VideoDetail 扩展信息
  "description": "视频简介",
  "viewCount": 100000,
  "likeCount": 5000,
  "coinCount": 1000,
  "favoriteCount": 2000,
  "shareCount": 500,
  "danmakuCount": 3000,
  "commentCount": 200,
  "publishDate": "2025-01-01T00:00:00Z",
  "ownerName": "UP主",
  "ownerFace": "https://...",
  "ownerId": 123456,
  "hotComments": [
    {
      "content": "评论内容",
      "memberName": "用户名",
      "memberAvatar": "https://...",
      "likeCount": 100
    }
  ]
}
```

---

## Provider 结构

```dart
// 服务 Provider
final downloadServiceProvider = Provider<DownloadService>

// 任务列表 Provider
final downloadTasksProvider = StreamProvider<List<DownloadTask>>
final playlistDownloadTasksProvider = StreamProvider<List<PlaylistDownloadTask>>

// 便捷 Provider
final activeDownloadsProvider = Provider<List<DownloadTask>>  // 进行中
final completedDownloadsProvider = Provider<List<DownloadTask>>  // 已完成
final isTrackDownloadingProvider = Provider.family<bool, int>  // 某歌曲是否在下载

// 进度流
final downloadProgressProvider = StreamProvider<DownloadProgressEvent>

// 已下载分类
final downloadedCategoriesProvider = FutureProvider<List<DownloadedCategory>>
final downloadedCategoryTracksProvider = FutureProvider.family<List<Track>, String>
```

---

## 已下载页面的文件扫描

### 分类获取

```dart
final downloadedCategoriesProvider = FutureProvider<List<DownloadedCategory>>((ref) async {
  final downloadDir = Directory(dirInfo.path);
  
  await for (final entity in downloadDir.list()) {
    if (entity is Directory) {
      final trackCount = await _countAudioFiles(entity);  // 统计 .m4a 文件
      if (trackCount > 0) {
        final coverPath = await _findFirstCover(entity);  // 查找封面
        categories.add(DownloadedCategory(
          folderName: folderName,
          displayName: _extractDisplayName(folderName),  // 去掉 _ID 后缀
          trackCount: trackCount,
          coverPath: coverPath,
          folderPath: entity.path,
        ));
      }
    }
  }
  
  // 排序："未分类"放最后
  categories.sort((a, b) {
    if (a.folderName == '未分类') return 1;
    if (b.folderName == '未分类') return -1;
    return a.displayName.compareTo(b.displayName);
  });
});
```

### Track 扫描

```dart
Future<List<Track>> _scanFolderForTracks(String folderPath) async {
  await for (final entity in folder.list()) {
    if (entity is Directory) {
      // 读取 metadata.json
      final metadataFile = File(p.join(entity.path, 'metadata.json'));
      Map<String, dynamic>? metadata;
      if (await metadataFile.exists()) {
        metadata = jsonDecode(await metadataFile.readAsString());
      }
      
      // 扫描 .m4a 文件
      await for (final audioEntity in entity.list()) {
        if (audioEntity.path.endsWith('.m4a')) {
          Track? track;
          
          if (metadata != null) {
            track = _trackFromMetadata(metadata, audioEntity.path);
            // 多P处理：从文件名提取 pageNum
            final pageMatch = RegExp(r'^P(\d+)').firstMatch(fileName);
            if (pageMatch != null) {
              track.pageNum = int.parse(pageMatch.group(1)!);
            }
          }
          
          // 无 metadata 时创建基本 Track
          if (track == null) {
            track = Track()
              ..sourceId = p.basename(entity.path)
              ..title = p.basenameWithoutExtension(audioEntity.path)
              ..downloadedPath = audioEntity.path;
          }
          
          tracks.add(track);
        }
      }
    }
  }
  
  // 排序：优先 order，其次 parentTitle + pageNum
  tracks.sort((a, b) {
    if (a.order != null && b.order != null) {
      return a.order!.compareTo(b.order!);
    }
    if (a.order != null) return -1;
    if (b.order != null) return 1;
    // 向后兼容
    final groupCompare = (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
    if (groupCompare != 0) return groupCompare;
    return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
  });
});
```

---

## 下载进度更新节流

为避免 Windows 平台的线程问题，进度更新使用节流策略：

```dart
DateTime lastProgressUpdate = DateTime.now();
double lastProgress = 0.0;
const progressUpdateInterval = Duration(milliseconds: 500);

onReceiveProgress: (received, total) {
  final progress = received / total;
  final now = DateTime.now();
  
  // 只在以下情况更新：
  // 1. 距离上次更新超过 500ms
  // 2. 进度变化超过 5%
  // 3. 下载完成 (100%)
  final shouldUpdate = 
      now.difference(lastProgressUpdate) >= progressUpdateInterval ||
      (progress - lastProgress) >= 0.05 ||
      progress >= 1.0;
  
  if (shouldUpdate) {
    lastProgressUpdate = now;
    lastProgress = progress;
    _downloadRepository.updateTaskProgress(task.id, progress, received, total);
    _progressController.add(DownloadProgressEvent(...));
  }
}
```

---

## 设置选项

### DownloadImageOption

| 值 | 描述 | 保存内容 |
|---|------|----------|
| none | 关闭 | 不下载图片 |
| coverOnly | 仅封面 | cover.jpg |
| coverAndAvatar | 封面和头像 | cover.jpg + avatar.jpg |

### maxConcurrentDownloads

- 默认值：3
- 范围：1-5
- 控制同时下载的任务数量
