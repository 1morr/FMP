# FMP - Flutter Music Player

跨平台音乐播放器，支持从 Bilibili 和 YouTube 获取音源，提供统一的播放体验。

## 特性

### 核心功能
- **多音源支持**：Bilibili、YouTube
- **完整播放控制**：播放/暂停、进度控制、播放速度、循环模式
- **智能队列管理**：持久化队列、拖拽排序、断点续播
- **音乐库系统**：歌单管理、外部导入、搜索功能
- **临时播放**：搜索/歌单点击歌曲临时播放，完成后恢复原队列
- **播放位置记忆**：长视频自动记忆播放位置
- **下载管理**：离线下载、批量下载、智能路径管理
- **YouTube Mix/Radio**：支持动态无限播放列表

### 平台特性
- **Android**：后台播放、通知栏控制、媒体键支持
- **Windows**：系统托盘、全局快捷键、SMTC 媒体键支持

## 技术栈

| 层级 | 技术 | 版本 |
|------|------|------|
| UI 框架 | Flutter | 3.10+ |
| 设计系统 | Material Design 3 | - |
| 编程语言 | Dart | 3.10+ |
| 状态管理 | Riverpod | 2.6+ |
| 本地存储 | Isar | 3.1+ |
| 音频播放 | media_kit | 1.1+ |
| 网络请求 | Dio | 5.8+ |
| 路由 | go_router | 14.8+ |

### 平台特定依赖

| 平台 | 依赖包 | 用途 |
|------|--------|------|
| Android | `media_kit_libs_android_audio` | 音频播放 |
| Android | `audio_service` | 后台播放与通知栏控制 |
| Android | `permission_handler` | 权限管理 |
| Windows | `media_kit_libs_windows_audio` | 音频播放 |
| Windows | `smtc_windows` | 媒体键和 SMTC 控制 |
| Windows | `tray_manager` | 系统托盘 |
| Windows | `window_manager` | 窗口管理 |
| Windows | `hotkey_manager` | 全局快捷键 |

## 项目结构

```
lib/
├── core/                   # 核心工具和配置
│   ├── constants/          # 常量定义
│   ├── theme/              # 主题配置
│   └── utils/              # 工具类
├── data/                   # 数据层
│   ├── models/             # Isar 数据模型
│   ├── repositories/       # 数据仓库
│   └── sources/            # 音源解析器
├── providers/              # Riverpod Providers
├── services/               # 业务逻辑层
│   ├── audio/              # 音频服务
│   ├── cache/              # 缓存服务
│   ├── download/           # 下载服务
│   ├── import/             # 导入服务
│   ├── library/            # 音乐库服务
│   └── search/             # 搜索服务
├── ui/                     # UI 层
│   ├── layouts/            # 响应式布局
│   ├── pages/              # 页面
│   └── widgets/            # 可复用组件
├── app.dart                # 应用入口
└── main.dart               # 主程序
```

## 快速开始

### 环境要求
- Flutter SDK 3.10+
- Dart 3.10+
- Android Studio / VS Code
- (Windows) Rust 工具链（用于 smtc_windows）

### 安装

```bash
# 克隆项目
git clone <repository-url>
cd FMP

# 获取依赖
flutter pub get

# 生成代码（Isar 模型）
flutter pub run build_runner build --delete-conflicting-outputs

# 运行应用
flutter run
```

### 构建

```bash
# Android APK
flutter build apk

# Android App Bundle
flutter build appbundle

# Windows
flutter build windows
```

## 架构设计

### 三层音频架构

```
UI Layer (player_page, mini_player)
         │
         ▼
┌─────────────────────────────────────┐
│         AudioController             │
│   (业务逻辑、状态管理、临时播放)      │
└─────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│MediaKitAudioSvc │  │  QueueManager   │
│(底层播放控制)    │  │(队列、shuffle)  │
└─────────────────┘  └─────────────────┘
         │
         ▼
┌─────────────────┐
│   media_kit     │
│ (原生 httpHeaders)
└─────────────────┘
```

### 分层架构

```
┌─────────────────────────────────────────┐
│           UI Layer                      │
│  (Pages, Widgets, Layouts, Router)      │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│        Provider Layer (Riverpod)        │
│  AudioProvider, PlaylistProvider, etc.  │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│         Service Layer                   │
│  AudioService, PlaylistService, etc.    │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│          Data Layer                     │
│  Repositories, Sources, Models          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│        External Layer                   │
│  Isar, media_kit, Dio, Platform APIs    │
└─────────────────────────────────────────┘
```

## 核心功能说明

### 1. 音频播放系统

**设计原则**：UI 只能调用 `AudioController`，不能直接调用 `AudioService`。

| 组件 | 文件 | 职责 |
|------|------|------|
| AudioController | `services/audio/audio_provider.dart` | 统一的播放控制入口、PlayerState 状态管理、业务逻辑 |
| MediaKitAudioService | `services/audio/media_kit_audio_service.dart` | 底层 media_kit 封装、原生 httpHeaders 支持 |
| QueueManager | `services/audio/queue_manager.dart` | 播放队列管理、Shuffle/Loop 模式、持久化 |

