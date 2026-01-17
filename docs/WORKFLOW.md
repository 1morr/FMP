# Flutter Music Player (FMP) - 实现工作流

> 版本: 1.0.0
> 创建日期: 2026-01-03
> 最后更新: 2026-01-17
> 基于: PRD.md, TECHNICAL_SPEC.md

---

## 进度追踪

| Phase | 名称 | 状态 | 完成日期 |
|-------|------|------|----------|
| Phase 1 | 基础架构 | ✅ 已完成 | 2026-01-03 |
| Phase 2 | 核心播放 | ✅ 已完成 | 2026-01-03 |
| Phase 3 | 音乐库 | ✅ 已完成 | 2026-01-03 |
| Phase 4 | 完整 UI | 🔄 进行中 | - |
| Phase 5 | 平台特性 | 🔄 进行中 | - |
| Phase 6 | 优化与完善 | ⏳ 待开始 | - |

**当前里程碑**: Milestone 3 (可发布) 🔄 进行中

---

## 设计规范

| 项目 | 规范 |
|------|------|
| **UI 框架** | Material Design 3 (Material You) |
| **组件库** | Flutter Material Components |
| **图标** | Material Icons / Material Symbols |
| **动画** | Material Motion |
| **主题** | Dynamic Color + Custom Color Scheme |

---

## 测试策略

> ⚠️ **重要**: 每完成一个 Phase，必须运行程序进行测试验证

| 阶段 | 测试命令 | 验收标准 |
|------|----------|----------|
| Phase 1 | `flutter run -d windows` | 应用启动，显示空白 Shell |
| Phase 2 | `flutter run -d windows` | 可播放 B站音频 |
| Phase 3 | `flutter run -d android` | 歌单管理正常 |
| Phase 4 | `flutter run -d windows` + `flutter run -d android` | UI 响应式正常 |
| Phase 5 | 分别测试 Android/Windows | 平台特性正常 |
| Phase 6 | 全面测试 | 性能达标，无明显 bug |

---

## 工作流概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FMP 实现工作流                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Phase 1: 基础架构          Phase 2: 核心播放          Phase 3: 音乐库        │
│  ━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━         │
│  [1.1] 项目初始化    ──→   [2.1] 音频服务     ──→   [3.1] 歌单管理          │
│  [1.2] 数据模型      ──→   [2.2] 播放队列     ──→   [3.2] 外部导入          │
│  [1.3] 核心架构      ──→   [2.3] B站音源      ──→   [3.3] 搜索功能          │
│           │                      │                        │                 │
│           ▼                      ▼                        ▼                 │
│  Phase 4: 完整 UI           Phase 5: 平台特性        Phase 6: 优化            │
│  ━━━━━━━━━━━━━━━            ━━━━━━━━━━━━━━━━        ━━━━━━━━━━              │
│  [4.1] 响应式布局    ──→   [5.1] Android 后台  ──→  [6.1] 性能优化          │
│  [4.2] 主题系统      ──→   [5.2] Windows 托盘  ──→  [6.2] 缓存优化          │
│  [4.3] 所有页面      ──→   [5.3] YouTube 音源  ──→  [6.3] 最终测试          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: 基础架构 (Foundation)

### 1.1 项目初始化

**目标**: 创建 Flutter 项目并配置开发环境

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 1.1.1 | 创建 Flutter 项目 | - | P0 | 低 |
| 1.1.2 | 配置 pubspec.yaml 依赖 | 1.1.1 | P0 | 低 |
| 1.1.3 | 设置目录结构 | 1.1.1 | P0 | 低 |
| 1.1.4 | 配置 Android 清单文件 | 1.1.2 | P0 | 中 |
| 1.1.5 | 配置 Windows 项目设置 | 1.1.2 | P0 | 中 |
| 1.1.6 | 设置代码格式化和 lint | 1.1.1 | P1 | 低 |

#### 1.1.1 创建 Flutter 项目

```bash
flutter create --org com.personal --project-name fmp flutter_music_player
cd flutter_music_player
```

#### 1.1.2 配置 pubspec.yaml

```yaml
name: fmp
description: Flutter Music Player - 跨平台音乐播放器
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Material Design 3
  material_color_utilities: ^0.11.0
  dynamic_color: ^1.6.0

  # 状态管理
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.3.0

  # 本地存储
  isar: ^3.1.0
  isar_flutter_libs: ^3.1.0
  path_provider: ^2.1.0

  # 音频播放
  just_audio: ^0.9.36
  just_audio_background: ^0.0.1-beta.11
  audio_session: ^0.1.18

  # 网络
  dio: ^5.4.0

  # 路由
  go_router: ^13.0.0

  # UI
  cached_network_image: ^3.3.0
  flutter_reorderable_list: ^1.3.0

  # 桌面平台
  tray_manager: ^0.2.0
  window_manager: ^0.3.7
  hotkey_manager: ^0.2.0

  # 工具
  logger: ^2.0.2
  file_picker: ^6.1.1
  permission_handler: ^11.1.0
  uuid: ^4.2.0
  collection: ^1.18.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  riverpod_generator: ^2.3.0
  isar_generator: ^3.1.0
  flutter_lints: ^3.0.0
```

