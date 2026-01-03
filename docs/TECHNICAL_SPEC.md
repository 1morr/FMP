# Flutter Music Player (FMP) - 技术规格文档

> 版本: 1.0.0
> 创建日期: 2026-01-03
> 状态: 技术设计阶段

---

## 1. 技术栈概览

### 1.1 核心框架

| 层级 | 技术选型 | 版本 | 说明 |
|------|----------|------|------|
| UI 框架 | Flutter | 3.x (最新稳定版) | 跨平台 UI |
| **设计系统** | **Material Design 3** | Material You | 现代化 UI 规范 |
| 编程语言 | Dart | 3.x | 类型安全，空安全 |
| 状态管理 | Riverpod | 2.x+ | 响应式，可测试 |
| 本地存储 | Isar | 3.x | 高性能 NoSQL |
| 音频播放 | just_audio | 0.9.x | 功能全面 |
| 后台播放 | just_audio_background | 0.0.x | Android/iOS 后台 |

### 1.2 平台特定依赖

#### Windows 桌面
| 功能 | 包名 | 说明 |
|------|------|------|
| 系统托盘 | tray_manager | 托盘图标与菜单 |
| 窗口管理 | window_manager | 窗口控制 |
| 全局快捷键 | hotkey_manager | 全局热键注册 |

#### Android 移动端
| 功能 | 包名 | 说明 |
|------|------|------|
| 权限管理 | permission_handler | 存储权限等 |
| 后台服务 | just_audio_background | 通知栏控制 |

### 1.3 公共依赖

| 功能 | 包名 | 说明 |
|------|------|------|
| 网络请求 | dio | HTTP 客户端 |
| 路由管理 | go_router | 声明式路由 |
| 依赖注入 | riverpod | Provider 系统 |
| 日志 | logger | 开发调试 |
| 文件选择 | file_picker | 文件/目录选择 |
| 图片缓存 | cached_network_image | 封面缓存 |
| 拖拽排序 | flutter_reorderable_list | 队列排序 |

---

## 2. 项目架构

### 2.1 目录结构

```
lib/
├── main.dart                    # 应用入口
├── app.dart                     # App 配置
│
├── core/                        # 核心模块
│   ├── constants/               # 常量定义
│   │   ├── app_constants.dart
│   │   ├── breakpoints.dart     # 响应式断点
│   │   └── theme_constants.dart
│   ├── extensions/              # Dart 扩展
│   ├── utils/                   # 工具函数
│   │   ├── platform_utils.dart
│   │   └── duration_utils.dart
│   └── errors/                  # 错误处理
│       ├── app_exception.dart
│       └── error_handler.dart
│
├── data/                        # 数据层
│   ├── models/                  # 数据模型 (Isar Collections)
│   │   ├── track.dart
│   │   ├── playlist.dart
│   │   ├── play_queue.dart
│   │   ├── search_history.dart
│   │   └── settings.dart
│   ├── repositories/            # 数据仓库
│   │   ├── track_repository.dart
│   │   ├── playlist_repository.dart
│   │   ├── queue_repository.dart
│   │   └── settings_repository.dart
│   └── sources/                 # 音源解析
│       ├── base_source.dart
│       ├── bilibili_source.dart
│       └── youtube_source.dart
│
├── services/                    # 服务层
│   ├── audio/                   # 音频服务
│   │   ├── audio_service.dart
│   │   ├── audio_handler.dart
│   │   └── playback_state.dart
│   ├── download/                # 下载服务
│   │   ├── download_service.dart
│   │   ├── download_task.dart
│   │   └── cache_manager.dart
│   ├── search/                  # 搜索服务
│   │   └── search_service.dart
│   ├── import/                  # 导入服务
│   │   ├── import_service.dart
│   │   └── playlist_sync_service.dart
│   └── platform/                # 平台服务
│       ├── tray_service.dart    # Windows 托盘
│       ├── hotkey_service.dart  # 全局快捷键
│       └── notification_service.dart
│
├── providers/                   # Riverpod Providers
│   ├── audio_provider.dart
│   ├── queue_provider.dart
│   ├── playlist_provider.dart
│   ├── search_provider.dart
│   ├── settings_provider.dart
│   ├── download_provider.dart
│   └── theme_provider.dart
│
├── ui/                          # UI 层
│   ├── app_shell.dart           # 响应式外壳
│   ├── router.dart              # 路由配置
│   │
│   ├── pages/                   # 页面
│   │   ├── home/
│   │   │   ├── home_page.dart
│   │   │   └── widgets/
│   │   ├── search/
│   │   │   ├── search_page.dart
│   │   │   └── widgets/
│   │   ├── player/
│   │   │   ├── player_page.dart
│   │   │   ├── mini_player.dart
│   │   │   └── widgets/
│   │   ├── queue/
│   │   │   ├── queue_page.dart
│   │   │   └── widgets/
│   │   ├── library/
│   │   │   ├── library_page.dart
│   │   │   ├── playlist_detail_page.dart
│   │   │   └── widgets/
│   │   └── settings/
│   │       ├── settings_page.dart
│   │       ├── theme_settings_page.dart
│   │       ├── cache_settings_page.dart
│   │       ├── hotkey_settings_page.dart
│   │       └── widgets/
│   │
│   ├── widgets/                 # 共享组件
│   │   ├── track_tile.dart
│   │   ├── playlist_card.dart
│   │   ├── source_badge.dart
│   │   ├── loading_indicator.dart
│   │   └── error_view.dart
│   │
│   ├── layouts/                 # 响应式布局
│   │   ├── responsive_scaffold.dart
│   │   ├── mobile_layout.dart
│   │   ├── tablet_layout.dart
│   │   └── desktop_layout.dart
│   │
│   └── theme/                   # 主题
│       ├── app_theme.dart
│       ├── color_schemes.dart
│       └── text_styles.dart
│
└── platform/                    # 平台特定代码
    ├── android/
    ├── windows/
    └── shared/
```