### 2. 临时播放功能

搜索页/歌单页点击歌曲时，临时播放该歌曲，播放完成后恢复原队列位置。

**实现细节**：
- 使用 `_PlaybackContext` 统一管理播放模式（queue/temporary/detached/mix）
- 保存队列索引和位置（不保存队列内容）
- 恢复时使用当前队列，自动 clamp 索引到有效范围
- 使用请求 ID 机制防止竞态条件

### 3. Mix 播放模式（YouTube Mix/Radio）

支持 YouTube Mix/Radio 播放列表（ID 以 "RD" 开头），动态无限加载。

**关键行为**：
- 禁止 shuffle 和 addToQueue/addNext
- 自动加载更多歌曲
- 状态跨 App 重启持久化
- 使用 InnerTube `/next` API 动态获取歌曲

### 4. 下载系统

**特点**：
- **路径预计算**：导入时计算并保存下载路径
- **FileExistsCache**：避免 UI build 期间同步 IO
- **进度节流**：防止频繁 Isar 写入
- **智能路径清理**：只清理不存在的路径

### 5. 图片缓存优化

**ThumbnailUrlUtils**：自动转换高分辨率图片为适当尺寸的缩略图
- Bilibili：添加 `@{size}w.jpg` 后缀
- YouTube：选择合适质量层级 + webp 格式

**效果**：下载大小从 ~700 KB 减少到 ~20 KB

### 6. 首页排行榜缓存

**RankingCacheService**：
- 应用启动时立即获取数据
- 每小时自动后台刷新
- UI 始终显示缓存数据（无加载等待）

## 常用命令

```bash
# 运行应用
flutter run

# 代码生成（修改 Isar 模型后必须运行）
flutter pub run build_runner build --delete-conflicting-outputs

# 静态分析
flutter analyze

# 运行测试
flutter test

# 清理构建产物
flutter clean
```

## UI 页面

| 页面 | 路径 | 功能 |
|------|------|------|
| 首页 | `/` | 快捷操作、排行榜预览、当前播放 |
| 探索 | `/explore` | Bilibili/YouTube 完整排行榜 |
| 搜索 | `/search` | 多源搜索、搜索历史 |
| 播放器 | `/player` | 全屏播放器 |
| 队列 | `/queue` | 播放队列管理 |
| 播放历史 | `/history` | 时间轴列表、统计卡片 |
| 音乐库 | `/library` | 歌单管理 |
| 歌单详情 | `/library/:id` | 歌曲列表、下载 |
| 已下载 | `/library/downloaded` | 本地文件浏览 |
| 设置 | `/settings` | 应用设置 |
| 音频设置 | `/settings/audio` | 音质等级、格式优先级 |
| 下载管理 | `/settings/download-manager` | 下载任务管理 |

## 响应式断点

| 布局 | 宽度 | 导航 | 详情面板 |
|------|------|------|----------|
| Mobile | < 600dp | 底部 NavigationBar | 无 |
| Tablet | 600-840dp | 侧边 NavigationRail | 无 |
| Desktop | > 840dp | 可收起侧边导航 | 有（可拖动宽度） |

## 开发指南

### 代码风格

- 使用 `riverpod_annotation` 进行代码生成
- Isar 模型修改后必须运行 `build_runner`
- UI 统一使用 `TrackThumbnail`/`ImageLoadingService` 加载图片
- 状态判断使用 `currentTrackProvider` 统一逻辑

### 重要规则

1. **UI 只能调用 AudioController**，不能直接调用 AudioService
2. **静音必须使用 toggleMute()**，不要用 setVolume(0)
3. **临时播放使用 playTemporary()**，不是 playTrack()
4. **Shuffle 模式下显示 upcomingTracks**，不要手动计算下一首
5. **进度条拖动只在 onChangeEnd 触发 seek**

### 相关文档

- `CLAUDE.md` - 项目开发指南
- `docs/PRD.md` - 产品需求文档
- `docs/TECHNICAL_SPEC.md` - 技术规格文档
- Serena 记忆文件（audio_system, architecture, ui_coding_patterns 等）

## 数据模型

| 模型 | 文件 | 说明 |
|------|------|------|
| Track | `data/models/track.dart` | 歌曲/音频实体 |
| Playlist | `data/models/playlist.dart` | 歌单 |
| PlayQueue | `data/models/play_queue.dart` | 播放队列 |
| Settings | `data/models/settings.dart` | 应用设置 |
| SearchHistory | `data/models/search_history.dart` | 搜索历史 |
| DownloadTask | `data/models/download_task.dart` | 下载任务 |

## 音源支持

### Bilibili
- 音频 URL 解析（DASH/durl）
- 多P视频支持
- 直播流支持
- 需 `Referer` 请求头

### YouTube
- 使用 `youtube_explode_dart` 解析
- YouTube Mix/Radio 支持（InnerTube API）
- 音频优先级：audio-only > muxed > HLS

## 许可证

[待定]

## 贡献

欢迎提交 Issue 和 Pull Request。
