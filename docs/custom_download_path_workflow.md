# 自定义下载路径系统 - 实施工作流

**基于**: `custom_download_path_plan.md`
**版本**: 1.0
**日期**: 2026-01-22
**预计总工时**: 13-17 天

---

## 工作流概览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        自定义下载路径系统实施工作流                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Phase 1: 基础设施 ─────┐                                              │
│  Phase 2: UI 集成 ───────┼──► 3-5 天 ──► 里程碑 1: 路径选择可用          │
│  Phase 3: 简化逻辑 ──────┘                                              │
│                                                                         │
│  Phase 4: 同步功能 ────────► 2 天 ────► 里程碑 2: 数据恢复完成          │
│                                                                         │
│  Phase 5: 路径变更 ────────► 1 天 ────► 里程碑 3: 完整用户体验          │
│                                                                         │
│  Phase 6: 清理优化 ────────► 1 天                                       │
│                                                                         │
│  测试与验证 ───────────────► 2-3 天 ───► 里程碑 4: 发布就绪            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 依赖关系图

```
                    ┌─────────────────────────────────────┐
                    │        添加 file_picker 依赖          │
                    │         (pubspec.yaml)               │
                    └─────────────────┬───────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Phase 1: 基础设施                              │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────┐│
│  │ DownloadPathManager  │→│  downloadPathProvider │→│ DownloadService ││
│  │      服务创建         │  │      Provider 创建    │  │    修改集成     ││
│  └──────────────────────┘  └──────────────────────┘  └─────────────────┘│
│                                        │                                    │
└────────────────────────────────────────┼────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           Phase 2: UI 集成                              │
│  ┌──────────────────────────┐  ┌─────────────────────┐  ┌─────────────┐│
│  │ DownloadPathSetupDialog  │→│  下载入口修改          │→│设置页面集成   ││
│  │      引导对话框           │  │ (playlist_detail)   │  │(settings)   ││
│  └──────────────────────────┘  └─────────────────────┘  └─────────────┘│
│                                        │                                    │
└────────────────────────────────────────┼────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Phase 3: 简化逻辑                              │
│  ┌──────────────────────┐  ┌──────────────────────┐  ┌─────────────────┐│
│  │  TrackExtensions     │→│  TrackRepository      │→│PlaylistService  ││
│  │     重构              │  │   方法添加            │  │ 移除预计算      ││
│  └──────────────────────┘  └──────────────────────┘  └─────────────────┘│
│                                        │                                    │
└────────────────────────────────────────┼────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Phase 4: 同步功能                              │
│  ┌──────────────────────────┐  ┌──────────────────────────────────────┐ │
│  │ DownloadPathSyncService  │→│         DownloadedPage               │ │
│  │       服务创建            │→│            刷新功能                  │ │
│  └──────────────────────────┘  └──────────────────────────────────────┘ │
│                                        │                                    │
└────────────────────────────────────────┼────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Phase 5: 路径变更处理                            │
│  ┌────────────────────────────────────────────────────────────────────┐│
│  │              ChangeDownloadPathDialog                              ││
│  │                   路径变更对话框                                    ││
│  └────────────────────────────────────────────────────────────────────┘│
│                                        │                                    │
└────────────────────────────────────────┼────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Phase 6: 清理优化                              │
│  ┌──────────────────────┐  ┌──────────────────────────────────────────┐│
│  │  FileExistsCache      │  │    删除 PlaylistFolderMigrator          ││
│  │     简化              │  │                                        ││
│  └──────────────────────┘  └──────────────────────────────────────────┘│
│                                        │                                    │
└────────────────────────────────────────┼────────────────────────────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │      测试与验证      │
                              │   (单元/集成/平台)   │
                              └─────────────────────┘
```

---

## Phase 1: 基础设施 (2-3天)

### 目标
建立目录选择和路径管理的基础能力

### 任务清单

#### Task 1.1: 添加依赖 (30分钟)

**文件**: `pubspec.yaml`

```yaml
dependencies:
  file_picker: ^8.1.0
```

**验证步骤**:
```bash
flutter pub get
flutter analyze
```

**验收标准**:
- [ ] 依赖安装成功
- [ ] 无分析错误

---

#### Task 1.2: 创建 DownloadPathManager 服务 (2-3小时)

**文件**: `lib/services/download/download_path_manager.dart`