#### 1.1.3 设置目录结构

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/
│   ├── extensions/
│   ├── utils/
│   └── errors/
├── data/
│   ├── models/
│   ├── repositories/
│   └── sources/
├── services/
│   ├── audio/
│   ├── download/
│   ├── search/
│   ├── import/
│   └── platform/
├── providers/
├── ui/
│   ├── pages/
│   ├── widgets/
│   ├── layouts/
│   └── theme/
└── platform/
```

**验收标准**:
- [x] `flutter run` 可在 Android 模拟器成功运行
- [x] `flutter run -d windows` 可在 Windows 成功运行
- [x] 所有依赖正确安装无冲突

> ✅ **Phase 1.1 完成** - 项目结构已建立，所有依赖已配置

---

### 1.2 数据模型

**目标**: 实现 Isar 数据模型和基础 Repository

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 1.2.1 | 定义 Track 模型 | 1.1.2 | P0 | 中 |
| 1.2.2 | 定义 Playlist 模型 | 1.1.2 | P0 | 中 |
| 1.2.3 | 定义 PlayQueue 模型 | 1.1.2 | P0 | 中 |
| 1.2.4 | 定义 Settings 模型 | 1.1.2 | P0 | 低 |
| 1.2.5 | 定义 SearchHistory 模型 | 1.1.2 | P1 | 低 |
| 1.2.6 | 定义 DownloadTask 模型 | 1.1.2 | P1 | 低 |
| 1.2.7 | 实现 Isar 初始化 | 1.2.1-6 | P0 | 中 |
| 1.2.8 | 运行 build_runner 生成代码 | 1.2.7 | P0 | 低 |

#### 1.2.1 Track 模型实现

**文件**: `lib/data/models/track.dart`

```dart
import 'package:isar/isar.dart';

part 'track.g.dart';

enum SourceType { bilibili, youtube }

@collection
class Track {
  Id id = Isar.autoIncrement;

  @Index()
  late String sourceId;

  @Index()
  @Enumerated(EnumType.name)
  late SourceType sourceType;

  late String title;
  String? artist;
  int? durationMs;
  String? thumbnailUrl;

  String? audioUrl;
  DateTime? audioUrlExpiry;

  bool isAvailable = true;
  String? unavailableReason;

  String? cachedPath;
  String? downloadedPath;

  DateTime createdAt = DateTime.now();
  DateTime? updatedAt;

  @Index(composite: [CompositeIndex('sourceType')])
  String get sourceKey => '${sourceType.name}:$sourceId';

  bool get hasValidAudioUrl {
    if (audioUrl == null) return false;
    if (audioUrlExpiry == null) return true;
    return DateTime.now().isBefore(audioUrlExpiry!);
  }

  bool get isDownloaded => downloadedPath != null;
  bool get isCached => cachedPath != null;
}
```

**验收标准**:
- [x] `flutter pub run build_runner build` 成功生成 `.g.dart` 文件
- [x] Isar 数据库可正确初始化
- [x] 基本 CRUD 操作测试通过

> ✅ **Phase 1.2 完成** - 所有数据模型已实现: Track, Playlist, PlayQueue, Settings, SearchHistory, DownloadTask

---

### 1.3 核心架构

**目标**: 搭建 Riverpod Provider 架构和基础服务

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 1.3.1 | 创建 DatabaseProvider | 1.2.8 | P0 | 低 |
| 1.3.2 | 创建 TrackRepository | 1.3.1 | P0 | 中 |
| 1.3.3 | 创建 PlaylistRepository | 1.3.1 | P0 | 中 |
| 1.3.4 | 创建 QueueRepository | 1.3.1 | P0 | 中 |
| 1.3.5 | 创建 SettingsRepository | 1.3.1 | P0 | 低 |
| 1.3.6 | 设置 Go Router 基础路由 | 1.1.3 | P0 | 中 |
| 1.3.7 | 创建 App Shell 框架 | 1.3.6 | P0 | 中 |

#### 1.3.1 DatabaseProvider

**文件**: `lib/providers/database_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../data/models/track.dart';
import '../data/models/playlist.dart';
import '../data/models/play_queue.dart';
import '../data/models/settings.dart';
import '../data/models/search_history.dart';
import '../data/models/download_task.dart';

final databaseProvider = FutureProvider<Isar>((ref) async {
  final dir = await getApplicationDocumentsDirectory();

  return await Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      PlayQueueSchema,
      SettingsSchema,
      SearchHistorySchema,
      DownloadTaskSchema,
    ],
    directory: dir.path,
    name: 'fmp_database',
  );
});
```

**验收标准**:
- [x] Provider 正确提供 Isar 实例
- [x] Repository 模式正确实现
- [x] 路由可在页面间正确导航

> ✅ **Phase 1.3 完成** - DatabaseProvider, 所有 Repository, GoRouter, AppShell 已实现

---

## Phase 2: 核心播放 (Core Playback)

### 2.1 音频服务

**目标**: 实现完整的音频播放能力

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 2.1.1 | 创建 AudioService 基础结构 | 1.3.1 | P0 | 高 |
| 2.1.2 | 实现播放/暂停/停止 | 2.1.1 | P0 | 中 |
| 2.1.3 | 实现进度控制 (seek) | 2.1.1 | P0 | 中 |
| 2.1.4 | 实现快进快退 (±10秒) | 2.1.3 | P0 | 低 |
| 2.1.5 | 实现播放速度控制 | 2.1.1 | P0 | 低 |
| 2.1.6 | 实现播放模式切换 | 2.1.1 | P0 | 中 |
| 2.1.7 | 实现音量控制 | 2.1.1 | P1 | 低 |
| 2.1.8 | 创建 AudioProvider | 2.1.1-7 | P0 | 中 |
| 2.1.9 | 实现播放状态流 | 2.1.8 | P0 | 中 |

#### 2.1.1 AudioService 核心实现

**文件**: `lib/services/audio/audio_service.dart`

```dart
import 'package:just_audio/just_audio.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  // 状态流
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  // 当前状态
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get speed => _player.speed;

  ConcatenatingAudioSource? _playlist;

  Future<void> dispose() async {
    await _player.dispose();
  }

  // 播放控制
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  Future<void> seekTo(Duration position) => _player.seek(position);
  Future<void> seekToIndex(int index) => _player.seek(Duration.zero, index: index);
  Future<void> seekToNext() => _player.seekToNext();
  Future<void> seekToPrevious() => _player.seekToPrevious();

  // 快进快退
  Future<void> seekForward([Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = _player.position + duration;
    final maxPosition = _player.duration ?? Duration.zero;
    await _player.seek(newPosition > maxPosition ? maxPosition : newPosition);
  }

  Future<void> seekBackward([Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = _player.position - duration;
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  // 播放速度
  Future<void> setSpeed(double speed) => _player.setSpeed(speed.clamp(0.5, 2.0));

  // 播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    switch (mode) {
      case PlayMode.sequential:
        await _player.setLoopMode(LoopMode.off);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.loop:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.loopOne:
        await _player.setLoopMode(LoopMode.one);
        await _player.setShuffleModeEnabled(false);
        break;
      case PlayMode.shuffle:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(true);
        break;
    }
  }

  // 音量
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));
}
```

**验收标准**:
- [x] 可播放网络音频 URL
- [x] 播放/暂停/停止正常工作
- [x] 进度控制正常工作
- [x] 播放模式切换正常工作

> ✅ **Phase 2.1 完成** - AudioService 完整实现，集成 just_audio + just_audio_windows

---

### 2.2 播放队列

**目标**: 实现支持上千首歌曲的持久化播放队列

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 2.2.1 | 实现队列初始化与加载 | 2.1.8 | P0 | 中 |
| 2.2.2 | 实现添加歌曲到队列 | 2.2.1 | P0 | 中 |
| 2.2.3 | 实现移除歌曲 | 2.2.1 | P0 | 低 |
| 2.2.4 | 实现拖拽排序 | 2.2.1 | P0 | 中 |
| 2.2.5 | 实现随机打乱 | 2.2.1 | P0 | 中 |
| 2.2.6 | 实现队列持久化 | 2.2.1 | P0 | 中 |
| 2.2.7 | 实现断点续播 | 2.2.6 | P0 | 中 |
| 2.2.8 | 创建 QueueProvider | 2.2.1-7 | P0 | 中 |

#### 2.2.1 队列管理实现

**文件**: `lib/services/audio/queue_manager.dart`

```dart
import 'package:just_audio/just_audio.dart';
import '../../data/models/track.dart';
import '../../data/models/play_queue.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/track_repository.dart';

