# 自定义下载路径系统重构计划

**版本**: 1.0
**日期**: 2026-01-22
**状态**: 待实施

---

## 目录

1. [项目概述](#项目概述)
2. [问题分析](#问题分析)
3. [技术方案](#技术方案)
4. [实施计划](#实施计划)
5. [代码变更清单](#代码变更清单)
6. [测试计划](#测试计划)
7. [风险评估](#风险评估)
8. [回滚计划](#回滚计划)

---

## 项目概述

### 目标

实现跨平台（Android 15+ 和 Windows）的自定义下载路径系统，解决当前 Android 平台因存储权限限制导致的下载失败问题。

### 当前错误

```
[E] Download failed for task: 1: PathAccessException: Cannot create file,
path = '/storage/emulated/0/Music/FMP/Music/BV1f82jBfEFJ_.../P01.m4a.downloading'
(OS Error: Operation not permitted, errno = 1)
```

**根本原因**: Android 10+ 限制了应用对外部存储的直接访问，即使有 `WRITE_EXTERNAL_STORAGE` 权限也可能失败。

### 核心变更

| 变更项 | 当前行为 | 新行为 |
|--------|----------|--------|
| 路径计算时机 | 导入歌曲时预计算 | 下载完成后保存实际路径 |
| 下载路径配置 | 使用默认路径或 settings | 用户首次下载时必须选择 |
| 已下载标记 | 检查文件实际存在 | downloadPaths 非空即视为已下载 |
| 路径验证 | FileExistsCache 异步检查 | 使用时失败则清空路径 |
| 数据恢复 | 无 | 已下载页面支持刷新导入 |

---

## 问题分析

### 当前系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                      当前下载系统                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  导入歌曲 → 预计算路径 → 保存到 Track.downloadPaths          │
│     ↓                                                      │
│  用户点击下载 → 读取预计算路径 → 创建文件                     │
│     ↓                                                      │
│  FileExistsCache 检查文件存在性                               │
│     ↓                                                      │
│  显示已下载标记                                               │
└─────────────────────────────────────────────────────────────┘
```

### 问题点

1. **预计算路径问题**:
   - 导入时计算的路径可能与实际下载时不同
   - 用户修改下载路径后，旧路径仍然存在于数据库
   - 路径可能因系统更新而失效

2. **FileExistsCache 复杂度**:
   - 需要异步刷新缓存
   - build 期间不能同步检查
   - 路径失效时缓存不准确

3. **Android 权限问题**:
   - `getExternalStorageDirectory()` 在 Android 10+ 受限
   - 需要使用 Storage Access Framework (SAF)

4. **数据恢复缺失**:
   - 无法从本地文件恢复下载状态
   - 删除数据库后无法重建

---

## 技术方案

### 依赖包

```yaml
dependencies:
  file_picker: ^8.1.0  # 目录选择，支持 Android SAF
```

**选择理由**:
- `file_picker` 是 Flutter 生态中最成熟的文件选择包
- 支持 Android SAF (Storage Access Framework)
- 支持 Windows 平台
- 维护活跃，代码质量高

### 平台差异处理

| 平台 | 目录选择方式 | 权限要求 | 路径持久化 |
|------|-------------|----------|-----------|
| Android 15+ | SAF (系统文件选择器) | 无需额外权限 | URI 可能失效，需验证 |
| Android 10-14 | SAF 或直接访问 | MANAGE_EXTERNAL_STORAGE | 稳定 |
| Windows | 系统文件夹选择对话框 | 无需权限 | 稳定 |

### 核心设计原则

1. **延迟计算**: 下载完成后再保存路径
2. **乐观标记**: 有路径就认为已下载，使用时验证
3. **快速失败**: 文件访问失败时立即清空路径
4. **数据可恢复**: 支持从本地文件重建数据库

---

## 实施计划

### Phase 1: 基础设施 (2-3天)

**目标**: 建立目录选择和路径管理的基础能力

#### 1.1 创建 DownloadPathManager 服务

**文件**: `lib/services/download/download_path_manager.dart`

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/repositories/settings_repository.dart';

/// 下载路径管理服务
class DownloadPathManager {
  final SettingsRepository _settingsRepo;

  DownloadPathManager(this._settingsRepo);

  /// 检查是否已配置下载路径
  Future<bool> hasConfiguredPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir != null &&
           settings.customDownloadDir!.isNotEmpty;
  }

  /// 显示目录选择器
  Future<String?> selectDirectory(BuildContext context) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) return null;

    // 验证写入权限
    if (!await _verifyWritePermission(selectedDirectory)) {
      if (context.mounted) {
        _showPermissionError(context);
      }
      return null;
    }

    return selectedDirectory;
  }

  /// 验证目录写入权限
  Future<bool> _verifyWritePermission(String path) async {
    try {
      final testFile = File('$path/.fmp_test');
      await testFile.create();
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存下载路径
  Future<void> saveDownloadPath(String path) async {
    await _settingsRepo.updateCustomDownloadDir(path);
  }

  /// 获取当前下载路径
  Future<String?> getCurrentDownloadPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir;
  }

  /// 清除下载路径
  Future<void> clearDownloadPath() async {
    await _settingsRepo.updateCustomDownloadDir(null);
  }

  void _showPermissionError(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('权限不足'),
        content: const Text('无法写入所选目录，请选择其他位置或授予必要权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
```

#### 1.2 创建 Provider

**文件**: `lib/providers/download_path_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download/download_path_manager.dart';
import '../data/repositories/settings_repository.dart';

final downloadPathManagerProvider = Provider<DownloadPathManager>((ref) {
  return DownloadPathManager(ref.watch(settingsRepositoryProvider));
});
```

#### 1.3 修改 DownloadService

**文件**: `lib/services/download/download_service.dart`

**变更点**:
- 添加 `DownloadPathManager` 依赖
- 在 `addTrackDownload` 开始时检查路径配置
- 下载完成时保存实际路径到 Track

```dart
// 添加 DownloadPathManager 到构造函数
DownloadService({
  required DownloadRepository downloadRepository,
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required SourceManager sourceManager,
  required DownloadPathManager pathManager,  // 新增
})  : _downloadRepository = downloadRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _pathManager = pathManager,  // 新增
        // ...

// 修改 _startDownload 方法，下载完成时保存路径
await tempFile.rename(savePath);

// 保存实际下载路径到 Track
await _trackRepository.addDownloadPath(track.id, task.playlistId, savePath);

// 更新任务状态
await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.completed);
```

---

### Phase 2: UI 集成 (2-3天)

**目标**: 在用户界面中集成路径选择流程

#### 2.1 创建路径配置引导对话框

**文件**: `lib/ui/widgets/download_path_setup_dialog.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_path_provider.dart';

class DownloadPathSetupDialog extends ConsumerWidget {
  const DownloadPathSetupDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const DownloadPathSetupDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('设置下载路径'),
      content: const Text('首次下载需要选择音乐保存位置。请选择一个您有写入权限的文件夹。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _selectPath(context, ref),
          child: const Text('选择文件夹'),
        ),
      ],
    );
  }

  Future<void> _selectPath(BuildContext context, WidgetRef ref) async {
    final pathManager = ref.read(downloadPathManagerProvider);
    final path = await pathManager.selectDirectory(context);

    if (path != null) {
      await pathManager.saveDownloadPath(path);
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    }
  }
}
```

#### 2.2 修改下载入口

**文件**: `lib/ui/pages/library/playlist_detail_page.dart` (或其他下载入口)

```dart
Future<void> _startDownload(Track track, Playlist playlist) async {
  // 检查路径配置
  final pathManager = ref.read(downloadPathManagerProvider);
  if (!await pathManager.hasConfiguredPath()) {
    final configured = await DownloadPathSetupDialog.show(context);
    if (configured != true) return;
  }

  // 原有下载逻辑
  final downloadService = ref.read(downloadServiceProvider);
  await downloadService.addTrackDownload(track, fromPlaylist: playlist);
}
```

#### 2.3 设置页面添加下载路径配置

**文件**: `lib/ui/pages/settings/settings_page.dart`

```dart
// 在设置列表中添加
ListTile(
  leading: const Icon(Icons.folder),
  title: const Text('下载路径'),
  subtitle: Text(
    downloadPath ?? '未设置',
    style: TextStyle(color: downloadPath == null ? Colors.red : null),
  ),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => _changeDownloadPath(context, ref),
),
```

---

### Phase 3: 简化下载标记逻辑 (1-2天)

**目标**: 移除预计算路径，简化下载状态判断

#### 3.1 修改 TrackExtensions

**文件**: `lib/core/extensions/track_extensions.dart`

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

extension TrackExtensions on Track {
  /// 简化逻辑：有路径就认为已下载
  ///
  /// 注意：这假设路径有效。使用时如果文件不存在会自动清空。
  bool get isDownloaded => downloadPaths.isNotEmpty;

  /// 获取本地音频路径
  ///
  /// 尝试使用第一个下载路径，如果失败则清空该路径
  /// 返回第一个实际存在的路径，或 null
  String? get localAudioPath {
    if (downloadPaths.isEmpty) return null;

    for (int i = 0; i < downloadPaths.length; i++) {
      try {
        final file = File(downloadPaths[i]);
        if (file.existsSync()) {
          return downloadPaths[i];
        }
      } catch (_) {
        // 路径无效，继续检查下一个
      }
    }

    // 所有路径都无效，返回 null
    return null;
  }

  /// 清理无效的下载路径
  ///
  /// 检查所有路径，移除不存在的
  List<String> get validDownloadPaths {
    final valid = <String>[];
    for (final path in downloadPaths) {
      try {
        if (File(path).existsSync()) {
          valid.add(path);
        }
      } catch (_) {
        // 路径无效，跳过
      }
    }
    return valid;
  }

  /// 获取本地封面路径
  String? getLocalCoverPath() {
    if (downloadPaths.isEmpty) return null;

    for (final path in downloadPaths) {
      try {
        final dir = Directory(p.dirname(path));
        final coverFile = File(p.join(dir.path, 'cover.jpg'));
        if (coverFile.existsSync()) {
          return coverFile.path;
        }
      } catch (_) {
        // 路径无效，继续
      }
    }
    return null;
  }

  /// 获取本地头像路径
  String? getLocalAvatarPath(String baseDir) {
    final creatorId = sourceType == SourceType.bilibili
        ? ownerId?.toString()
        : channelId;
    if (creatorId == null || creatorId.isEmpty || creatorId == '0') {
      return null;
    }

    final platform = sourceType == SourceType.bilibili ? 'bilibili' : 'youtube';
    final avatarPath = p.join(baseDir, 'avatars', platform, '$creatorId.jpg');

    try {
      if (File(avatarPath).existsSync()) {
        return avatarPath;
      }
    } catch (_) {}
    return null;
  }

  // ... 其他方法保持不变
}
```

#### 3.2 移除预计算路径逻辑

**文件**: `lib/services/library/playlist_service.dart`

```dart
// 移除导入时计算下载路径的代码
// 之前：
// final downloadPath = DownloadPathUtils.computeDownloadPath(...);
// track.setDownloadPath(playlist.id, downloadPath);

// 之后：
// 不做任何操作，路径在下载完成时设置
```

#### 3.3 更新 TrackRepository

**文件**: `lib/data/repositories/track_repository.dart`

```dart
/// 添加下载路径
Future<void> addDownloadPath(int trackId, int? playlistId, String path) async {
  final track = await getById(trackId);
  if (track == null) return;

  if (playlistId != null) {
    track.setDownloadPath(playlistId, path);
  } else {
    // 未指定歌单，添加到通用路径
    if (!track.downloadPaths.contains(path)) {
      track.downloadPaths = List.from(track.downloadPaths)..add(path);
      track.playlistIds = List.from(track.playlistIds)..add(0);
    }
  }

  await isar.writeTxn(() async {
    await isar.tracks.put(track);
  });
}

/// 清除指定歌单的下载路径
Future<void> clearDownloadPath(int trackId, int? playlistId) async {
  final track = await getById(trackId);
  if (track == null) return;

  if (playlistId != null) {
    track.removeDownloadPath(playlistId);
  } else {
    track.downloadPaths.clear();
    track.playlistIds.clear();
  }

  await isar.writeTxn(() async {
    await isar.tracks.put(track);
  });
}

/// 清除所有下载路径
Future<void> clearAllDownloadPaths() async {
  await isar.writeTxn(() async {
    final tracks = await isar.tracks.where().findAll();
    for (final track in tracks) {
      track.downloadPaths.clear();
      track.playlistIds.clear();
      await isar.tracks.put(track);
    }
  });
}
```

---

### Phase 4: 已下载页面刷新功能 (2天)

**目标**: 实现从本地文件恢复下载状态

#### 4.1 创建 DownloadPathSyncService

**文件**: `lib/services/download/download_path_sync_service.dart`

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../data/models/track.dart';
import '../../data/repositories/track_repository.dart';
import '../../providers/download_path_provider.dart';
import 'download_path_utils.dart';
import 'download_scanner.dart';

/// 下载路径同步服务
///
/// 负责扫描本地文件并同步到数据库
class DownloadPathSyncService {
  final TrackRepository _trackRepo;
  final DownloadPathManager _pathManager;

  DownloadPathSyncService(this._trackRepo, this._pathManager);

  /// 同步本地文件到数据库
  ///
  /// 扫描下载目录，匹配 Track 并更新下载路径
  /// 返回 (更新数量, 孤儿文件数量)
  Future<(int updated, int orphans)> syncLocalFiles() async {
    final basePath = await _pathManager.getCurrentDownloadPath();
    if (basePath == null) {
      throw Exception('下载路径未配置');
    }

    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return (0, 0);
    }

    int updated = 0;
    int orphans = 0;

    // 扫描所有文件夹
    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        final result = await _syncFolder(entity);
        updated += result.$1;
        orphans += result.$2;
      }
    }

    return (updated, orphans);
  }

  /// 同步单个文件夹
  Future<(int updated, int orphans)> _syncFolder(Directory folder) async {
    final tracks = await DownloadScanner.scanFolderForTracks(folder.path);
    int updated = 0;
    int orphans = 0;

    for (final scannedTrack in tracks) {
      // 在数据库中查找匹配的 Track
      final existingTrack = await _findMatchingTrack(scannedTrack);

      if (existingTrack != null) {
        // 找到匹配，更新下载路径
        final path = scannedTrack.downloadPaths.firstOrNull;
        if (path != null) {
          await _trackRepo.addDownloadPath(
            existingTrack.id,
            scannedTrack.playlistIds.firstOrNull,
            path,
          );
          updated++;
        }
      } else {
        // 没有找到匹配的 Track
        orphans++;
      }
    }

    return (updated, orphans);
  }

  /// 查找匹配的 Track
  ///
  /// 匹配规则：sourceId + cid + pageNum
  Future<Track?> _findMatchingTrack(Track scannedTrack) async {
    final tracks = await _trackRepo.getBySourceId(scannedTrack.sourceId);

    for (final track in tracks) {
      // 检查 cid 和 pageNum 是否匹配
      if (track.cid == scannedTrack.cid &&
          track.pageNum == scannedTrack.pageNum) {
        return track;
      }
    }

    return null;
  }

  /// 清理无效的下载路径
  ///
  /// 检查数据库中的所有下载路径，移除不存在的
  Future<int> cleanupInvalidPaths() async {
    final allTracks = await _trackRepo.getAll();
    int cleaned = 0;

    for (final track in allTracks) {
      final validPaths = track.validDownloadPaths;

      if (validPaths.length != track.downloadPaths.length) {
        track.downloadPaths = validPaths;
        await _trackRepo.save(track);
        cleaned++;
      }
    }

    return cleaned;
  }
}
```

#### 4.2 修改已下载页面

**文件**: `lib/ui/pages/library/downloaded_page.dart`

```dart
Future<void> _refreshAndSync() async {
  final syncService = ref.read(downloadPathSyncServiceProvider);

  // 显示进度对话框
  if (!mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('正在扫描本地文件...'),
        ],
      ),
    ),
  );

  try {
    final (updated, orphans) = await syncService.syncLocalFiles();

    if (mounted) Navigator.pop(context);

    // 刷新页面
    ref.invalidate(downloadedCategoriesProvider);

    // 显示结果
    if (mounted) {
      ToastService.show(
        context,
        '同步完成: 更新 $updated 首${orphans > 0 ? ', 孤儿文件 $orphan 个' : ''}',
      );
    }
  } catch (e) {
    if (mounted) Navigator.pop(context);
    if (mounted) {
      ToastService.show(context, '同步失败: $e');
    }
  }
}

@override
Widget build(BuildContext context) {
  // ...
  AppBar(
    actions: [
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: '刷新并同步',
        onPressed: _refreshAndSync,  // 改为调用同步方法
      ),
      // ...
    ],
  ),
  // ...
}
```

---

### Phase 5: 修改下载路径处理 (1天)

**目标**: 实现修改下载路径时清空数据库路径

#### 5.1 修改路径变更对话框

**文件**: `lib/ui/widgets/change_download_path_dialog.dart`

```dart
Future<void> _showChangePathDialog(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('更改下载路径'),
      content: const Text(
        '更改下载路径将清空所有已保存的下载路径信息。\n\n'
        '下载的文件不会被删除，但需要重新扫描才能显示。\n\n'
        '是否继续？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('继续'),
        ),
      ],
    ),
  );

  if (result == true && context.mounted) {
    await _changePath(context, ref);
  }
}

Future<void> _changePath(BuildContext context, WidgetRef ref) async {
  final pathManager = ref.read(downloadPathManagerProvider);
  final trackRepo = ref.read(trackRepositoryProvider);

  // 选择新路径
  final newPath = await pathManager.selectDirectory(context);
  if (newPath == null) return;

  // 清空所有下载路径
  await trackRepo.clearAllDownloadPaths();

  // 保存新路径
  await pathManager.saveDownloadPath(newPath);

  // 刷新相关 Provider
  ref.invalidate(fileExistsCacheProvider);
  ref.invalidate(downloadedCategoriesProvider);

  if (context.mounted) {
    ToastService.show(context, '下载路径已更改');
  }
}
```

---

### Phase 6: 清理和优化 (1天)

**目标**: 移除不再需要的代码，优化现有逻辑

#### 6.1 简化 FileExistsCache

**文件**: `lib/providers/download/file_exists_cache.dart`

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/track.dart';

/// 文件存在检查缓存（简化版）
///
/// 主要用于 UI 层的图片加载优化
class FileExistsCache extends StateNotifier<Set<String>> {
  FileExistsCache() : super({});

  /// 检查路径是否存在（带缓存）
  bool exists(String path) {
    if (state.contains(path)) return true;

    // 异步检查并缓存
    _checkAndCache(path);
    return false;
  }

  /// 标记路径为已存在
  void markAsExisting(String path) {
    state = {...state, path};
  }

  /// 移除路径缓存
  void remove(String path) {
    final newState = Set<String>.from(state);
    newState.remove(path);
    state = newState;
  }

  /// 清除所有缓存
  void clearAll() {
    state = {};
  }

  void _checkAndCache(String path) {
    Future.microtask(() async {
      if (await File(path).exists()) {
        state = {...state, path};
      }
    });
  }
}

final fileExistsCacheProvider =
    StateNotifierProvider<FileExistsCache, Set<String>>((ref) {
  return FileExistsCache();
});
```

#### 6.2 移除 PlaylistFolderMigrator

**文件**: `lib/services/download/playlist_folder_migrator.dart` (删除)

不再需要歌单重命名时迁移路径的逻辑。

---

## 代码变更清单

### 新增文件

| 文件路径 | 说明 |
|---------|------|
| `lib/services/download/download_path_manager.dart` | 下载路径管理服务 |
| `lib/providers/download_path_provider.dart` | 下载路径 Provider |
| `lib/ui/widgets/download_path_setup_dialog.dart` | 路径设置引导对话框 |
| `lib/ui/widgets/change_download_path_dialog.dart` | 更改路径对话框 |
| `lib/services/download/download_path_sync_service.dart` | 本地文件同步服务 |

### 修改文件

| 文件路径 | 变更内容 |
|---------|----------|
| `lib/services/download/download_service.dart` | 添加 DownloadPathManager 依赖，下载完成时保存路径 |
| `lib/core/extensions/track_extensions.dart` | 简化 isDownloaded 逻辑，添加路径清理方法 |
| `lib/data/repositories/track_repository.dart` | 添加 addDownloadPath, clearDownloadPath 等方法 |
| `lib/services/library/playlist_service.dart` | 移除预计算路径逻辑 |
| `lib/ui/pages/library/downloaded_page.dart` | 添加同步功能 |
| `lib/ui/pages/settings/settings_page.dart` | 添加下载路径配置入口 |
| `lib/ui/pages/library/playlist_detail_page.dart` | 下载前检查路径配置 |
| `lib/providers/download/file_exists_cache.dart` | 简化实现 |

### 删除文件

| 文件路径 | 原因 |
|---------|------|
| `lib/services/download/playlist_folder_migrator.dart` | 不再需要路径迁移逻辑 |

---

## 测试计划

### 单元测试

#### DownloadPathManager

```dart
test('hasConfiguredPath returns false when no path set', () async {
  // Setup mock settings repository with empty customDownloadDir
  // Assert hasConfiguredPath() returns false
});

test('selectDirectory validates write permission', () async {
  // Mock file picker
  // Mock file creation
  // Assert permission check works
});
```

#### DownloadPathSyncService

```dart
test('syncLocalFiles matches tracks by sourceId and cid', () async {
  // Setup mock repository with tracks
  // Setup mock file system
  // Assert matching tracks are updated
});
```

### 集成测试

#### 下载流程

1. **首次下载**:
   - 点击下载按钮
   - 验证路径配置对话框显示
   - 选择路径后下载成功
   - 验证路径已保存到数据库

2. **后续下载**:
   - 点击下载按钮
   - 验证直接开始下载（不显示配置对话框）
   - 验证文件保存到配置的路径

3. **修改路径**:
   - 更改下载路径
   - 验证确认对话框显示
   - 确认后验证数据库路径已清空
   - 验证新文件保存到新路径

#### 同步功能

1. **扫描本地文件**:
   - 在下载目录放入文件
   - 点击刷新按钮
   - 验证文件被识别并匹配到 Track

2. **孤儿文件处理**:
   - 创建不在数据库中的文件
   - 运行同步
   - 验证孤儿文件计数正确

### 平台测试

#### Android 15+

- [ ] SAF 目录选择正常工作
- [ ] 下载到选定目录成功
- [ ] 应用重启后路径仍然有效
- [ ] 撤销权限后能正确提示

#### Windows

- [ ] 文件夹选择对话框正常显示
- [ ] 下载到选定目录成功
- [ ] 路径持久化正常

---

## 风险评估

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| SAF URI 在应用重启后失效 | 高 | 中 | 每次下载前验证路径有效性，失败则提示重新选择 |
| 用户选择系统受保护目录 | 中 | 低 | 验证写入权限，失败则提示重新选择 |
| 大量文件同步导致 UI 卡顿 | 中 | 中 | 使用 Isolate 进行后台扫描 |
| 修改路径后用户无法找到旧文件 | 低 | 高 | 明确提示文件不会被删除，提供重新扫描功能 |
| 现有用户升级后数据丢失 | 高 | 低 | 保留现有 downloadPaths，提供清理选项 |

---

## 回滚计划

### 触发条件

1. Android 平台下载失败率超过 5%
2. 用户反馈无法访问已下载文件
3. 同步功能导致数据损坏

### 回滚步骤

1. **代码回滚**: 恢复到重构前的 commit
2. **数据恢复**:
   ```dart
   // 从备份恢复 downloadPaths
   // 使用 metadata.json 重建路径信息
   ```
3. **用户通知**: 说明问题并提供临时解决方案

### 数据备份方案

在实施前创建数据备份功能：

```dart
// lib/services/data_backup_service.dart
Future<void> backupDownloadPaths() async {
  final tracks = await isar.tracks.where().findAll();
  final backup = tracks.map((t) => {
    'id': t.id,
    'sourceId': t.sourceId,
    'downloadPaths': t.downloadPaths,
  }).toList();

  final file = File('${(await getTemporaryDirectory()).path}/download_paths_backup.json');
  await file.writeAsString(jsonEncode(backup));
}
```

---

## 实施时间表

| 阶段 | 任务 | 预计时间 | 依赖 |
|------|------|----------|------|
| Phase 1 | 基础设施 (DownloadPathManager) | 2-3天 | - |
| Phase 2 | UI 集成 (对话框、设置页面) | 2-3天 | Phase 1 |
| Phase 3 | 简化下载标记逻辑 | 1-2天 | Phase 2 |
| Phase 4 | 已下载页面刷新功能 | 2天 | Phase 3 |
| Phase 5 | 修改下载路径处理 | 1天 | Phase 4 |
| Phase 6 | 清理和优化 | 1天 | Phase 5 |
| 测试 | 单元测试、集成测试 | 2-3天 | Phase 6 |
| **总计** | | **13-17天** | |

---

## 附录

### A. 相关文档

- [FMP 下载系统文档](../download_system.md)
- [file_picker 包文档](https://pub.dev/packages/file_picker)
- [Android Storage Access Framework](https://developer.android.com/guide/topics/providers/document-provider)

### B. 变更历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| 1.0 | 2026-01-22 | 初始版本 |