**代码模板**:
```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/repositories/settings_repository.dart';

class DownloadPathManager {
  final SettingsRepository _settingsRepo;

  DownloadPathManager(this._settingsRepo);

  Future<bool> hasConfiguredPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir != null &&
           settings.customDownloadDir!.isNotEmpty;
  }

  Future<String?> selectDirectory(BuildContext context) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return null;

    if (!await _verifyWritePermission(selectedDirectory)) {
      if (context.mounted) {
        _showPermissionError(context);
      }
      return null;
    }
    return selectedDirectory;
  }

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

  Future<void> saveDownloadPath(String path) async {
    await _settingsRepo.updateCustomDownloadDir(path);
  }

  Future<String?> getCurrentDownloadPath() async {
    final settings = await _settingsRepo.get();
    return settings.customDownloadDir;
  }

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

**验收标准**:
- [ ] 文件创建在正确位置
- [ ] 所有方法实现完成
- [ ] 代码通过 `flutter analyze`

---

#### Task 1.3: 创建 Provider (30分钟)

**文件**: `lib/providers/download_path_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download/download_path_manager.dart';
import '../data/repositories/settings_repository.dart';

final downloadPathManagerProvider = Provider<DownloadPathManager>((ref) {
  return DownloadPathManager(ref.watch(settingsRepositoryProvider));
});

/// 下载路径状态 Provider
final downloadPathProvider = FutureProvider<String?>((ref) async {
  final manager = ref.watch(downloadPathManagerProvider);
  return manager.getCurrentDownloadPath();
});
```

**验收标准**:
- [ ] Provider 创建成功
- [ ] 导出正确

---

#### Task 1.4: 修改 DownloadService (2-3小时)

**文件**: `lib/services/download/download_service.dart`

**变更点**:

1. 添加依赖注入
```dart
class DownloadService with Logging {
  final DownloadRepository _downloadRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;
  final DownloadPathManager _pathManager;  // 新增

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
        _dio = Dio(...);
```

2. 修改 `_startDownload` 方法，下载完成时保存路径
```dart
// 下载完成，将临时文件重命名为正式文件
await tempFile.rename(savePath);

// 保存实际下载路径到 Track (新增)
await _trackRepository.addDownloadPath(track.id, task.playlistId, savePath);

// 保存元数据
await _saveMetadata(track, savePath, videoDetail: videoDetail, order: task.order);

// 更新任务状态为已完成
await _downloadRepository.updateTaskStatus(task.id, DownloadStatus.completed);
```

**验收标准**:
- [ ] 编译通过
- [ ] Provider 注入正确
- [ ] 下载路径在完成时保存

---

#### Task 1.5: 更新 Provider (1小时)

**文件**: `lib/providers/download/download_providers.dart`

```dart
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final downloadRepository = ref.watch(downloadRepositoryProvider);
  final trackRepository = ref.watch(trackRepositoryProvider);
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  final sourceManager = ref.watch(sourceManagerProvider);
  final pathManager = ref.watch(downloadPathManagerProvider);  // 新增

  return DownloadService(
    downloadRepository: downloadRepository,
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: sourceManager,
    pathManager: pathManager,  // 新增
  );
});
```

**验收标准**:
- [ ] Provider 更新正确
- [ ] 应用启动无错误

---

### Phase 1 验收标准

- [ ] `file_picker` 依赖添加成功
- [ ] `DownloadPathManager` 服务创建完成
- [ ] `downloadPathManagerProvider` 创建完成
- [ ] `DownloadService` 集成 `DownloadPathManager`
- [ ] 下载完成时路径保存到数据库
- [ ] 所有代码通过 `flutter analyze`

---

## Phase 2: UI 集成 (2-3天)

### 目标
在用户界面中集成路径选择流程

### 任务清单

#### Task 2.1: 创建路径配置引导对话框 (2-3小时)

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

    // 显示加载状态
    if (context.mounted) {
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final path = await pathManager.selectDirectory(context);

    // 关闭加载对话框
    if (context.mounted) {
      Navigator.pop(context);
    }

    if (path != null) {
      await pathManager.saveDownloadPath(path);
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    } else {
      // 用户取消，返回设置对话框
      if (context.mounted) {
        DownloadPathSetupDialog.show(context);
      }
    }
  }
}
```

**验收标准**:
- [ ] 对话框显示正确
- [ ] 选择目录流程正常
- [ ] 权限验证生效
- [ ] 路径成功保存

---

#### Task 2.2: 修改下载入口 - playlist_detail_page (2-3小时)

**文件**: `lib/ui/pages/library/playlist_detail_page.dart`

**变更**: 在所有下载方法开头添加路径检查