class QueueManager {
  final AudioPlayer _player;
  final QueueRepository _queueRepository;
  final TrackRepository _trackRepository;

  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  List<Track> _tracks = [];
  PlayQueue? _currentQueue;

  List<Track> get tracks => List.unmodifiable(_tracks);
  int get length => _tracks.length;
  int? get currentIndex => _player.currentIndex;
  Track? get currentTrack =>
    currentIndex != null && currentIndex! < _tracks.length
      ? _tracks[currentIndex!]
      : null;

  QueueManager({
    required AudioPlayer player,
    required QueueRepository queueRepository,
    required TrackRepository trackRepository,
  }) : _player = player,
       _queueRepository = queueRepository,
       _trackRepository = trackRepository;

  /// 初始化队列（从持久化存储加载）
  Future<void> initialize() async {
    _currentQueue = await _queueRepository.getOrCreate();

    if (_currentQueue!.trackIds.isNotEmpty) {
      _tracks = await _trackRepository.getByIds(_currentQueue!.trackIds);
      await _rebuildPlaylist();

      // 恢复播放位置
      if (_currentQueue!.currentIndex < _tracks.length) {
        await _player.seek(
          Duration(milliseconds: _currentQueue!.lastPositionMs),
          index: _currentQueue!.currentIndex,
        );
      }
    }
  }

  /// 添加歌曲到队列末尾
  Future<void> add(Track track) async {
    _tracks.add(track);
    await _playlist.add(_createAudioSource(track));
    await _persistQueue();
  }

  /// 添加多首歌曲
  Future<void> addAll(List<Track> tracks) async {
    _tracks.addAll(tracks);
    await _playlist.addAll(tracks.map(_createAudioSource).toList());
    await _persistQueue();
  }

  /// 插入歌曲到指定位置
  Future<void> insert(int index, Track track) async {
    _tracks.insert(index, track);
    await _playlist.insert(index, _createAudioSource(track));
    await _persistQueue();
  }

  /// 移除指定位置的歌曲
  Future<void> removeAt(int index) async {
    _tracks.removeAt(index);
    await _playlist.removeAt(index);
    await _persistQueue();
  }

  /// 移动歌曲位置
  Future<void> move(int oldIndex, int newIndex) async {
    final track = _tracks.removeAt(oldIndex);
    _tracks.insert(newIndex, track);
    await _playlist.move(oldIndex, newIndex);
    await _persistQueue();
  }

  /// 随机打乱队列
  Future<void> shuffle() async {
    // 保存原始顺序用于恢复
    _currentQueue!.originalOrder = _tracks.map((t) => t.id).toList();

    // 保持当前播放的歌曲在第一位
    final currentTrack = this.currentTrack;
    _tracks.shuffle();

    if (currentTrack != null) {
      _tracks.remove(currentTrack);
      _tracks.insert(0, currentTrack);
    }

    await _rebuildPlaylist();
    await _persistQueue();
  }

  /// 清空队列
  Future<void> clear() async {
    _tracks.clear();
    await _playlist.clear();
    await _persistQueue();
  }

  /// 持久化队列状态
  Future<void> _persistQueue() async {
    _currentQueue!.trackIds = _tracks.map((t) => t.id).toList();
    _currentQueue!.currentIndex = _player.currentIndex ?? 0;
    _currentQueue!.lastPositionMs = _player.position.inMilliseconds;
    _currentQueue!.lastUpdated = DateTime.now();
    await _queueRepository.save(_currentQueue!);
  }

  /// 保存当前播放位置
  Future<void> savePosition() async {
    if (_currentQueue != null) {
      _currentQueue!.currentIndex = _player.currentIndex ?? 0;
      _currentQueue!.lastPositionMs = _player.position.inMilliseconds;
      await _queueRepository.save(_currentQueue!);
    }
  }

  AudioSource _createAudioSource(Track track) {
    return AudioSource.uri(
      Uri.parse(track.audioUrl ?? ''),
      tag: MediaItem(
        id: track.id.toString(),
        title: track.title,
        artist: track.artist,
        artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      ),
    );
  }