### 2.2 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                           UI Layer                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Pages   │ │ Widgets  │ │ Layouts  │ │  Theme   │ │ Router │ │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘ │
└───────┼────────────┼────────────┼────────────┼───────────┼──────┘
        │            │            │            │           │
        ▼            ▼            ▼            ▼           ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Provider Layer (Riverpod)                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │AudioProvider │ │QueueProvider │ │ThemeProvider │    ...      │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Service Layer                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │AudioService │ │DownloadSvc  │ │ ImportSvc   │ │ PlatformSvc│ │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘ └─────┬─────┘  │
└─────────┼───────────────┼───────────────┼──────────────┼────────┘
          │               │               │              │
          ▼               ▼               ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Data Layer                               │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │ Repositories │ │   Sources    │ │    Models    │             │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      External Layer                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │   Isar   │ │just_audio│ │  Dio/HTTP │ │ Platform │            │
│  │ Database │ │  Player  │ │  Client   │ │   APIs   │            │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 数据模型 (Isar Collections)

### 3.1 Track (歌曲)

```dart
import 'package:isar/isar.dart';

part 'track.g.dart';

enum SourceType { bilibili, youtube }

@collection
class Track {
  Id id = Isar.autoIncrement;

  @Index()
  late String sourceId;      // 源平台的唯一ID (如 BV号, YouTube video ID)

  @Index()
  @Enumerated(EnumType.name)
  late SourceType sourceType;

  late String title;
  String? artist;
  int? durationMs;           // 时长（毫秒）
  String? thumbnailUrl;      // 封面图 URL

  // 音频 URL（可能会过期，需要重新获取）
  String? audioUrl;
  DateTime? audioUrlExpiry;

  // 可用性
  bool isAvailable = true;
  String? unavailableReason;

  // 缓存/下载状态
  String? cachedPath;        // 流媒体缓存路径
  String? downloadedPath;    // 离线下载路径

  DateTime createdAt = DateTime.now();
  DateTime? updatedAt;

  // 复合索引用于快速查找
  @Index(composite: [CompositeIndex('sourceType')])
  String get sourceKey => '$sourceType:$sourceId';
}
```

### 3.2 Playlist (歌单)