```dart
Future<void> _downloadSingleTrack(Track track, Playlist playlist) async {
  // 检查路径配置
  final pathManager = ref.read(downloadPathManagerProvider);
  if (!await pathManager.hasConfiguredPath()) {
    final configured = await DownloadPathSetupDialog.show(context);
    if (configured != true) return;
  }

  // 原有下载逻辑
  final downloadService = ref.read(downloadServiceProvider);
  await downloadService.addTrackDownload(
    track,
    fromPlaylist: playlist,
    order: playlist.trackIds.indexOf(track.id),
  );
}

Future<void> _downloadPlaylist(Playlist playlist) async {
  // 检查路径配置
  final pathManager = ref.read(downloadPathManagerProvider);
  if (!await pathManager.hasConfiguredPath()) {
    final configured = await DownloadPathSetupDialog.show(context);
    if (configured != true) return;
  }

  // 原有下载逻辑
  final downloadService = ref.read(downloadServiceProvider);
  await downloadService.addPlaylistDownload(playlist);
}
```

**验收标准**:
- [ ] 单曲下载前检查路径
- [ ] 歌单下载前检查路径
- [ ] 取消配置时不执行下载
- [ ] 配置后正常下载

---

#### Task 2.3: 修改其他下载入口 (1-2小时)

**文件列表**:
- `lib/ui/widgets/track_group/track_group.dart`
- `lib/ui/pages/search/search_page.dart`
- 其他有下载功能的页面

**统一变更模式**:
```dart
// 在下载方法开头添加
final pathManager = ref.read(downloadPathManagerProvider);
if (!await pathManager.hasConfiguredPath()) {
  final configured = await DownloadPathSetupDialog.show(context);
  if (configured != true) return;
}
```

**验收标准**:
- [ ] 所有下载入口统一处理
- [ ] 无遗漏的下载入口

---

#### Task 2.4: 设置页面添加下载路径配置 (2-3小时)

**文件**: `lib/ui/pages/settings/settings_page.dart`

**变更**:

1. 在设置列表中添加入口
```dart
// 在现有设置项后添加
Consumer(
  builder: (context, ref, _) {
    final downloadPathAsync = ref.watch(downloadPathProvider);
    final downloadPath = downloadPathAsync.value;

    return ListTile(
      leading: const Icon(Icons.folder),
      title: const Text('下载路径'),
      subtitle: Text(
        downloadPath ?? '未设置',
        style: TextStyle(
          color: downloadPath == null
            ? Theme.of(context).colorScheme.error
            : null,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDownloadPathOptions(context, ref),
    );
  },
),
```

2. 添加选项处理
```dart
void _showDownloadPathOptions(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('更改下载路径'),
            onTap: () {
              Navigator.pop(context);
              _changeDownloadPath(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('当前路径信息'),
            onTap: () {
              Navigator.pop(context);
              _showPathInfo(context, ref);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _changeDownloadPath(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
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

  if (confirmed == true && context.mounted) {
    await _executePathChange(context, ref);
  }
}

Future<void> _executePathChange(BuildContext context, WidgetRef ref) async {
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
  ref.invalidate(downloadPathProvider);

  if (context.mounted) {
    ToastService.show(context, '下载路径已更改');
  }
}

void _showPathInfo(BuildContext context, WidgetRef ref) {
  final downloadPath = ref.read(downloadPathProvider).value;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('下载路径信息'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前路径: ${downloadPath ?? "未设置"}'),
          if (downloadPath != null) ...[
            const SizedBox(height: 8),
            const Text('提示: 修改路径将清空数据库中的下载路径记录',
              style: TextStyle(fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
```

**验收标准**:
- [ ] 设置页显示下载路径
- [ ] 未设置时显示红色警告
- [ ] 可以更改下载路径
- [ ] 更改时显示确认对话框
- [ ] 更改后清空数据库路径

---

### Phase 2 验收标准

- [ ] `DownloadPathSetupDialog` 创建完成
- [ ] 所有下载入口集成路径检查
- [ ] 设置页面添加下载路径配置
- [ ] 首次下载显示引导对话框
- [ ] 路径配置后正常下载

---

## Phase 3: 简化下载标记逻辑 (1-2天)

### 目标
移除预计算路径，简化下载状态判断

### 任务清单

#### Task 3.1: 重构 TrackExtensions (2-3小时)

**文件**: `lib/core/extensions/track_extensions.dart`