  Future<void> _rebuildPlaylist() async {
    _playlist = ConcatenatingAudioSource(
      children: _tracks.map(_createAudioSource).toList(),
    );
    await _player.setAudioSource(_playlist);
  }
}
```

**验收标准**:
- [x] 队列可持久化并在重启后恢复
- [x] 支持添加/移除/移动歌曲
- [x] 拖拽排序正常工作
- [x] 断点续播位置精确到秒

> ✅ **Phase 2.2 完成** - QueueManager 已实现，支持持久化和断点续播

---

### 2.3 B站音源

**目标**: 实现 Bilibili 音源解析

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 2.3.1 | 创建 BaseSource 抽象类 | 1.3.1 | P0 | 低 |
| 2.3.2 | 实现 BV号解析 | 2.3.1 | P0 | 低 |
| 2.3.3 | 实现视频信息获取 | 2.3.2 | P0 | 中 |
| 2.3.4 | 实现音频流 URL 获取 | 2.3.3 | P0 | 高 |
| 2.3.5 | 实现搜索功能 | 2.3.1 | P0 | 中 |
| 2.3.6 | 实现收藏夹解析 | 2.3.3 | P1 | 中 |
| 2.3.7 | 实现 URL 过期刷新机制 | 2.3.4 | P0 | 中 |

#### 2.3.1 BaseSource 抽象类

**文件**: `lib/data/sources/base_source.dart`

```dart
import '../models/track.dart';

abstract class BaseSource {
  SourceType get sourceType;

  /// 从 URL 解析出 ID
  String? parseId(String url);

  /// 验证 ID 格式
  bool isValidId(String id);

  /// 获取歌曲信息
  Future<Track> getTrackInfo(String sourceId);

  /// 获取音频流 URL（可能会过期）
  Future<String> getAudioUrl(String sourceId);

  /// 刷新音频 URL（如果过期）
  Future<Track> refreshAudioUrl(Track track);

  /// 搜索
  Future<List<Track>> search(String query, {int page = 1, int pageSize = 20});

  /// 解析播放列表/收藏夹
  Future<List<Track>> parsePlaylist(String playlistUrl);
}
```

#### 2.3.4 Bilibili 音频 URL 获取

**文件**: `lib/data/sources/bilibili_source.dart`

```dart
import 'package:dio/dio.dart';
import '../models/track.dart';
import 'base_source.dart';

class BilibiliSource extends BaseSource {
  final Dio _dio = Dio();

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String? parseId(String url) {
    // 支持多种 URL 格式
    // https://www.bilibili.com/video/BV1xx411c7mD
    // https://b23.tv/BV1xx411c7mD
    final regex = RegExp(r'BV[a-zA-Z0-9]{10}');
    final match = regex.firstMatch(url);
    return match?.group(0);
  }

  @override
  bool isValidId(String id) {
    return RegExp(r'^BV[a-zA-Z0-9]{10}$').hasMatch(id);
  }

