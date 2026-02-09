# Flutter Music Player (FMP) - 技术规格文档

> 版本: 1.1.0
> 创建日期: 2026-01-03
> 最后更新: 2026-02-09
> 状态: 实现完成 (Phase 1-5 ✅)

---

## 1. 技术栈概览

### 1.1 核心框架

| 层级 | 技术选型 | 版本 | 说明 |
|------|----------|------|------|
| UI 框架 | Flutter | 3.x (>=3.5.0) | 跨平台 UI |
| 设计系统 | Material Design 3 | Material You | 现代化 UI 规范 |
| 编程语言 | Dart | 3.x | 类型安全，空安全 |
| 状态管理 | Riverpod | 2.6.x | 响应式，可测试 |
| 本地存储 | Isar | 3.1.x | 高性能 NoSQL |
| 音频播放 | media_kit | 1.1.x | 直接使用，原生 httpHeaders 支持 |
| 后台播放 | audio_service | 0.18.x | Android 媒体通知控制 |
| Windows 媒体 | smtc_windows | 1.1.x | Windows SMTC 媒体键 |
| 网络请求 | Dio | 5.8.x | HTTP 客户端 |
| 路由管理 | go_router | 14.8.x | 声明式路由 |

### 1.2 平台特定依赖

#### Windows 桌面
| 功能 | 包名 | 版本 | 说明 |
|------|------|------|------|
| 系统托盘 | tray_manager | 0.2.x | 托盘图标与菜单 |
| 窗口管理 | window_manager | 0.4.x | 窗口控制 |
| 全局快捷键 | hotkey_manager | 0.2.x | 全局热键注册 |
| 音频支持 | media_kit_libs_windows_audio | 1.0.x | Windows 音频解码 |

#### Android 移动端
| 功能 | 包名 | 版本 | 说明 |
|------|------|------|------|
| 权限管理 | permission_handler | 11.4.x | 存储权限等 |
| 后台服务 | audio_service | 0.18.x | 媒体通知栏控制 |
| 音频支持 | media_kit_libs_android_audio | 1.3.x | Android 音频解码 |
| APK 安装 | open_filex | 4.5.x | 应用更新安装 |

### 1.3 公共依赖

| 功能 | 包名 | 版本 | 说明 |
|------|------|------|------|
| 动态取色 | dynamic_color | 1.7.x | Material You 动态颜色 |
| YouTube 解析 | youtube_explode_dart | 2.3.x | YouTube 数据提取 |
| 图片缓存 | cached_network_image | 3.4.x | 封面缓存 |
| 文件选择 | file_picker | 8.3.x | 文件/目录选择 |
| 日志 | logger | 2.5.x | 开发调试 |
| 流处理 | rxdart | 0.28.x | BehaviorSubject 等 |
| ZIP 解压 | archive | 4.0.x | Windows 更新解压 |
| 版本信息 | package_info_plus | 8.0.x | 获取应用版本 |

---

## 2. 项目架构

### 2.1 目录结构