**完整替换**:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 简化逻辑：有路径就认为已下载
  ///
  /// 注意：这假设路径有效。使用时如果文件不存在会自动清空。
  bool get isDownloaded => downloadPaths.isNotEmpty;

  /// 获取本地音频路径
  ///
  /// 尝试使用第一个有效路径，如果都不存在返回 null
  String? get localAudioPath {
    if (downloadPaths.isEmpty) return null;

    for (final downloadPath in downloadPaths) {
      try {
        if (File(downloadPath).existsSync()) {
          return downloadPath;
        }
      } catch (_) {
        // 路径无效，继续检查下一个
      }
    }
    return null;
  }

  /// 清理无效的下载路径
  ///
  /// 检查所有路径，移除不存在的
  /// 返回清理后的路径列表
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
  ///
  /// 遍历所有下载路径，返回第一个存在 cover.jpg 的路径
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
  ///
  /// 头像存储在 {baseDir}/avatars/{platform}/{creatorId}.jpg
  String? getLocalAvatarPath(String baseDir) {
    if (baseDir.isEmpty) return null;

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

  /// 是否有网络封面
  bool get hasNetworkCover => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;

  /// 格式化时长显示
  String get formattedDuration {
    if (durationMs == null) return '--:--';
    final minutes = durationMs! ~/ 60000;
    final seconds = (durationMs! % 60000) ~/ 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
```

**验收标准**:
- [ ] `isDownloaded` 简化为检查 `downloadPaths.isNotEmpty`
- [ ] `localAudioPath` 验证文件实际存在
- [ ] `validDownloadPaths` 方法添加
- [ ] 移除对 `FileExistsCache` 的依赖（部分移除）

---

#### Task 3.2: 更新 TrackRepository (2-3小时)

**文件**: `lib/data/repositories/track_repository.dart`

**添加方法**:

```dart
/// 添加下载路径
///
/// [trackId] Track ID
/// [playlistId] 歌单 ID，null 表示添加到通用列表
/// [path] 下载路径
Future<void> addDownloadPath(int trackId, int? playlistId, String path) async {
  final track = await getById(trackId);
  if (track == null) return;

  await isar.writeTxn(() async {
    if (playlistId != null) {
      // 添加到指定歌单
      final index = track.playlistIds.indexOf(playlistId);
      if (index >= 0) {
        // 更新现有路径
        final newPaths = List<String>.from(track.downloadPaths);
        newPaths[index] = path;
        track.downloadPaths = newPaths;
      } else {
        // 添加新歌单和路径
        track.playlistIds = List.from(track.playlistIds)..add(playlistId);
        track.downloadPaths = List.from(track.downloadPaths)..add(path);
      }
    } else {
      // 添加到通用列表 (playlistId = 0)
      if (!track.downloadPaths.contains(path)) {
        track.playlistIds = List.from(track.playlistIds)..add(0);
        track.downloadPaths = List.from(track.downloadPaths)..add(path);
      }
    }
    await isar.tracks.put(track);
  });
}

/// 清除指定歌单的下载路径
Future<void> clearDownloadPath(int trackId, int? playlistId) async {
  final track = await getById(trackId);
  if (track == null) return;

  await isar.writeTxn(() async {
    if (playlistId != null) {
      final index = track.playlistIds.indexOf(playlistId);
      if (index >= 0) {
        final newPlaylistIds = List<int>.from(track.playlistIds)..removeAt(index);
        final newDownloadPaths = List<String>.from(track.downloadPaths)..removeAt(index);
        track.playlistIds = newPlaylistIds;
        track.downloadPaths = newDownloadPaths;
      }
    } else {
      track.downloadPaths.clear();
      track.playlistIds.clear();
    }
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

/// 清理无效的下载路径
///
/// 检查数据库中的所有下载路径，移除不存在的
/// 返回清理的 Track 数量
Future<int> cleanupInvalidDownloadPaths() async {
  int cleaned = 0;

  await isar.writeTxn(() async {
    final tracks = await isar.tracks.where().findAll();
    for (final track in tracks) {
      final validPaths = <String>[];
      final validPlaylistIds = <int>[];

      for (int i = 0; i < track.downloadPaths.length; i++) {
        try {
          if (File(track.downloadPaths[i]).existsSync()) {
            validPaths.add(track.downloadPaths[i]);
            validPlaylistIds.add(track.playlistIds[i]);
          }
        } catch (_) {
          // 路径无效，跳过
        }
      }

      if (validPaths.length != track.downloadPaths.length) {
        track.downloadPaths = validPaths;
        track.playlistIds = validPlaylistIds;
        await isar.tracks.put(track);
        cleaned++;
      }
    }
  });

  return cleaned;
}
```

**验收标准**:
- [ ] `addDownloadPath` 方法实现
- [ ] `clearDownloadPath` 方法实现
- [ ] `clearAllDownloadPaths` 方法实现
- [ ] `cleanupInvalidDownloadPaths` 方法实现

---

#### Task 3.3: 移除预计算路径逻辑 (1-2小时)

**文件**: `lib/services/library/playlist_service.dart`

**查找并移除**:
```bash
# 搜索预计算路径的代码
grep -n "computeDownloadPath" lib/services/library/playlist_service.dart
grep -n "setDownloadPath" lib/services/library/playlist_service.dart
```

**移除类似代码**:
```dart
// 删除或注释掉
// final downloadPath = DownloadPathUtils.computeDownloadPath(...);
// track.setDownloadPath(playlist.id, downloadPath);
```

**验收标准**:
- [ ] 预计算路径逻辑移除
- [ ] 导入歌曲不设置下载路径
- [ ] 代码通过编译

---

### Phase 3 验收标准

- [ ] `TrackExtensions` 重构完成
- [ ] `TrackRepository` 新方法添加
- [ ] 预计算路径逻辑移除
- [ ] `isDownloaded` 简化为检查 `downloadPaths.isNotEmpty`

---

## Phase 4: 已下载页面刷新功能 (2天)

### 目标
实现从本地文件恢复下载状态

### 任务清单

#### Task 4.1: 创建 DownloadPathSyncService (3-4小时)

**文件**: `lib/services/download/download_path_sync_service.dart`

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../data/models/track.dart';
import '../../data/repositories/track_repository.dart';
import 'download_path_manager.dart';
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
  Future<(int updated, int orphans)> syncLocalFiles({
    void Function(int current, int total)? onProgress,
  }) async {
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
    int processed = 0;

    // 获取所有子文件夹
    final folders = baseDir.list().where((e) => e is Directory).toList();
    final total = folders.length;

    for (final entity in folders) {
      if (entity is Directory) {
        final result = await _syncFolder(entity);
        updated += result.$1;
        orphans += result.$2;

        processed++;
        onProgress?.call(processed, total);
      }
    }

    return (updated, orphans);
  }

  /// 同步单个文件夹
  Future<(int updated, int orphans)> _syncFolder(Directory folder) async {
    try {
      final tracks = await DownloadScanner.scanFolderForTracks(folder.path);
      int updated = 0;
      int orphans = 0;

      for (final scannedTrack in tracks) {
        final existingTrack = await _findMatchingTrack(scannedTrack);

        if (existingTrack != null) {
          final path = scannedTrack.downloadPaths.firstOrNull;
          if (path != null && !existingTrack.downloadPaths.contains(path)) {
            await _trackRepo.addDownloadPath(
              existingTrack.id,
              scannedTrack.playlistIds.firstOrNull,
              path,
            );
            updated++;
          }
        } else {
          orphans++;
        }
      }

      return (updated, orphans);
    } catch (_) {
      return (0, 0);
    }
  }

  /// 查找匹配的 Track
  ///
  /// 匹配规则：sourceId + cid + pageNum
  Future<Track?> _findMatchingTrack(Track scannedTrack) async {
    final tracks = await _trackRepo.getBySourceId(scannedTrack.sourceId);

    for (final track in tracks) {
      if (track.cid == scannedTrack.cid &&
          track.pageNum == scannedTrack.pageNum) {
        return track;
      }
    }

    return null;
  }

  /// 清理无效的下载路径
  Future<int> cleanupInvalidPaths() async {
    return await _trackRepo.cleanupInvalidDownloadPaths();
  }

  /// 获取孤儿文件列表
  ///
  /// 返回本地存在但数据库中没有匹配的文件信息
  Future<List<Map<String, dynamic>>> getOrphanFiles() async {
    final basePath = await _pathManager.getCurrentDownloadPath();
    if (basePath == null) return [];

    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) return [];

    final orphans = <Map<String, dynamic>>[];

    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        final tracks = await DownloadScanner.scanFolderForTracks(entity.path);
        for (final track in tracks) {
          final existingTrack = await _findMatchingTrack(track);
          if (existingTrack == null) {
            orphans.add({
              'title': track.title,
              'path': track.downloadPaths.firstOrNull,
              'sourceId': track.sourceId,
              'sourceType': track.sourceType.name,
            });
          }
        }
      }
    }

    return orphans;
  }
}
```

**验收标准**:
- [ ] 服务创建完成
- [ ] `syncLocalFiles` 方法实现
- [ ] 支持进度回调
- [ ] 孤儿文件检测

---

#### Task 4.2: 创建 SyncService Provider (30分钟)

**文件**: `lib/providers/download_path_sync_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/download/download_path_sync_service.dart';
import '../services/download/download_path_manager.dart';
import '../data/repositories/track_repository.dart';

final downloadPathSyncServiceProvider = Provider<DownloadPathSyncService>((ref) {
  return DownloadPathSyncService(
    ref.watch(trackRepositoryProvider),
    ref.watch(downloadPathManagerProvider),
  );
});
```

**验收标准**:
- [ ] Provider 创建完成
- [ ] 依赖注入正确

---

#### Task 4.3: 修改已下载页面 (3-4小时)

**文件**: `lib/ui/pages/library/downloaded_page.dart`

**变更**: 替换刷新功能

```dart
Future<void> _refreshAndSync() async {
  final syncService = ref.read(downloadPathSyncServiceProvider);

  // 显示进度对话框
  if (!mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SyncProgressDialog(
      onSync: (onProgress) async {
        return await syncService.syncLocalFiles(onProgress: onProgress);
      },
    ),
  );
}

class _SyncProgressDialog extends ConsumerStatefulWidget {
  final Future<(int, int)> Function(void Function(int, int)?) onSync;

  const _SyncProgressDialog({required this.onSync});

  @override
  ConsumerState<_SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends ConsumerState<_SyncProgressDialog> {
  int _current = 0;
  int _total = 1;
  String _status = '正在扫描...';

  @override
  void initState() {
    super.initState();
    _executeSync();
  }

  Future<void> _executeSync() async {
    try {
      final (updated, orphans) = await widget.onSync((current, total) {
        if (mounted) {
          setState(() {
            _current = current;
            _total = total;
            _status = '正在扫描 ($current/$total)...';
          });
        }
      });

      if (mounted) {
        Navigator.pop(context);

        // 刷新页面
        ref.invalidate(downloadedCategoriesProvider);

        // 显示结果
        _showResult(updated, orphans);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showError(e.toString());
      }
    }
  }

  void _showResult(int updated, int orphans) {
    ToastService.show(
      context,
      '同步完成: 更新 $updated 首${orphans > 0 ? ', 未匹配文件 $orphan 个' : ''}',
    );
  }

  void _showError(String error) {
    ToastService.show(context, '同步失败: $error');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('同步本地文件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(value: _total > 0 ? _current / _total : null),
          const SizedBox(height: 16),
          Text(_status),
        ],
      ),
    );
  }
}
```

**更新 AppBar**:
```dart
AppBar(
  title: const Text('已下载'),
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: '刷新并同步',
      onPressed: _refreshAndSync,
    ),
    IconButton(
      icon: const Icon(Icons.download),
      tooltip: '下载管理',
      onPressed: () => context.pushNamed(RouteNames.downloadManager),
    ),
  ],
),
```

**验收标准**:
- [ ] 刷新按钮调用同步功能
- [ ] 显示进度对话框
- [ ] 同步完成显示结果
- [ ] 错误处理正确

---

### Phase 4 验收标准

- [ ] `DownloadPathSyncService` 创建完成
- [ ] `downloadPathSyncServiceProvider` 创建完成
- [ ] 已下载页面刷新功能实现
- [ ] 同步进度显示正确
- [ ] 孤儿文件计数正确

---

## Phase 5: 修改下载路径处理 (1天)

### 目标
实现修改下载路径时清空数据库路径

### 任务清单

#### Task 5.1: 创建路径变更对话框 (2-3小时)

**文件**: `lib/ui/widgets/change_download_path_dialog.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/download_path_provider.dart';
import '../../providers/track_provider.dart';
import '../../core/services/toast_service.dart';

class ChangeDownloadPathDialog {
  /// 显示更改下载路径对话框
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    // 第一次确认
    final confirmed = await showDialog<bool>(
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

    if (confirmed != true || !context.mounted) return;

    // 执行路径变更
    await _executePathChange(context, ref);
  }

  static Future<void> _executePathChange(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final pathManager = ref.read(downloadPathManagerProvider);
    final trackRepo = ref.read(trackRepositoryProvider);

    // 显示加载状态
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      // 选择新路径
      final newPath = await pathManager.selectDirectory(context);

      // 关闭加载对话框
      if (context.mounted) Navigator.pop(context);

      if (newPath == null) return;

      // 清空所有下载路径
      await trackRepo.clearAllDownloadPaths();

      // 保存新路径
      await pathManager.saveDownloadPath(newPath);

      // 刷新相关 Provider
      if (context.mounted) {
        ref.invalidate(fileExistsCacheProvider);
        ref.invalidate(downloadedCategoriesProvider);
        ref.invalidate(downloadPathProvider);

        ToastService.show(context, '下载路径已更改，请点击刷新按钮扫描本地文件');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ToastService.show(context, '更改路径失败: $e');
      }
    }
  }
}
```

**验收标准**:
- [ ] 对话框显示正确
- [ ] 两次确认防止误操作
- [ ] 路径变更流程完整
- [ ] 刷新相关 Provider

---

#### Task 5.2: 集成到设置页面 (1小时)

**文件**: `lib/ui/pages/settings/settings_page.dart`

**更新 `_changeDownloadPath` 方法**:
```dart
Future<void> _changeDownloadPath(BuildContext context, WidgetRef ref) async {
  await ChangeDownloadPathDialog.show(context, ref);
}
```

**验收标准**:
- [ ] 设置页面调用新对话框
- [ ] 流程正常工作

---

### Phase 5 验收标准

- [ ] `ChangeDownloadPathDialog` 创建完成
- [ ] 路径变更时清空数据库
- [ ] 设置页面集成完成
- [ ] 用户提示清晰

---

## Phase 6: 清理和优化 (1天)

### 目标
移除不再需要的代码，优化现有逻辑

### 任务清单

#### Task 6.1: 简化 FileExistsCache (2小时)

**文件**: `lib/providers/download/file_exists_cache.dart`

**替换为简化版本**:

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文件存在检查缓存（简化版）
///
/// 主要用于 UI 层的图片加载优化，避免重复检查
class FileExistsCache extends StateNotifier<Set<String>> {
  FileExistsCache() : super({});

  /// 检查路径是否存在（带缓存）
  bool exists(String path) {
    if (state.contains(path)) return true;

    // 异步检查并缓存
    _checkAndCache(path);
    return false;
  }

  /// 批量预加载路径
  Future<void> preloadPaths(List<String> paths) async {
    final existing = <String>{};
    for (final path in paths) {
      try {
        if (await File(path).exists()) {
          existing.add(path);
        }
      } catch (_) {}
    }
    if (existing.isNotEmpty) {
      state = {...state, ...existing};
    }
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
      try {
        if (await File(path).exists()) {
          state = {...state, path};
        }
      } catch (_) {}
    });
  }
}

final fileExistsCacheProvider =
    StateNotifierProvider<FileExistsCache, Set<String>>((ref) {
  return FileExistsCache();
});
```

**验收标准**:
- [ ] 状态类型从 `Map<String, bool>` 改为 `Set<String>`
- [ ] 移除复杂的 Track 相关方法
- [ ] 保留图片加载优化功能

---

#### Task 6.2: 删除 PlaylistFolderMigrator (30分钟)

**文件**: `lib/services/download/playlist_folder_migrator.dart`

**操作**:
```bash
# 确认没有引用
grep -r "PlaylistFolderMigrator" lib/ --exclude-dir=.dart_tool

# 如果没有其他引用，删除文件
rm lib/services/download/playlist_folder_migrator.dart
```

**验收标准**:
- [ ] 确认无引用
- [ ] 文件已删除

---

#### Task 6.3: 清理未使用的导入和方法 (1小时)

**检查文件**:
- `lib/core/extensions/track_extensions.dart`
- `lib/providers/download/file_exists_cache.dart`
- `lib/ui/widgets/track_thumbnail.dart`

**移除对旧 FileExistsCache API 的引用**:
```dart
// 移除类似这样的调用
// final isDownloaded = cache.isDownloadedForPlaylist(track, playlistId);
// 改为
// final isDownloaded = track.isDownloaded;
```

**验收标准**:
- [ ] 所有编译错误修复
- [ ] 无未使用的导入

---

### Phase 6 验收标准

- [ ] `FileExistsCache` 简化完成
- [ ] `PlaylistFolderMigrator` 删除
- [ ] 无编译错误
- [ ] 代码通过 `flutter analyze`

---

## 测试阶段 (2-3天)

### 单元测试

#### Test 1: DownloadPathManager

**文件**: `test/services/download/download_path_manager_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:fmp/data/repositories/settings_repository.dart';

class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  group('DownloadPathManager', () {
    late DownloadPathManager manager;
    late MockSettingsRepository mockRepo;

    setUp(() {
      mockRepo = MockSettingsRepository();
      manager = DownloadPathManager(mockRepo);
    });

    test('hasConfiguredPath returns false when no path set', () async {
      when(mockRepo.get()).thenAnswer((_) async => Settings());
      expect(await manager.hasConfiguredPath(), false);
    });

    test('hasConfiguredPath returns true when path is set', () async {
      final settings = Settings()..customDownloadDir = '/test/path';
      when(mockRepo.get()).thenAnswer((_) async => settings);
      expect(await manager.hasConfiguredPath(), true);
    });
  });
}
```

#### Test 2: DownloadPathSyncService

**文件**: `test/services/download/download_path_sync_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/download/download_path_sync_service.dart';

void main() {
  group('DownloadPathSyncService', () {
    test('syncLocalFiles returns zero when path not configured', () async {
      // 测试未配置路径时的行为
    });

    test('syncLocalFiles matches tracks by sourceId and cid', () async {
      // 测试 Track 匹配逻辑
    });
  });
}
```

---

### 集成测试

#### 场景 1: 首次下载流程

```
步骤:
1. 启动应用
2. 进入歌单详情页
3. 点击下载按钮
4. 验证路径配置对话框显示
5. 点击"选择文件夹"
6. 选择一个目录
7. 验证下载开始
8. 验证下载完成
9. 验证路径已保存
```

#### 场景 2: 后续下载流程

```
步骤:
1. 确保已配置下载路径
2. 进入歌单详情页
3. 点击下载按钮
4. 验证直接开始下载（无配置对话框）
5. 验证文件保存到正确位置
```

#### 场景 3: 修改下载路径

```
步骤:
1. 进入设置页面
2. 点击"下载路径"
3. 选择"更改下载路径"
4. 验证确认对话框显示
5. 确认更改
6. 选择新路径
7. 验证数据库路径已清空
8. 验证新文件保存到新路径
```

#### 场景 4: 同步本地文件

```
步骤:
1. 确保下载目录有文件
2. 进入已下载页面
3. 点击刷新按钮
4. 验证扫描进度显示
5. 验证同步结果通知
6. 验证已下载列表更新
```

---

### 平台测试

#### Android 15+ 测试清单

- [ ] SAF 目录选择器正常显示
- [ ] 下载到选定目录成功
- [ ] 应用重启后路径仍然有效
- [ ] 撤销权限后正确提示
- [ ] 下载进度正常显示
- [ ] 后台下载正常工作

#### Windows 测试清单

- [ ] 文件夹选择对话框正常显示
- [ ] 下载到选定目录成功
- [ ] 路径持久化正常
- [ ] 下载进度正常显示

---

## 发布检查清单

### 代码质量

- [ ] 所有代码通过 `flutter analyze`
- [ ] 所有代码通过 `dart format`
- [ ] 无 TODO 标记（或已创建 Issue）
- [ ] 无调试用 `print` 语句

### 文档更新

- [ ] CLAUDE.md 更新
- [ ] Serena `download_system` 记忆更新
- [ ] CHANGELOG.md 添加变更记录

### 数据兼容性

- [ ] 现有用户数据不会丢失
- [ ] 现有下载路径保留（可选清理）
- [ ] 提供数据恢复方法

### 性能

- [ ] 大量文件同步不卡顿
- [ ] UI 响应流畅
- [ ] 内存使用正常

---

## 回滚计划

### 触发条件

1. Android 平台下载失败率超过 5%
2. 用户反馈无法访问已下载文件
3. 同步功能导致数据损坏
4. 其他严重问题影响使用

### 回滚步骤

1. **Git 回滚**:
   ```bash
   git revert <merge-commit-hash>
   git push origin main
   ```

2. **数据恢复**:
   - 从备份恢复 `downloadPaths`
   - 使用 `metadata.json` 重建路径信息

3. **用户通知**:
   - 发布公告说明问题
   - 提供临时解决方案

### 备份检查点

在实施前创建备份：

```bash
# 1. 备份当前代码
git tag backup-before-download-path-refactor

# 2. 备份数据库
# 在应用中添加导出功能
```

---

## 附录

### A. 相关 Issue

- Issue #XXX: Android 下载失败问题
- Issue #XXX: 自定义下载路径需求

### B. 相关文档

- [计划文档](./custom_download_path_plan.md)
- [下载系统文档](./download_system.md)
- [file_picker 文档](https://pub.dev/packages/file_picker)

### C. 变更历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| 1.0 | 2026-01-22 | 初始版本 |