  @override
  Future<Track> getTrackInfo(String bvid) async {
    final response = await _dio.get(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: {'bvid': bvid},
    );

    if (response.data['code'] != 0) {
      throw Exception('Failed to get video info: ${response.data['message']}');
    }

    final data = response.data['data'];
    final track = Track()
      ..sourceId = bvid
      ..sourceType = SourceType.bilibili
      ..title = data['title']
      ..artist = data['owner']['name']
      ..durationMs = (data['duration'] as int) * 1000
      ..thumbnailUrl = data['pic'];

    // 获取音频 URL
    final audioUrl = await getAudioUrl(bvid);
    track.audioUrl = audioUrl;
    track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 2));

    return track;
  }

  @override
  Future<String> getAudioUrl(String bvid) async {
    // 1. 先获取 cid
    final viewResponse = await _dio.get(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: {'bvid': bvid},
    );

    final cid = viewResponse.data['data']['cid'];

    // 2. 获取播放 URL
    final playUrlResponse = await _dio.get(
      'https://api.bilibili.com/x/player/playurl',
      queryParameters: {
        'bvid': bvid,
        'cid': cid,
        'fnval': 16,  // 请求 DASH 格式
        'qn': 0,      // 最高画质
        'fourk': 1,
      },
    );

    if (playUrlResponse.data['code'] != 0) {
      throw Exception('Failed to get audio URL');
    }

    final dash = playUrlResponse.data['data']['dash'];
    final audios = dash['audio'] as List;

    // 选择最高音质
    audios.sort((a, b) => (b['bandwidth'] as int).compareTo(a['bandwidth'] as int));

    return audios.first['baseUrl'] as String;
  }

  @override
  Future<Track> refreshAudioUrl(Track track) async {
    final audioUrl = await getAudioUrl(track.sourceId);
    track.audioUrl = audioUrl;
    track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 2));
    track.updatedAt = DateTime.now();
    return track;
  }

  @override
  Future<List<Track>> search(String query, {int page = 1, int pageSize = 20}) async {
    final response = await _dio.get(
      'https://api.bilibili.com/x/web-interface/search/type',
      queryParameters: {
        'keyword': query,
        'search_type': 'video',
        'page': page,
        'page_size': pageSize,
      },
    );

    if (response.data['code'] != 0) {
      return [];
    }

    final results = response.data['data']['result'] as List? ?? [];

    return results.map((item) {
      return Track()
        ..sourceId = item['bvid']
        ..sourceType = SourceType.bilibili
        ..title = _cleanHtmlTags(item['title'])
        ..artist = item['author']
        ..durationMs = _parseDuration(item['duration'])
        ..thumbnailUrl = 'https:${item['pic']}';
    }).toList();
  }

  @override
  Future<List<Track>> parsePlaylist(String favUrl) async {
    // 解析收藏夹 ID
    final regex = RegExp(r'fid=(\d+)|ml(\d+)');
    final match = regex.firstMatch(favUrl);
    if (match == null) {
      throw Exception('Invalid favorites URL');
    }

    final fid = match.group(1) ?? match.group(2);

    final response = await _dio.get(
      'https://api.bilibili.com/x/v3/fav/resource/list',
      queryParameters: {
        'media_id': fid,
        'pn': 1,
        'ps': 20,
      },
    );

    if (response.data['code'] != 0) {
      throw Exception('Failed to get favorites: ${response.data['message']}');
    }

    final medias = response.data['data']['medias'] as List? ?? [];

    return medias.map((item) {
      return Track()
        ..sourceId = item['bvid']
        ..sourceType = SourceType.bilibili
        ..title = item['title']
        ..artist = item['upper']['name']
        ..durationMs = (item['duration'] as int) * 1000
        ..thumbnailUrl = item['cover'];
    }).toList();
  }

  String _cleanHtmlTags(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  int _parseDuration(String duration) {
    // 格式: "3:45" 或 "1:23:45"
    final parts = duration.split(':').map(int.parse).toList();
    if (parts.length == 2) {
      return (parts[0] * 60 + parts[1]) * 1000;
    } else if (parts.length == 3) {
      return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
    }
    return 0;
  }
}
```

**验收标准**:
- [x] 可从 B站 URL 解析 BV 号
- [x] 可获取视频信息（标题、作者、时长、封面）
- [x] 可获取音频流 URL 并播放
- [x] 搜索功能正常工作

> ✅ **Phase 2.3 完成** - BilibiliSource 已实现，支持 BV 解析、信息获取、音频流提取、搜索

---

## Phase 3: 音乐库 (Library)

### 3.1 歌单管理

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 3.1.1 | 实现创建歌单 | 1.2.2 | P0 | 低 |
| 3.1.2 | 实现删除歌单 | 3.1.1 | P0 | 低 |
| 3.1.3 | 实现重命名歌单 | 3.1.1 | P0 | 低 |
| 3.1.4 | 实现添加歌曲到歌单 | 3.1.1 | P0 | 中 |
| 3.1.5 | 实现从歌单移除歌曲 | 3.1.1 | P0 | 低 |
| 3.1.6 | 实现自定义封面 | 3.1.1 | P1 | 中 |
| 3.1.7 | 创建 PlaylistProvider | 3.1.1-6 | P0 | 中 |

**验收标准**:
- [x] 可创建/删除/重命名歌单
- [x] 可添加/移除歌曲
- [x] 歌单封面自动从首首歌曲获取

> ✅ **Phase 3.1 完成** - PlaylistService 和 PlaylistProvider 已实现

### 3.2 外部导入

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 3.2.1 | 实现 URL 解析识别 | 2.3.1 | P0 | 中 |
| 3.2.2 | 实现 B站收藏夹导入 | 2.3.6 | P0 | 中 |
| 3.2.3 | 实现导入进度显示 | 3.2.2 | P0 | 低 |
| 3.2.4 | 实现定时刷新机制 | 3.2.2 | P1 | 高 |
| 3.2.5 | 实现刷新通知 | 3.2.4 | P1 | 中 |
| 3.2.6 | 实现同步删除 | 3.2.4 | P1 | 中 |
| 3.2.7 | 实现导出功能 | 3.1.1 | P2 | 中 |

**验收标准**:
- [x] 可从 B站收藏夹 URL 导入
- [x] 导入进度实时显示
- [x] 支持刷新导入的歌单

> ✅ **Phase 3.2 完成** - ImportService 已实现，支持 URL 解析、进度流、刷新机制

### 3.3 搜索功能

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 3.3.1 | 实现多源搜索服务 | 2.3.5 | P0 | 中 |
| 3.3.2 | 实现搜索结果聚合 | 3.3.1 | P0 | 中 |
| 3.3.3 | 实现音源筛选 | 3.3.2 | P0 | 低 |
| 3.3.4 | 实现搜索历史存储 | 1.2.5 | P1 | 低 |
| 3.3.5 | 实现搜索历史展示 | 3.3.4 | P1 | 低 |
| 3.3.6 | 创建 SearchProvider | 3.3.1-5 | P0 | 中 |

**验收标准**:
- [x] 多源搜索正常工作
- [x] 本地和在线结果分离显示
- [x] 搜索历史保存和展示

> ✅ **Phase 3.3 完成** - SearchService 和 SearchProvider 已实现

---

## Phase 4: 完整 UI

### 4.1 响应式布局

| 任务 ID | 任务名称 | 依赖 | 优先级 | 状态 |
|---------|----------|------|--------|------|
| 4.1.1 | 定义响应式断点 | 1.3.7 | P0 | ✅ |
| 4.1.2 | 实现 MobileLayout | 4.1.1 | P0 | ✅ |
| 4.1.3 | 实现 TabletLayout | 4.1.1 | P1 | ✅ |
| 4.1.4 | 实现 DesktopLayout | 4.1.1 | P0 | ✅ |
| 4.1.5 | 实现 ResponsiveScaffold | 4.1.2-4 | P0 | ✅ |

**验收标准**:
- [x] 移动端 (<600dp) 显示底部导航栏
- [x] 桌面端 (>1200dp) 显示侧边栏 + 右侧面板
- [x] 平板端 (600-1200dp) 显示侧边导航
- [x] 窗口大小变化时布局自动切换

> ✅ **Phase 4.1 已完成** - ResponsiveScaffold 已实现，支持移动端、平板端和桌面端布局

### 4.2 主题系统

| 任务 ID | 任务名称 | 依赖 | 优先级 | 状态 |
|---------|----------|------|--------|------|
| 4.2.1 | 定义浅色主题 | 1.2.4 | P0 | ✅ |
| 4.2.2 | 定义深色主题 | 1.2.4 | P0 | ✅ |
| 4.2.3 | 实现主题切换 | 4.2.1-2 | P0 | ✅ |
| 4.2.4 | 实现自定义颜色 | 4.2.3 | P1 | ✅ |
| 4.2.5 | 实现颜色选择器 UI | 4.2.4 | P1 | ✅ |
| 4.2.6 | 创建 ThemeProvider | 4.2.1-5 | P0 | ✅ |

**验收标准**:
- [x] 支持浅色/深色/跟随系统三种模式
- [x] 主题切换即时生效，无需重启
- [x] 自定义主题色可选择
- [x] 主题设置持久化保存

> ✅ **Phase 4.2 已完成** - app_theme.dart + themeProvider 已实现

### 4.3 所有页面

| 任务 ID | 任务名称 | 依赖 | 优先级 | 状态 |
|---------|----------|------|--------|------|
| 4.3.1 | 实现首页 | 4.1.5 | P0 | ✅ |
| 4.3.2 | 实现搜索页 | 3.3.6, 4.1.5 | P0 | ✅ |
| 4.3.3 | 实现播放器页 | 2.1.8, 4.1.5 | P0 | ✅ |
| 4.3.4 | 实现迷你播放器 | 4.3.3 | P0 | ✅ |
| 4.3.5 | 实现播放队列页 | 2.2.8, 4.1.5 | P0 | ✅ |
| 4.3.6 | 实现音乐库页 | 3.1.7, 4.1.5 | P0 | ✅ |
| 4.3.7 | 实现歌单详情页 | 4.3.6 | P0 | ✅ |
| 4.3.8 | 实现设置页 | 4.2.6, 4.1.5 | P0 | ✅ |
| 4.3.9 | 实现缓存设置页 | 4.3.8 | P1 | ✅ |
| 4.3.10 | 实现下载管理页 | 4.3.8 | P1 | ⏳ |

**验收标准**:
- [x] 所有核心页面可正常导航
- [x] 播放器页支持手势控制和进度拖拽
- [x] 迷你播放器显示当前歌曲信息和控制按钮
- [x] 队列页支持拖拽排序
- [x] 设置页可修改主题和缓存设置
- [x] 缓存设置支持查看大小、设置上限、清除缓存
- [ ] 下载管理页显示下载任务和进度

> 🔄 **Phase 4.3 大部分完成** - 核心页面已实现，下载管理待实现

---

## Phase 5: 平台特性

### 5.1 Android 后台播放

| 任务 ID | 任务名称 | 依赖 | 优先级 | 状态 |
|---------|----------|------|--------|------|
| 5.1.1 | 配置 AndroidManifest | 2.1.1 | P0 | ✅ |
| 5.1.2 | 集成 just_audio_background | 5.1.1 | P0 | ✅ |
| 5.1.3 | 实现通知栏控制（含上下首） | 5.1.2 | P0 | ✅ |
| 5.1.4 | 实现锁屏控制 | 5.1.2 | P1 | ✅ |
| 5.1.5 | 测试后台播放稳定性 | 5.1.3 | P0 | 🔄 |

**验收标准**:
- [x] 应用切到后台后音频继续播放
- [x] 通知栏显示当前歌曲信息和控制按钮
- [x] 通知栏可控制播放/暂停/上下曲 ✅ (2026-01-17 完成)
- [x] 锁屏界面显示播放控制
- [ ] 后台播放 30 分钟以上无中断

> 🔄 **Phase 5.1 大部分完成** - Android 后台播放和通知栏控制已完整实现（含上一首/下一首），待长时间稳定性测试

### 5.2 Windows 桌面特性

| 任务 ID | 任务名称 | 依赖 | 优先级 | 状态 |
|---------|----------|------|--------|------|
| 5.2.1 | 实现系统托盘 | 2.1.8 | P0 | ✅ |
| 5.2.2 | 实现托盘右键菜单 | 5.2.1 | P0 | ✅ |
| 5.2.3 | 实现托盘当前歌曲显示 | 5.2.1 | P1 | ✅ |
| 5.2.4 | 实现全局快捷键 | 2.1.8 | P0 | ✅ |
| 5.2.5 | 实现快捷键自定义 | 5.2.4 | P1 | ⏳ |
| 5.2.6 | 实现窗口管理 | 5.2.1 | P1 | ✅ |
| 5.2.7 | 实现最小化到托盘 | 5.2.1, 5.2.6 | P1 | ✅ |

**验收标准**:
- [x] 系统托盘图标显示应用状态
- [x] 右键托盘显示播放控制菜单
- [x] 托盘悬停显示当前歌曲信息
- [x] 全局快捷键可控制播放 (Ctrl+Alt+Space/Left/Right)
- [x] 关闭窗口时最小化到托盘而非退出

> ✅ **Phase 5.2 大部分完成** - Windows 桌面特性已实现（托盘、快捷键、窗口管理），快捷键自定义待实现

### 5.3 YouTube 音源

| 任务 ID | 任务名称 | 依赖 | 优先级 | 状态 |
|---------|----------|------|--------|------|
| 5.3.1 | 实现 YouTube ID 解析 | 2.3.1 | P0 | ✅ |
| 5.3.2 | 研究 YouTube 音频获取方案 | 5.3.1 | P0 | ✅ |
| 5.3.3 | 实现视频信息获取 | 5.3.2 | P0 | ✅ |
| 5.3.4 | 实现音频流 URL 获取 | 5.3.2 | P0 | ✅ |
| 5.3.5 | 实现搜索功能 | 5.3.2 | P0 | ✅ |
| 5.3.6 | 实现播放列表解析 | 5.3.3 | P1 | ✅ |

**验收标准**:
- [x] 可从 YouTube URL 解析视频 ID
- [x] 可获取视频标题、作者、时长、封面
- [x] 可获取音频流 URL 并播放
- [x] 搜索功能返回相关结果
- [x] 可导入 YouTube 播放列表

> ✅ **Phase 5.3 完成** - YouTubeSource 已实现，使用 youtube_explode_dart 库

---

## Phase 6: 优化与完善

### 6.1 性能优化

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 6.1.1 | 优化大列表滚动性能 | 4.3.5 | P0 | 中 |
| 6.1.2 | 实现图片懒加载 | 4.3.1 | P1 | 低 |
| 6.1.3 | 优化数据库查询 | 1.3.2 | P1 | 中 |
| 6.1.4 | 减少不必要的重建 | 4.3.1 | P1 | 中 |
| 6.1.5 | 测量并优化启动时间 | 1.1.1 | P1 | 中 |

**验收标准**:
- [ ] 1000+ 歌曲列表滚动流畅 (60fps)
- [ ] 图片懒加载，可见区域外不加载
- [ ] 应用冷启动时间 < 3 秒
- [ ] 页面切换无明显卡顿

### 6.2 缓存与下载

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 6.2.1 | 实现 CacheManager | 1.2.4 | P0 | 中 |
| 6.2.2 | 实现 LRU 自动清理 | 6.2.1 | P0 | 中 |
| 6.2.3 | 实现 DownloadService | 1.2.6 | P0 | 高 |
| 6.2.4 | 实现下载进度追踪 | 6.2.3 | P0 | 中 |
| 6.2.5 | 实现断点续传 | 6.2.3 | P1 | 高 |
| 6.2.6 | 实现批量下载 | 6.2.3 | P1 | 中 |

**验收标准**:
- [ ] 缓存自动清理超过限制的旧文件
- [ ] 下载任务显示进度百分比
- [ ] 下载中断后可断点续传
- [ ] 支持批量下载整个歌单
- [ ] 离线模式下可播放已下载歌曲

### 6.3 最终测试

| 任务 ID | 任务名称 | 依赖 | 优先级 | 预估复杂度 |
|---------|----------|------|--------|------------|
| 6.3.1 | 端到端功能测试 | All | P0 | 高 |
| 6.3.2 | 性能基准测试 | 6.1.* | P1 | 中 |
| 6.3.3 | 内存泄漏检测 | All | P1 | 中 |
| 6.3.4 | 长时间播放测试 | 2.1.* | P0 | 中 |
| 6.3.5 | 离线场景测试 | 6.2.* | P0 | 中 |
| 6.3.6 | 修复发现的问题 | 6.3.1-5 | P0 | 高 |

**验收标准**:
- [ ] 所有核心功能端到端测试通过
- [ ] 连续播放 2 小时无内存泄漏
- [ ] 离线场景正确处理网络错误
- [ ] 所有 P0 问题已修复
- [ ] Android 和 Windows 双平台测试通过

---

## 依赖关系图

```
Phase 1 (基础架构)
━━━━━━━━━━━━━━━━━━━
1.1.1 ──→ 1.1.2 ──→ 1.1.3
  │         │
  │         ├──→ 1.1.4
  │         └──→ 1.1.5
  │
  └──→ 1.1.6