```
lib/
├── main.dart                    # 应用入口
├── app.dart                     # App 配置（主题、路由）
│
├── core/                        # 核心模块
│   ├── constants/               # 常量定义
│   │   ├── app_constants.dart   # 应用常量
│   │   └── source_type.dart     # 音源类型枚举
│   ├── extensions/              # Dart 扩展
│   │   └── track_extensions.dart # Track 扩展方法
│   └── utils/                   # 工具函数
│       └── duration_formatter.dart
│
├── data/                        # 数据层
│   ├── models/                  # 数据模型 (Isar Collections)
│   │   ├── track.dart           # 歌曲模型
│   │   ├── playlist.dart        # 歌单模型
│   │   ├── play_queue.dart      # 播放队列模型
│   │   ├── settings.dart        # 设置模型
│   │   ├── search_history.dart  # 搜索历史
│   │   └── download_task.dart   # 下载任务
│   ├── repositories/            # 数据仓库
│   │   ├── track_repository.dart
│   │   ├── playlist_repository.dart
│   │   ├── queue_repository.dart
│   │   └── settings_repository.dart
│   └── database/
│       └── database_service.dart # Isar 数据库初始化
│
├── sources/                     # 音源解析
│   ├── base_source.dart         # 音源基类
│   ├── bilibili_source.dart     # Bilibili 音源
│   ├── youtube_source.dart      # YouTube 音源
│   └── source_manager.dart      # 音源管理器
│
├── services/                    # 服务层
│   ├── audio/                   # 音频服务
│   │   ├── media_kit_audio_service.dart  # media_kit 播放器封装
│   │   ├── audio_controller.dart         # 播放控制器（核心）
│   │   ├── android_audio_handler.dart    # Android 后台播放
│   │   └── windows_smtc_handler.dart     # Windows 媒体键
│   ├── download/                # 下载服务
│   │   ├── download_service.dart         # 下载任务管理
│   │   ├── download_path_utils.dart      # 路径计算
│   │   ├── download_path_manager.dart    # 路径选择管理
│   │   └── download_path_sync_service.dart # 本地文件同步
│   ├── playlist/                # 歌单服务
│   │   └── playlist_service.dart
│   ├── ranking/                 # 排行榜服务
│   │   └── ranking_cache_service.dart    # 排行榜缓存
│   ├── update/                  # 应用更新
│   │   └── update_service.dart
│   └── platform/                # 平台服务
│       ├── tray_service.dart    # Windows 托盘
│       └── hotkey_service.dart  # 全局快捷键
│
├── providers/                   # Riverpod Providers
│   ├── audio/
│   │   ├── audio_controller_provider.dart
│   │   └── player_state_provider.dart
│   ├── download/
│   │   ├── download_providers.dart
│   │   ├── download_scanner.dart
│   │   └── file_exists_cache.dart
│   ├── playlist_provider.dart
│   ├── search_provider.dart
│   ├── settings_provider.dart
│   ├── theme_provider.dart
│   └── update_provider.dart
│
├── ui/                          # UI 层
│   ├── router.dart              # 路由配置
│   ├── responsive_scaffold.dart # 响应式外壳
│   │
│   ├── pages/                   # 页面
│   │   ├── home/
│   │   │   └── home_page.dart
│   │   ├── explore/
│   │   │   └── explore_page.dart
│   │   ├── search/
│   │   │   └── search_page.dart
│   │   ├── player/
│   │   │   ├── player_page.dart
│   │   │   └── radio_player_page.dart   # Mix 模式播放器
│   │   ├── queue/
│   │   │   └── queue_page.dart
│   │   ├── history/
│   │   │   └── play_history_page.dart
│   │   ├── library/
│   │   │   ├── library_page.dart
│   │   │   ├── playlist_detail_page.dart
│   │   │   ├── downloaded_page.dart
│   │   │   └── downloaded_category_page.dart
│   │   └── settings/
│   │       ├── settings_page.dart
│   │       ├── audio_settings_page.dart
│   │       └── download_manager_page.dart
│   │
│   ├── widgets/                 # 共享组件
│   │   ├── mini_player.dart
│   │   ├── track_detail_panel.dart      # 桌面端详情面板
│   │   ├── track_thumbnail.dart
│   │   ├── track_cover.dart
│   │   ├── now_playing_indicator.dart
│   │   ├── update_dialog.dart
│   │   └── change_download_path_dialog.dart
│   │
│   └── theme/                   # 主题
│       └── app_theme.dart
│
└── platform/                    # 平台特定代码
    ├── android/
    └── windows/
```

### 2.2 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                           UI Layer                               │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │  Pages   │ │ Widgets  │ │Responsive│ │  Theme   │            │
│  │          │ │          │ │ Scaffold │ │          │            │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘            │
└───────┼────────────┼────────────┼────────────┼──────────────────┘
        │            │            │            │
        ▼            ▼            ▼            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Provider Layer (Riverpod)                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │AudioController│ │PlayerState  │ │SettingsProvider│   ...     │
│  │   Provider   │ │  Provider   │ │              │             │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Service Layer                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │MediaKitAudio│ │DownloadSvc  │ │SourceManager│ │UpdateSvc  │  │
│  │  Service    │ │             │ │             │ │           │  │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘ └─────┬─────┘  │
└─────────┼───────────────┼───────────────┼──────────────┼────────┘
          │               │               │              │
          ▼               ▼               ▼              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Data Layer                               │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │ Repositories │ │   Sources    │ │    Models    │             │