```dart
@collection
class Playlist {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String name;

  String? description;
  String? coverUrl;          // 自定义封面
  String? coverLocalPath;    // 本地封面路径

  // 导入源信息（如果是从外部导入的）
  String? sourceUrl;         // B站收藏夹/YouTube播放列表 URL
  @Enumerated(EnumType.name)
  SourceType? importSourceType;

  // 刷新配置
  Duration? refreshInterval; // 刷新间隔
  DateTime? lastRefreshed;
  bool notifyOnUpdate = true;

  final tracks = IsarLinks<Track>();  // 关联的歌曲

  DateTime createdAt = DateTime.now();
  DateTime? updatedAt;
}
```

### 3.3 PlayQueue (播放队列)

```dart
@collection
class PlayQueue {
  Id id = Isar.autoIncrement;

  // 队列中的歌曲ID列表（有序）
  List<int> trackIds = [];

  // 当前播放状态
  int currentIndex = 0;
  int lastPositionMs = 0;    // 上次播放位置（毫秒）

  @Enumerated(EnumType.name)
  PlayMode playMode = PlayMode.sequential;

  // 原始顺序（用于取消随机时恢复）
  List<int>? originalOrder;

  DateTime? lastUpdated;
}

enum PlayMode {
  sequential,  // 顺序播放
  loop,        // 列表循环
  loopOne,     // 单曲循环
  shuffle,     // 随机播放
}
```

### 3.4 Settings (设置)

```dart
@collection
class Settings {
  Id id = 0;  // 单例，始终使用 ID 0

  // 主题
  @Enumerated(EnumType.name)
  ThemeMode themeMode = ThemeMode.system;

  // 自定义颜色 (ARGB int)
  int? primaryColor;
  int? secondaryColor;
  int? backgroundColor;
  int? surfaceColor;
  int? textColor;
  int? cardColor;

  // 缓存设置
  String? customCacheDir;
  int maxCacheSizeMB = 2048;  // 默认 2GB
  String? customDownloadDir;

  // 快捷键配置 (JSON 字符串)
  String? hotkeyConfig;

  // 搜索设置
  List<String> enabledSources = ['bilibili', 'youtube'];

  // 导入设置
  bool autoRefreshImports = true;
  int defaultRefreshIntervalHours = 24;
}
```

### 3.5 SearchHistory (搜索历史)

```dart
@collection
class SearchHistory {
  Id id = Isar.autoIncrement;

  @Index()
  late String query;

  @Index()
  DateTime timestamp = DateTime.now();
}
```

### 3.6 DownloadTask (下载任务)

```dart
@collection
class DownloadTask {
  Id id = Isar.autoIncrement;

  @Index()
  late int trackId;

  @Enumerated(EnumType.name)
  DownloadStatus status = DownloadStatus.pending;

  double progress = 0.0;
  String? errorMessage;

  DateTime createdAt = DateTime.now();
  DateTime? completedAt;
}

enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
}
```

---

## 4. 核心服务实现

### 4.1 音频服务 (AudioService)

```dart
class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final QueueRepository _queueRepository;

  // 状态流
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  // 播放队列
  ConcatenatingAudioSource? _playlist;

  Future<void> playTrack(Track track, {int? queueIndex}) async {
    // 1. 获取音频 URL（如果过期则重新获取）
    final audioUrl = await _getAudioUrl(track);

    // 2. 创建 AudioSource
    final source = AudioSource.uri(
      Uri.parse(audioUrl),
      tag: MediaItem(
        id: track.id.toString(),
        title: track.title,
        artist: track.artist,
        artUri: track.thumbnailUrl != null
          ? Uri.parse(track.thumbnailUrl!)
          : null,
      ),
    );

    // 3. 播放
    await _player.setAudioSource(source);
    await _player.play();
  }

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    _playlist = ConcatenatingAudioSource(
      children: tracks.map((t) => AudioSource.uri(
        Uri.parse(t.audioUrl ?? ''),
        tag: _trackToMediaItem(t),
      )).toList(),
    );

    await _player.setAudioSource(_playlist!, initialIndex: startIndex);
  }

  // 播放控制
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seekTo(Duration position) => _player.seek(position);
  Future<void> seekToNext() => _player.seekToNext();
  Future<void> seekToPrevious() => _player.seekToPrevious();

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
        break;
      case PlayMode.shuffle:
        await _player.setLoopMode(LoopMode.all);
        await _player.setShuffleModeEnabled(true);
        break;
    }
  }

  // 播放速度
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  // 快进快退
  Future<void> seekForward(Duration duration) async {
    final newPosition = _player.position + duration;
    await _player.seek(newPosition);
  }

  Future<void> seekBackward(Duration duration) async {
    final newPosition = _player.position - duration;
    await _player.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }
}
```