1.1.2 ──→ 1.2.1 ──┐
          1.2.2 ──┤
          1.2.3 ──┼──→ 1.2.7 ──→ 1.2.8
          1.2.4 ──┤
          1.2.5 ──┤
          1.2.6 ──┘

1.2.8 ──→ 1.3.1 ──→ 1.3.2
                ──→ 1.3.3
                ──→ 1.3.4
                ──→ 1.3.5

1.1.3 ──→ 1.3.6 ──→ 1.3.7


Phase 2 (核心播放)
━━━━━━━━━━━━━━━━━━━
1.3.1 ──→ 2.1.1 ──→ 2.1.2
                ──→ 2.1.3 ──→ 2.1.4
                ──→ 2.1.5
                ──→ 2.1.6
                ──→ 2.1.7
                    │
                    ▼
          2.1.8 ──→ 2.1.9

2.1.8 ──→ 2.2.1 ──→ 2.2.2
                ──→ 2.2.3
                ──→ 2.2.4
                ──→ 2.2.5
                ──→ 2.2.6 ──→ 2.2.7
                    │
                    ▼
                  2.2.8

1.3.1 ──→ 2.3.1 ──→ 2.3.2 ──→ 2.3.3 ──→ 2.3.4 ──→ 2.3.7
                           └──→ 2.3.5
                           └──→ 2.3.6