│  │              │ │ (Bilibili/YT)│ │   (Isar)     │             │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      External Layer                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │   Isar   │ │media_kit │ │  Dio +   │ │ Platform │            │
│  │ Database │ │  Player  │ │yt_explode│ │   APIs   │            │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 数据模型 (Isar Collections)

### 3.1 Track (歌曲)

```dart
@collection
class Track {
  Id id = Isar.autoIncrement;

  @Index()
  late String sourceId;           // 源平台 ID (BV号/YouTube video ID)

  @Index()
  @Enumerated(EnumType.ordinal)
  late SourceType sourceType;     // bilibili / youtube

  late String title;
  String? artist;
  int? durationMs;                // 时长（毫秒）
  String? thumbnailUrl;           // 封面 URL

  // Bilibili 特有字段
  int? cid;                       // Bilibili cid
  int? pageNum;                   // 多P视频分P序号
  String? parentTitle;            // 多P视频父标题

  // 歌单关联（多对多）
  List<int> playlistIds = [];     // 关联的歌单 ID 列表

  // 下载路径（按歌单存储）
  List<String> downloadPaths = []; // 下载路径列表

  // 播放位置记忆
  int? rememberedPositionMs;      // 记忆的播放位置（长视频）

  DateTime createdAt = DateTime.now();
  DateTime? lastPlayedAt;

  // 复合索引
  @Index(composite: [CompositeIndex('sourceType'), CompositeIndex('cid')])
  String get sourceKey => '$sourceType:$sourceId';
}

// Track 扩展方法 (track_extensions.dart)
extension TrackExtensions on Track {
  bool get isDownloaded => downloadPaths.isNotEmpty;
  String? get localAudioPath;           // 第一个存在的音频路径
  List<String> get validDownloadPaths;  // 过滤出存在的路径
  bool get hasLocalAudio;
  bool get isPartOfMultiPage => pageNum != null && pageNum! > 0;
}
```

### 3.2 Playlist (歌单)

```dart
@collection
class Playlist {
  Id id = Isar.autoIncrement;

  late String name;
  String? description;
  String? coverUrl;

  // 导入源信息
  String? sourceUrl;              // B站收藏夹/YouTube播放列表 URL
  @Enumerated(EnumType.ordinal)
  SourceType? sourceType;         // 导入源类型

  bool isImported = false;        // 是否为导入歌单

  DateTime createdAt = DateTime.now();
  DateTime? lastSyncedAt;         // 最后同步时间
}
```

### 3.3 PlayQueue (播放队列)

```dart
@collection
class PlayQueue {
  Id id = 0;                      // 单例

  List<int> trackIds = [];        // 队列中的歌曲 ID 列表
  int currentIndex = 0;
  int lastPositionMs = 0;         // 上次播放位置

  @Enumerated(EnumType.ordinal)
  LoopMode loopMode = LoopMode.off;

  bool isShuffled = false;
  List<int>? originalOrder;       // 随机前的原始顺序

  double volume = 1.0;            // 音量 (0.0-1.0)
  double? volumeBeforeMute;       // 静音前的音量

  // Mix 模式相关
  bool isMixMode = false;
  String? mixPlaylistId;          // Mix 播放列表 ID (以 "RD" 开头)
  String? mixSeedVideoId;         // Mix 种子视频 ID
  String? mixTitle;

  DateTime? lastUpdated;
}

enum LoopMode { off, one, all }
```

### 3.4 Settings (设置)

```dart
@collection
class Settings {
  Id id = 0;                      // 单例

  // 主题
  int themeModeIndex = 0;         // 0=system, 1=light, 2=dark

  // 下载设置
  String? downloadPath;

  // 桌面设置
  bool minimizeToTray = true;
  bool globalHotkeysEnabled = true;

  // 播放设置
  bool autoScrollToCurrentTrack = true;

  // 音频质量设置
  int audioQualityLevelIndex = 0;       // 0=high, 1=medium, 2=low
  String audioFormatPriority = 'opus,aac';
  String youtubeStreamPriority = 'audioOnly,muxed,hls';
  String bilibiliStreamPriority = 'audioOnly,muxed';
}
```