### 4.2 音源解析 (Source Parser)

```dart
abstract class BaseSource {
  SourceType get sourceType;

  /// 从 URL 解析出 ID
  String? parseId(String url);

  /// 获取歌曲信息
  Future<Track> getTrackInfo(String sourceId);

  /// 获取音频流 URL（可能会过期）
  Future<String> getAudioUrl(String sourceId);

  /// 搜索
  Future<List<Track>> search(String query, {int page = 1, int pageSize = 20});

  /// 解析播放列表/收藏夹
  Future<List<Track>> parsePlaylist(String playlistUrl);
}

class BilibiliSource extends BaseSource {
  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String? parseId(String url) {
    // 解析 BV 号
    final regex = RegExp(r'BV[a-zA-Z0-9]+');
    final match = regex.firstMatch(url);
    return match?.group(0);
  }

  @override
  Future<Track> getTrackInfo(String bvid) async {
    // 调用 B站 API 获取视频信息
    final response = await _dio.get(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: {'bvid': bvid},
    );

    final data = response.data['data'];
    return Track()
      ..sourceId = bvid
      ..sourceType = SourceType.bilibili
      ..title = data['title']
      ..artist = data['owner']['name']
      ..durationMs = data['duration'] * 1000
      ..thumbnailUrl = data['pic'];
  }

  @override
  Future<String> getAudioUrl(String bvid) async {
    // 获取音频流 URL
    // 需要先获取 cid，再获取播放 URL
    // ...
  }

  @override
  Future<List<Track>> parsePlaylist(String favUrl) async {
    // 解析收藏夹 URL，获取所有视频
    // ...
  }
}

class YouTubeSource extends BaseSource {
  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  String? parseId(String url) {
    // 解析 YouTube video ID
    final regex = RegExp(
      r'(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})'
    );
    final match = regex.firstMatch(url);
    return match?.group(1);
  }

  // ... 其他实现
}
```

### 4.3 下载服务 (DownloadService)

```dart
class DownloadService {
  final Dio _dio = Dio();
  final Map<int, CancelToken> _cancelTokens = {};

  final _progressController = StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  Future<void> startDownload(Track track) async {
    final task = DownloadTask()
      ..trackId = track.id
      ..status = DownloadStatus.downloading;

    await _taskRepository.save(task);

    final cancelToken = CancelToken();
    _cancelTokens[track.id] = cancelToken;

    try {
      final audioUrl = await _getAudioUrl(track);
      final savePath = await _getDownloadPath(track);

      await _dio.download(
        audioUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          task.progress = progress;
          _progressController.add(DownloadProgress(track.id, progress));
        },
      );

      track.downloadedPath = savePath;
      await _trackRepository.save(track);

      task.status = DownloadStatus.completed;
      task.completedAt = DateTime.now();
      await _taskRepository.save(task);

    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task.status = DownloadStatus.paused;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.message;
      }
      await _taskRepository.save(task);
    }
  }

  Future<void> pauseDownload(int trackId) async {
    _cancelTokens[trackId]?.cancel();
  }

  Future<void> resumeDownload(Track track) async {
    // 断点续传实现
    // ...
  }
}
```

### 4.4 缓存管理 (CacheManager)