Phase 3-6 继续...
```

---

## 里程碑

### Milestone 1: 可播放 (Playable) ✅ 已达成
**完成条件**: 可以通过 B站 URL 播放音乐
- [x] Phase 1 完成
- [x] Phase 2 (2.1, 2.2, 2.3) 完成
- [x] 基础播放器 UI 完成

**达成日期**: 2026-01-03

### Milestone 2: 可管理 (Manageable) ✅ 已达成
**完成条件**: 可以管理歌单和播放队列
- [x] Phase 3 完成
- [x] 基础音乐库 UI 完成

**达成日期**: 2026-01-03

### Milestone 3: 可发布 (Releasable)
**完成条件**: 功能完整，可日常使用
- [ ] Phase 4, 5, 6 完成
- [ ] 所有 P0 任务完成

---

## 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| B站 API 变更 | 高 | 中 | 监控 API 变化，设计可替换的解析层 |
| YouTube 解析困难 | 高 | 高 | 先完成 B站，YouTube 作为 Phase 5 独立处理 |
| just_audio 兼容性问题 | 中 | 低 | 保持依赖版本稳定，测试多平台 |
| Isar 性能问题 | 中 | 低 | 添加合适索引，优化查询 |
| Windows 桌面 API 限制 | 低 | 中 | 提前验证 tray_manager 和 hotkey_manager |

---

## 下一步行动

1. ~~**立即开始**: Phase 1.1 项目初始化~~ ✅ 已完成
2. ~~**验证**: 确认所有依赖可正确安装~~ ✅ 已完成
3. ~~**原型**: 快速实现最小可播放原型 (M1)~~ ✅ 已完成
4. ~~**音乐库**: 实现歌单管理、导入、搜索 (M2)~~ ✅ 已完成

---

## 当前待办

1. **Phase 4 收尾** - 完善下载管理页面
2. **Phase 5 收尾** - 快捷键自定义
3. **UI 细节优化** - 动画、过渡效果、错误提示

## 最近完成 (2026-01-17)

- ✅ YouTube 音源完整实现（5.3.1-5.3.6）
  - URL 解析（支持多种格式）
  - 视频信息获取（标题、作者、时长、封面）
  - 音频流 URL 获取（优先 audio-only 流）
  - 搜索功能（分页支持）
  - 播放列表解析
- ✅ Windows 系统托盘（图标、右键菜单、当前歌曲显示）
- ✅ Windows 全局快捷键（Ctrl+Alt+Space/Left/Right/S）
- ✅ Windows 最小化到托盘
- ✅ 桌面设置页面（托盘、快捷键开关）
- ✅ Android 通知栏上一首/下一首控制
- ✅ 记住播放位置功能（长视频自动记忆）
- ✅ 下载进度全局节流优化
- ✅ 网络图片缓存
- ✅ UI 刷新性能优化（Android）

---

## 已完成功能清单

### Phase 1 实现文件
| 文件 | 功能 |
|------|------|
| `lib/data/models/track.dart` | Track 数据模型 |
| `lib/data/models/playlist.dart` | Playlist 数据模型 |
| `lib/data/models/play_queue.dart` | PlayQueue 数据模型 |
| `lib/data/models/settings.dart` | Settings 数据模型 |
| `lib/data/models/search_history.dart` | SearchHistory 数据模型 |
| `lib/data/models/download_task.dart` | DownloadTask 数据模型 |
| `lib/providers/database_provider.dart` | Isar 数据库 Provider |
| `lib/data/repositories/track_repository.dart` | Track 仓库 |
| `lib/data/repositories/playlist_repository.dart` | Playlist 仓库 |
| `lib/data/repositories/queue_repository.dart` | Queue 仓库 |
| `lib/data/repositories/settings_repository.dart` | Settings 仓库 |
| `lib/ui/router.dart` | GoRouter 路由配置 |
| `lib/ui/app_shell.dart` | 应用 Shell 框架 |
| `lib/ui/theme/app_theme.dart` | Material 3 主题 |
| `lib/ui/layouts/responsive_scaffold.dart` | 响应式布局 |

### Phase 2 实现文件
| 文件 | 功能 |
|------|------|
| `lib/services/audio/audio_service.dart` | 音频播放服务 |
| `lib/services/audio/queue_manager.dart` | 播放队列管理器 |
| `lib/services/audio/audio_provider.dart` | Riverpod 状态管理 |
| `lib/data/sources/base_source.dart` | 音源抽象基类 |
| `lib/data/sources/bilibili_source.dart` | B站音源实现 |
| `lib/data/sources/source_provider.dart` | 音源 Provider |
| `lib/ui/pages/player/player_page.dart` | 全屏播放器页面 |
| `lib/ui/widgets/player/mini_player.dart` | 迷你播放器组件 |
| `lib/ui/pages/home/home_page.dart` | 首页 (含 URL 输入测试) |

### Phase 3 实现文件
| 文件 | 功能 |
|------|------|
| `lib/services/library/playlist_service.dart` | 歌单管理服务 |
| `lib/providers/playlist_provider.dart` | 歌单状态管理 Provider |
| `lib/services/import/import_service.dart` | 外部导入服务 |
| `lib/services/search/search_service.dart` | 多源搜索服务 |
| `lib/providers/search_provider.dart` | 搜索状态管理 Provider |
| `lib/ui/pages/library/library_page.dart` | 音乐库页面 |
| `lib/ui/pages/library/playlist_detail_page.dart` | 歌单详情页面 |
| `lib/ui/pages/library/widgets/create_playlist_dialog.dart` | 创建歌单对话框 |
| `lib/ui/pages/library/widgets/import_url_dialog.dart` | URL 导入对话框 |
| `lib/ui/pages/search/search_page.dart` | 搜索页面 (完整功能) |

### Phase 4 实现文件
| 文件 | 功能 |
|------|------|
| `lib/ui/layouts/responsive_scaffold.dart` | 响应式布局框架 |
| `lib/ui/theme/app_theme.dart` | Material 3 主题系统 |
| `lib/providers/theme_provider.dart` | 主题状态管理 |
| `lib/ui/pages/player/player_page.dart` | 增强版播放器页面 |
| `lib/ui/widgets/player/mini_player.dart` | 迷你播放器 (拖拽进度条) |
| `lib/ui/pages/queue/queue_page.dart` | 播放队列页面 |
| `lib/ui/pages/settings/settings_page.dart` | 设置页面 (主题/缓存) |
| `lib/ui/pages/settings/download_manager_page.dart` | 下载管理页面 |
| `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart` | 添加到歌单对话框 |
| `lib/ui/widgets/track_detail_panel.dart` | 歌曲详情面板 (可展开描述) |
| `lib/ui/widgets/refresh_progress_indicator.dart` | 刷新进度指示器 |
| `lib/ui/widgets/cached_thumbnail.dart` | 带缓存的网络图片组件 |

### Phase 5 实现文件
| 文件 | 功能 |
|------|------|
| `lib/services/audio/audio_handler.dart` | Android 媒体通知控制 |
| `lib/services/audio/queue_manager.dart` | 记住播放位置功能 |
| `lib/services/platform/windows_desktop_service.dart` | Windows 桌面服务（托盘、快捷键、窗口管理） |
| `lib/providers/windows_desktop_provider.dart` | Windows 桌面服务 Provider |
| `lib/providers/desktop_settings_provider.dart` | 桌面设置 Provider（托盘/快捷键开关） |
| `lib/data/sources/youtube_source.dart` | YouTube 音源实现（youtube_explode_dart） |

### 依赖配置 (pubspec.yaml)
- `just_audio: ^0.9.43` - 音频播放核心
- `just_audio_media_kit: ^2.1.0` - Windows/Linux 平台支持（替代 just_audio_windows）
- `audio_service: ^0.18.15` - Android 媒体通知
- `youtube_explode_dart: ^2.3.5` - YouTube 数据提取
- `tray_manager: ^0.2.3` - Windows 系统托盘
- `window_manager: ^0.4.3` - 窗口管理
- `hotkey_manager: ^0.2.3` - 全局快捷键
- `isar: ^3.1.0+1` - 本地数据库
- `flutter_riverpod: ^2.6.1` - 状态管理
- `dio: ^5.8.0+1` - 网络请求
- `go_router: ^14.8.1` - 路由管理