### 3.5 DownloadTask (下载任务)

```dart
@collection
class DownloadTask {
  Id id = Isar.autoIncrement;

  @Index()
  late int trackId;

  int? playlistId;                // 关联的歌单 ID

  @Index()
  late String savePath;           // 保存路径（用于去重）

  @Enumerated(EnumType.ordinal)
  DownloadStatus status = DownloadStatus.pending;

  double progress = 0.0;          // 注意：进度主要在内存中管理
  String? errorMessage;

  DateTime createdAt = DateTime.now();
  DateTime? completedAt;
}

enum DownloadStatus { pending, downloading, paused, completed, failed }
```

### 3.6 SearchHistory (搜索历史)

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

### 3.7 枚举类型汇总

```dart
enum SourceType { bilibili, youtube }

enum LoopMode { off, one, all }

enum PlayMode { queue, temporary, detached, mix }

enum AudioQualityLevel { high, medium, low }

enum AudioFormat { opus, aac }

enum StreamType { audioOnly, muxed, hls }

enum DownloadStatus { pending, downloading, paused, completed, failed }
```

---

## 4. 核心服务实现

### 4.1 音频服务架构

FMP 使用 `media_kit` 直接播放，通过 `AudioController` 统一管理播放状态。

```
┌─────────────────────────────────────────────────────────────┐
│                     AudioController                          │
│  (lib/services/audio/audio_controller.dart)                 │
│  - 播放控制核心                                              │
│  - 队列管理                                                  │
│  - 临时播放/Mix 模式                                         │
└─────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│                  MediaKitAudioService                        │
│  (lib/services/audio/media_kit_audio_service.dart)          │
│  - media_kit Player 封装                                     │
│  - 原生 httpHeaders 支持（解决 Bilibili 防盗链）             │
│  - 状态流管理 (RxDart BehaviorSubject)                       │
└─────────────────────────────────────────────────────────────┘
          │
          ├──────────────────────┬──────────────────────┐
          ▼                      ▼                      ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│AndroidAudioHandler│  │WindowsSmtcHandler│  │  media_kit      │
│(audio_service)   │  │(smtc_windows)    │  │  Player         │
│- 通知栏控制      │  │- 媒体键控制      │  │                 │
│- 后台播放        │  │- SMTC 集成       │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### 4.2 AudioController 核心方法

```dart
class AudioController extends StateNotifier<PlayerState> {
  // 播放模式
  PlayMode _playMode = PlayMode.queue;  // queue/temporary/detached/mix

  // 队列播放
  Future<void> playFromQueue(int index);
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0});

  // 临时播放（不修改队列）
  Future<void> playTemporary(Track track);

  // Mix 模式播放
  Future<void> playMix(String playlistId, String seedVideoId, String title);

  // 播放控制
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> seekTo(Duration position);
  Future<void> seekToProgress(double progress);  // 0.0-1.0
  Future<void> next();
  Future<void> previous();

  // 音量控制
  Future<void> setVolume(double volume);
  Future<void> toggleMute();  // 带记忆的静音切换

  // 循环模式
  Future<void> setLoopMode(LoopMode mode);
  Future<void> toggleShuffle();

  // 队列操作
  Future<void> addToQueue(Track track);
  Future<void> addNext(Track track);
  Future<void> removeFromQueue(int index);
  Future<void> moveInQueue(int oldIndex, int newIndex);
  Future<void> clearQueue();
}
```

### 4.3 音源解析 (SourceManager)

```dart
class SourceManager {
  final BilibiliSource _bilibiliSource;
  final YouTubeSource _youtubeSource;

  /// 从 URL 解析 Track
  Future<Track?> parseUrl(String url);

  /// 搜索
  Future<List<Track>> search(String query, {
    SourceType? sourceType,
    int page = 1,
    String? sortBy,
  });

  /// 获取音频流 URL
  Future<AudioStreamInfo> getAudioStream(Track track);

  /// 获取视频详情
  Future<VideoDetail> getVideoDetail(Track track);

  /// 导入播放列表
  Future<List<Track>> importPlaylist(String url);