```dart
class CacheManager {
  late Directory _cacheDir;
  late int _maxSizeBytes;

  Future<void> initialize(Settings settings) async {
    _cacheDir = settings.customCacheDir != null
      ? Directory(settings.customCacheDir!)
      : await getTemporaryDirectory();

    _maxSizeBytes = settings.maxCacheSizeMB * 1024 * 1024;
  }

  /// 自动清理缓存（LRU）
  Future<void> autoClean() async {
    final files = await _getCacheFiles();

    // 按访问时间排序
    files.sort((a, b) =>
      a.statSync().accessed.compareTo(b.statSync().accessed));

    int totalSize = files.fold(0, (sum, f) => sum + f.lengthSync());

    // 删除最旧的文件直到低于上限
    while (totalSize > _maxSizeBytes && files.isNotEmpty) {
      final oldest = files.removeAt(0);
      totalSize -= oldest.lengthSync();
      await oldest.delete();
    }
  }

  Future<int> getCacheSize() async {
    final files = await _getCacheFiles();
    return files.fold(0, (sum, f) => sum + f.lengthSync());
  }

  Future<void> clearCache() async {
    final files = await _getCacheFiles();
    for (final file in files) {
      await file.delete();
    }
  }
}
```

---

## 5. 响应式 UI 实现

### 5.1 断点定义

```dart
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1200;

  static LayoutType getLayoutType(double width) {
    if (width < mobile) return LayoutType.mobile;
    if (width < tablet) return LayoutType.tablet;
    return LayoutType.desktop;
  }
}

enum LayoutType { mobile, tablet, desktop }
```

### 5.2 响应式 Scaffold

```dart
class ResponsiveScaffold extends ConsumerWidget {
  final Widget child;
  final int selectedIndex;
  final Function(int) onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutType = Breakpoints.getLayoutType(constraints.maxWidth);

        return switch (layoutType) {
          LayoutType.mobile => MobileLayout(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            child: child,
          ),
          LayoutType.tablet => TabletLayout(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            child: child,
          ),
          LayoutType.desktop => DesktopLayout(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            child: child,
          ),
        };
      },
    );
  }
}
```

### 5.3 桌面三栏布局

```dart
class DesktopLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧导航栏
        NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: _destinations,
        ),

        // 分隔线
        const VerticalDivider(width: 1),

        // 中间内容区
        Expanded(
          flex: 2,
          child: child,
        ),

        // 分隔线
        const VerticalDivider(width: 1),

        // 右侧播放器详情（如果正在播放）
        Expanded(
          flex: 1,
          child: PlayerDetailPanel(),
        ),
      ],
    );
  }
}
```

---

## 6. 主题系统

### 6.1 主题 Provider

```dart
@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  @override
  AppThemeState build() {
    _loadSavedTheme();
    return AppThemeState.defaults();
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(mode: mode);
    _saveTheme();
  }

  void setCustomColor(ColorType type, Color color) {
    final newColors = Map<ColorType, Color>.from(state.customColors);
    newColors[type] = color;
    state = state.copyWith(customColors: newColors);
    _saveTheme();
  }

  ThemeData buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: state.customColors[ColorType.primary] ?? Colors.blue,
        secondary: state.customColors[ColorType.secondary] ?? Colors.blueAccent,
        surface: state.customColors[ColorType.surface] ?? Colors.white,
        // ...
      ),
    );
  }

  ThemeData buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: state.customColors[ColorType.primary] ?? Colors.blue,
        // ...
      ),
    );
  }
}
```

---

## 7. 平台特定实现

### 7.1 Windows 系统托盘

```dart
class TrayService {
  Future<void> initialize() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }

    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icons/tray.ico' : 'assets/icons/tray.png',
    );

    await _updateContextMenu();
  }

  Future<void> updateNowPlaying(Track? track) async {
    if (track != null) {
      await trayManager.setToolTip('${track.title} - ${track.artist ?? "Unknown"}');
    } else {
      await trayManager.setToolTip('FMP - Flutter Music Player');
    }
    await _updateContextMenu(track);
  }

  Future<void> _updateContextMenu([Track? track]) async {
    final menu = Menu(
      items: [
        if (track != null) ...[
          MenuItem(key: 'now_playing', label: '♪ ${track.title}'),
          MenuItem.separator(),
        ],
        MenuItem(key: 'play_pause', label: _isPlaying ? 'Pause' : 'Play'),
        MenuItem(key: 'next', label: 'Next'),
        MenuItem(key: 'previous', label: 'Previous'),
        MenuItem.separator(),
        MenuItem(key: 'show', label: 'Show Window'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }
}
```