  /// 获取排行榜
  Future<List<Track>> getRanking(SourceType sourceType);
}

// 音频流信息
class AudioStreamInfo {
  final String url;
  final Map<String, String> headers;  // 包含 Referer 等
  final int? bitrate;
  final String? format;               // opus/aac
  final StreamType streamType;        // audioOnly/muxed/hls
}
```

### 4.4 下载服务 (DownloadService)

```dart
class DownloadService {
  static const int maxConcurrentDownloads = 3;

  // Windows 使用 Isolate 下载避免主线程卡顿
  final Map<int, ({Isolate isolate, ReceivePort receivePort})> _activeDownloadIsolates;

  /// 添加下载任务
  Future<AddDownloadResult> addTrackDownload(Track track, int? playlistId);

  /// 批量添加
  Future<void> addBatchDownloads(List<Track> tracks, int? playlistId);

  /// 暂停/恢复/取消
  Future<void> pauseDownload(int taskId);
  Future<void> resumeDownload(int taskId);
  Future<void> cancelDownload(int taskId);

  /// 下载流程
  /// 1. 获取音频 URL (source.getAudioStream)
  /// 2. Isolate 下载到临时文件
  /// 3. 重命名为正式文件
  /// 4. 获取 VideoDetail 并保存 metadata
  /// 5. 下载封面和头像
  /// 6. 保存下载路径到 Track
}

enum AddDownloadResult { created, taskExists, alreadyDownloaded }
```

### 4.5 排行榜缓存服务

```dart
class RankingCacheService {
  // 后台每小时自动刷新
  static const refreshInterval = Duration(hours: 1);

  /// 获取缓存的排行榜
  Future<List<Track>> getCachedRanking(SourceType sourceType);

  /// 强制刷新
  Future<void> refresh(SourceType sourceType);

  /// 启动后台刷新定时器
  void startBackgroundRefresh();
}
```

---

## 5. 响应式 UI 实现

### 5.1 断点定义

```dart
// lib/core/constants/breakpoints.dart
class Breakpoints {
  static const double compact = 600;   // Mobile
  static const double medium = 840;    // Tablet
  static const double expanded = 1200; // Desktop

  static LayoutType getLayoutType(double width) {
    if (width < compact) return LayoutType.mobile;
    if (width < medium) return LayoutType.tablet;
    return LayoutType.desktop;
  }
}

enum LayoutType { mobile, tablet, desktop }
```

### 5.2 响应式 Scaffold

```dart
// lib/ui/responsive_scaffold.dart
class ResponsiveScaffold extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutType = Breakpoints.getLayoutType(constraints.maxWidth);

        return switch (layoutType) {
          LayoutType.mobile => _MobileLayout(
            // 底部 NavigationBar
            // 底部 MiniPlayer
          ),
          LayoutType.tablet => _TabletLayout(
            // 侧边 NavigationRail
            // 底部 MiniPlayer
          ),
          LayoutType.desktop => _DesktopLayout(
            // 可收起侧边导航
            // 底部 MiniPlayer
            // 右侧 TrackDetailPanel（可拖动宽度）
          ),
        };
      },
    );
  }
}
```

### 5.3 桌面三栏布局

```
┌──────────┬────────────────────────────────┬──────────────────┐
│          │                                │                  │
│  导航栏   │         主内容区               │  TrackDetail     │
│ (可收起)  │                                │    Panel         │
│          │                                │  (可拖动宽度)    │
│  首页     │                                │                  │
│  探索     │                                │  封面            │
│  搜索     │                                │  UP主信息        │
│  音乐库   │                                │  统计数据        │
│  设置     │                                │  下一首预览      │
│          │                                │  简介            │
│          │                                │  热门评论        │
│          │                                │                  │
├──────────┴────────────────────────────────┴──────────────────┤
│  MiniPlayer (进度条 + 封面 + 标题 + 控制按钮 + 音量)          │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 MiniPlayer 组件

```dart
// lib/ui/widgets/mini_player.dart
class MiniPlayer extends ConsumerWidget {
  // 功能：
  // - 可交互进度条（点击/拖动跳转）
  // - 封面缩略图
  // - 歌曲标题和艺术家
  // - 随机/循环模式切换
  // - 上一首/播放暂停/下一首
  // - 音量滑块（桌面端）
  // - 点击展开全屏播放器
}
```

---

## 6. 主题系统

### 6.1 主题配置

```dart
// lib/ui/theme/app_theme.dart
class AppTheme {
  static ThemeData light(ColorScheme? dynamicColorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: dynamicColorScheme ?? _defaultLightColorScheme,
      // Material Design 3 组件样式
    );
  }

  static ThemeData dark(ColorScheme? dynamicColorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: dynamicColorScheme ?? _defaultDarkColorScheme,
      // Material Design 3 组件样式
    );
  }
}
```

### 6.2 动态取色 (dynamic_color)

```dart
// lib/app.dart
class App extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp.router(
          theme: AppTheme.light(lightDynamic),
          darkTheme: AppTheme.dark(darkDynamic),
          themeMode: themeMode,
          routerConfig: router,
        );
      },
    );
  }
}
```

### 6.3 主题模式切换

```dart
// lib/providers/theme_provider.dart
@riverpod
class ThemeModeNotifier extends _$ThemeModeNotifier {
  @override
  ThemeMode build() {
    // 从 Settings 加载
    final settings = ref.watch(settingsProvider);
    return switch (settings.themeModeIndex) {
      0 => ThemeMode.system,
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    // 保存到 Settings
  }
}
```

---

## 7. 平台特定实现

### 7.1 Windows 系统托盘

```dart
// lib/services/platform/tray_service.dart
class TrayService {
  Future<void> initialize() async {
    await trayManager.setIcon('assets/icons/app_icon.ico');
    await _updateContextMenu();

    // 监听托盘事件
    trayManager.addListener(_onTrayEvent);
  }

  Future<void> _updateContextMenu([Track? track]) async {
    final menu = Menu(items: [
      if (track != null)
        MenuItem(label: '♪ ${track.title}', disabled: true),
      MenuItem.separator(),
      MenuItem(key: 'play_pause', label: _isPlaying ? '暂停' : '播放'),
      MenuItem(key: 'next', label: '下一首'),
      MenuItem(key: 'previous', label: '上一首'),
      MenuItem.separator(),
      MenuItem(key: 'show', label: '显示窗口'),
      MenuItem(key: 'exit', label: '退出'),
    ]);
    await trayManager.setContextMenu(menu);
  }

  void _onTrayEvent(TrayEvent event) {
    // 处理托盘点击和菜单事件
  }
}
```

### 7.2 全局快捷键

```dart
// lib/services/platform/hotkey_service.dart
class HotkeyService {
  // 默认快捷键
  static const defaultHotkeys = {
    'play_pause': 'Ctrl+Alt+P',
    'next': 'Ctrl+Alt+Right',
    'previous': 'Ctrl+Alt+Left',
  };

  Future<void> initialize(bool enabled) async {
    if (!enabled) return;

    await _registerHotkey('play_pause', _onPlayPause);
    await _registerHotkey('next', _onNext);
    await _registerHotkey('previous', _onPrevious);
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await initialize(true);
    } else {
      await hotKeyManager.unregisterAll();
    }
  }
}
```

### 7.3 Windows SMTC 媒体键

```dart
// lib/services/audio/windows_smtc_handler.dart
class WindowsSmtcHandler {
  late SMTCWindows _smtc;

  Future<void> initialize() async {
    _smtc = SMTCWindows(
      config: const SMTCConfig(
        fastForwardEnabled: false,
        rewindEnabled: false,
        prevEnabled: true,
        nextEnabled: true,
        pauseEnabled: true,
        playEnabled: true,
        stopEnabled: false,
      ),
    );

    // 监听媒体键事件
    _smtc.buttonPressStream.listen(_onButtonPress);
  }

  Future<void> updateMetadata(Track track) async {
    await _smtc.updateMetadata(MusicMetadata(
      title: track.title,
      artist: track.artist ?? '',
      thumbnail: track.thumbnailUrl,
    ));
  }

  Future<void> updatePlaybackStatus(bool isPlaying) async {
    await _smtc.setPlaybackStatus(
      isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
    );
  }
}
```