### 7.2 全局快捷键

```dart
class HotkeyService {
  final Map<String, HotKey> _registeredHotkeys = {};

  Future<void> initialize(Settings settings) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }

    final config = settings.hotkeyConfig != null
      ? HotkeyConfig.fromJson(settings.hotkeyConfig!)
      : HotkeyConfig.defaults();

    await _registerHotkey('play_pause', config.playPause, _onPlayPause);
    await _registerHotkey('next', config.next, _onNext);
    await _registerHotkey('previous', config.previous, _onPrevious);
    await _registerHotkey('volume_up', config.volumeUp, _onVolumeUp);
    await _registerHotkey('volume_down', config.volumeDown, _onVolumeDown);
    await _registerHotkey('show_hide', config.showHide, _onShowHide);
  }

  Future<void> _registerHotkey(
    String id,
    HotKey hotkey,
    VoidCallback callback,
  ) async {
    await hotKeyManager.register(
      hotkey,
      keyDownHandler: (_) => callback(),
    );
    _registeredHotkeys[id] = hotkey;
  }

  Future<void> updateHotkey(String id, HotKey newHotkey) async {
    final oldHotkey = _registeredHotkeys[id];
    if (oldHotkey != null) {
      await hotKeyManager.unregister(oldHotkey);
    }
    await _registerHotkey(id, newHotkey, _getCallback(id));
  }
}
```

---

## 8. 错误处理策略

### 8.1 播放错误处理

```dart
class PlaybackErrorHandler {
  void handleError(Object error, Track track) {
    if (error is PlayerException) {
      // 音频加载失败
      _showToast('播放失败: ${track.title}');
      _audioService.seekToNext();
    } else if (error is SourceUnavailableException) {
      // 音源失效
      _markTrackUnavailable(track, error.reason);
      _showToast('音源失效: ${track.title}');
      _audioService.seekToNext();
    } else if (error is NetworkException) {
      // 网络错误
      _showToast('网络错误，跳转下一首');
      _audioService.seekToNext();
    }
  }

  void _markTrackUnavailable(Track track, String reason) {
    track.isAvailable = false;
    track.unavailableReason = reason;
    _trackRepository.save(track);
  }
}
```

---

## 9. 开发路线图

### Phase 1: 核心功能 (MVP)
- [ ] 项目初始化与架构搭建
- [ ] 数据模型与 Isar 集成
- [ ] 音频播放核心功能
- [ ] 播放队列管理
- [ ] 基础 UI（首页、播放器、队列）
- [ ] B站音源解析
- [ ] Android 后台播放

### Phase 2: 完整功能
- [ ] YouTube 音源解析
- [ ] 音乐库与歌单管理
- [ ] 搜索功能
- [ ] 外部歌单导入
- [ ] 缓存与下载管理
- [ ] Windows 系统托盘
- [ ] 全局快捷键

### Phase 3: 优化与扩展
- [ ] 主题自定义
- [ ] 响应式布局优化
- [ ] 性能优化
- [ ] 导入歌单定时刷新
- [ ] 导出功能

### Phase 4: 未来功能
- [ ] 歌词显示
- [ ] 云同步
- [ ] 更多平台支持
- [ ] 更多音源支持

---

## 10. 依赖清单

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter

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

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  riverpod_generator: ^2.3.0
  isar_generator: ^3.1.0
  flutter_lints: ^3.0.0
```

---

## 11. 附录

### 11.1 B站 API 参考

- 视频信息: `https://api.bilibili.com/x/web-interface/view?bvid={bvid}`
- 播放 URL: `https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&fnval=16`
- 收藏夹: `https://api.bilibili.com/x/v3/fav/resource/list?media_id={fid}`

### 11.2 YouTube 解析参考

- 使用 yt-dlp 的 Dart 封装或自行实现解析
- 注意: YouTube 的音频 URL 经常变化，需要实现刷新机制

### 11.3 相关资源

- [just_audio 文档](https://pub.dev/packages/just_audio)
- [Isar 文档](https://isar.dev)
- [Riverpod 文档](https://riverpod.dev)
- [Flutter 响应式布局指南](https://docs.flutter.dev/ui/layout/responsive)