### 7.4 Android 后台播放

```dart
// lib/services/audio/android_audio_handler.dart
class AndroidAudioHandler extends BaseAudioHandler {
  final AudioController _audioController;

  @override
  Future<void> play() => _audioController.play();

  @override
  Future<void> pause() => _audioController.pause();

  @override
  Future<void> skipToNext() => _audioController.next();

  @override
  Future<void> skipToPrevious() => _audioController.previous();

  @override
  Future<void> seek(Duration position) => _audioController.seekTo(position);

  /// 更新通知栏显示
  void updateMediaItem(Track track) {
    mediaItem.add(MediaItem(
      id: track.id.toString(),
      title: track.title,
      artist: track.artist,
      artUri: track.thumbnailUrl != null ? Uri.parse(track.thumbnailUrl!) : null,
      duration: track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null,
    ));
  }
}
```

### 7.5 应用更新服务

```dart
// lib/services/update/update_service.dart
class UpdateService {
  static const githubRepo = 'user/FMP';

  /// 检查更新
  Future<UpdateInfo?> checkForUpdate() async {
    final response = await dio.get(
      'https://api.github.com/repos/$githubRepo/releases/latest',
    );
    // 比较版本号
  }

  /// Android: 下载 APK 并调用系统安装器
  Future<void> downloadAndInstallApk(String downloadUrl) async {
    final savePath = '${(await getTemporaryDirectory()).path}/update.apk';
    await dio.download(downloadUrl, savePath, onReceiveProgress: ...);
    await OpenFilex.open(savePath);
  }

  /// Windows: 下载 ZIP 并静默替换
  Future<void> downloadAndInstallWindows(String downloadUrl) async {
    // 1. 下载 ZIP 到临时目录
    // 2. 解压到临时目录
    // 3. 启动更新脚本替换文件
    // 4. 重启应用
  }
}
```

---

## 8. 错误处理策略

### 8.1 播放错误处理

```dart
// AudioController 中的错误处理
void _handlePlaybackError(Object error, Track track) {
  if (error is PlatformException) {
    // 音频加载失败，自动跳到下一首
    _showToast('播放失败: ${track.title}');
    next();
  } else if (error is SocketException || error is DioException) {
    // 网络错误
    _showToast('网络错误，请检查网络连接');
  }
}
```

### 8.2 下载错误处理

```dart
// DownloadService 中的错误处理
void _handleDownloadError(DownloadTask task, Object error) {
  task.status = DownloadStatus.failed;
  task.errorMessage = error.toString();
  // 保存到数据库，用户可以稍后重试
}
```

### 8.3 音源失效处理

```dart
// 音频 URL 获取失败时的处理
Future<AudioStreamInfo?> _getAudioStreamWithRetry(Track track) async {
  try {
    return await sourceManager.getAudioStream(track);
  } catch (e) {
    // 记录错误，返回 null
    // 播放器会自动跳过无法播放的歌曲
    return null;
  }
}
```

---

## 9. 开发路线图

### Phase 1: 基础架构 ✅
- [x] 项目初始化与架构搭建
- [x] 数据模型与 Isar 集成
- [x] 基础 UI 框架 (Material Design 3)
- [x] 路由配置 (go_router)

### Phase 2: 核心播放 ✅
- [x] 音频播放核心 (media_kit)
- [x] 播放队列管理
- [x] 基础播放控制
- [x] 进度条和时间显示
- [x] 临时播放功能
- [x] 静音切换（带记忆）

### Phase 3: 音乐库 ✅
- [x] 歌单 CRUD
- [x] 歌曲管理
- [x] 搜索功能
- [x] Bilibili 导入
- [x] YouTube 导入

### Phase 4: 完整 UI ✅
- [x] 响应式布局（Mobile/Tablet/Desktop）
- [x] 主题系统（Material Design 3 + 动态取色）
- [x] 探索页（排行榜 + 缓存）
- [x] 歌曲详情面板（桌面端）
- [x] 迷你播放器

### Phase 5: 平台特性 ✅
- [x] Android 后台播放 (audio_service)
- [x] Android 通知栏控制
- [x] Windows 托盘 (tray_manager)
- [x] Windows SMTC 媒体键 (smtc_windows)
- [x] 全局快捷键 (hotkey_manager)
- [x] YouTube Mix/Radio 播放
- [x] 应用内更新
- [x] 音频质量设置
- [x] 下载系统（Isolate 下载）

### Phase 6: 优化与完善 ⏳
- [ ] 性能优化
- [ ] 全局快捷键自定义
- [ ] 错误监控
- [ ] 无障碍支持
- [ ] 文档完善

---

## 10. 依赖清单

```yaml
# pubspec.yaml (关键依赖)
dependencies:
  flutter:
    sdk: flutter

  # 状态管理
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1

  # 本地存储
  isar: ^3.1.0+1
  isar_flutter_libs: ^3.1.0+1
  path_provider: ^2.1.5

  # 音频播放
  media_kit: ^1.1.11
  media_kit_libs_android_audio: ^1.3.6
  media_kit_libs_windows_audio: ^1.0.10
  audio_service: ^0.18.15
  smtc_windows: ^1.1.0

  # 网络
  dio: ^5.8.0+1

  # 路由
  go_router: ^14.8.1

  # YouTube 解析
  youtube_explode_dart: ^2.3.5

  # UI
  dynamic_color: ^1.7.0
  cached_network_image: ^3.4.1
  flutter_reorderable_list: ^1.3.1

  # 桌面平台
  tray_manager: ^0.2.3
  window_manager: ^0.4.3
  hotkey_manager: ^0.2.3

  # 工具
  logger: ^2.5.0
  file_picker: ^8.3.3
  permission_handler: ^11.4.0
  rxdart: ^0.28.0
  archive: ^4.0.2
  package_info_plus: ^8.0.0
  open_filex: ^4.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.13
  riverpod_generator: ^2.6.2
  isar_generator: ^3.1.0+1
  flutter_lints: ^5.0.0
```

---

## 11. 附录

### 11.1 Bilibili API 参考

| 接口 | URL | 说明 |
|------|-----|------|
| 视频信息 | `api.bilibili.com/x/web-interface/view?bvid={bvid}` | 获取视频详情 |
| 播放 URL | `api.bilibili.com/x/player/wbi/playurl?bvid={bvid}&cid={cid}` | 获取音频流 |
| 收藏夹 | `api.bilibili.com/x/v3/fav/resource/list?media_id={fid}` | 获取收藏夹内容 |
| 搜索 | `api.bilibili.com/x/web-interface/search/type?search_type=video&keyword={q}` | 搜索视频 |
| 排行榜 | `api.bilibili.com/x/web-interface/ranking/v2?rid=3` | 音乐区排行榜 |

**注意**: Bilibili 音频流需要 `Referer: https://www.bilibili.com` 请求头。

### 11.2 YouTube 解析

使用 `youtube_explode_dart` 包进行解析：

```dart
final yt = YoutubeExplode();

// 获取视频信息
final video = await yt.videos.get(videoId);

// 获取音频流
final manifest = await yt.videos.streamsClient.getManifest(videoId);
final audioStream = manifest.audioOnly.withHighestBitrate();

// 获取 Mix 播放列表
final mixPlaylist = await yt.playlists.get('RD$videoId');
```

### 11.3 下载文件结构

```
{下载路径}/
├── {歌单名}/
│   ├── playlist_cover.jpg
│   ├── {sourceId}_{视频标题}/
│   │   ├── metadata.json          # 单P视频
│   │   ├── metadata_P01.json      # 多P视频
│   │   ├── cover.jpg
│   │   ├── audio.m4a              # 单P音频
│   │   ├── P01.m4a                # 多P音频
│   │   └── ...
│   └── ...
└── 未分类/
    └── ...
```

### 11.4 相关资源

- [Flutter 官方文档](https://flutter.dev/docs)
- [media_kit 文档](https://pub.dev/packages/media_kit)
- [Isar 文档](https://isar.dev)
- [Riverpod 文档](https://riverpod.dev)
- [Material Design 3](https://m3.material.io/)
- [Bilibili API 文档](https://github.com/SocialSisterYi/bilibili-API-collect)
- [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart)