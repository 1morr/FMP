# FMP 开发文档

本文档面向想要了解项目架构或参与开发的开发者。

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| UI 框架 | Flutter 3.10+ | Material Design 3 / Material You |
| 编程语言 | Dart 3.10+ | |
| 状态管理 | Riverpod 2.6+ | |
| 本地存储 | Isar 3.1+ | NoSQL 嵌入式数据库 |
| 音频播放 | media_kit 1.1+ | 原生 httpHeaders，无代理 |
| 网络请求 | Dio 5.8+ | |
| 路由 | go_router 14.8+ | 声明式路由 |

### 平台特定依赖

| 平台 | 依赖包 | 用途 |
|------|--------|------|
| Android | `media_kit_libs_android_audio` | 音频解码 |
| Android | `audio_service` | 后台播放与通知栏 |
| Android | `permission_handler` | 权限管理 |
| Windows | `media_kit_libs_windows_audio` | 音频解码 |
| Windows | `smtc_windows` | 系统媒体传输控件 |
| Windows | `tray_manager` | 系统托盘 |
| Windows | `window_manager` | 窗口管理 |
| Windows | `hotkey_manager` | 全局快捷键 |

---

## 项目结构

```
lib/
├── core/                          # 核心工具和配置
│   ├── constants/                 # 常量定义
│   ├── theme/                     # 主题配置（Material You）
│   └── utils/                     # 工具类（缩略图优化等）
├── data/                          # 数据层
│   ├── models/                    # Isar 数据模型
│   ├── repositories/              # 数据仓库（CRUD）
│   └── sources/                   # 音源解析器
│       ├── bilibili_source.dart   # Bilibili 音源
│       ├── youtube_source.dart    # YouTube 音源
│       └── playlist_import/       # 外部歌单导入
│           ├── netease_playlist_source.dart
│           ├── qq_music_playlist_source.dart
│           └── spotify_playlist_source.dart
├── providers/                     # Riverpod Providers
├── services/                      # 业务逻辑层
│   ├── audio/                     # 音频播放核心
│   │   ├── audio_provider.dart    # AudioController（UI 唯一入口）
│   │   ├── media_kit_audio_service.dart  # media_kit 封装
│   │   ├── queue_manager.dart     # 队列管理
│   │   └── audio_handler.dart     # Android 通知栏控制
│   ├── cache/                     # 缓存服务（排行榜等）
│   ├── download/                  # 下载管理
│   ├── import/                    # 导入服务
│   ├── library/                   # 音乐库服务
│   ├── network/                   # 网络服务
│   ├── platform/                  # 平台特性（Windows 桌面）
│   ├── radio/                     # 直播/电台控制
│   ├── search/                    # 搜索服务
│   └── update/                    # 应用内更新
├── ui/                            # UI 层
│   ├── layouts/                   # 响应式布局
│   ├── pages/                     # 页面
│   │   ├── home/                  # 首页
│   │   ├── explore/               # 探索页（排行榜）
│   │   ├── search/                # 搜索页
│   │   ├── player/                # 全屏播放器
│   │   ├── queue/                 # 播放队列
│   │   ├── history/               # 播放历史
│   │   ├── library/               # 音乐库、歌单详情、已下载
│   │   ├── live_room/             # 直播间
│   │   ├── radio/                 # 电台页面
│   │   ├── settings/              # 设置
│   │   └── download/              # 下载相关
│   └── widgets/                   # 可复用组件
├── app.dart                       # 应用入口（路由配置）
└── main.dart                      # 主程序
```

---

## 架构设计

### 三层音频架构

```
UI Layer (player_page, mini_player)
         │
         ▼
┌─────────────────────────────────────┐
│         AudioController             │  ← UI 唯一入口
│   (状态管理、业务逻辑、临时播放)       │
└─────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│MediaKitAudioSvc │  │  QueueManager   │
│(底层播放控制)    │  │(队列、Shuffle)  │
└─────────────────┘  └─────────────────┘
         │
         ▼
┌─────────────────┐
│    media_kit     │  ← 原生 httpHeaders
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

---

## 数据模型

| 模型 | 说明 |
|------|------|
| Track | 歌曲/音频实体 |
| Playlist | 歌单 |
| PlayQueue | 播放队列（含 Mix 模式状态） |
| Settings | 应用设置（含音质配置） |
| SearchHistory | 搜索历史 |
| DownloadTask | 下载任务 |

---

## 音源支持

### Bilibili
- 视频音频提取（DASH / durl 格式）
- 多P视频支持
- 直播间音频流
- 需 `Referer: https://www.bilibili.com` 请求头

### YouTube
- 视频音频提取（`youtube_explode_dart`）
- YouTube Mix/Radio 动态播放列表（InnerTube API）
- 音频格式优先级：audio-only > muxed > HLS
- 支持 Opus / AAC 格式选择

### 外部歌单导入
- **网易云音乐** - 标准链接 / 短链接
- **QQ音乐** - 多种链接格式，自带签名算法
- **Spotify** - Client Credentials 认证

---

## UI 页面

| 页面 | 路径 | 功能 |
|------|------|------|
| 首页 | `/` | 快捷操作、排行榜预览、当前播放 |
| 探索 | `/explore` | Bilibili / YouTube 完整排行榜 |
| 搜索 | `/search` | 多源搜索、搜索历史、分P展开 |
| 播放器 | `/player` | 全屏播放器 |
| 队列 | `/queue` | 播放队列管理、拖拽排序 |
| 播放历史 | `/history` | 时间轴列表、统计卡片 |
| 音乐库 | `/library` | 歌单管理 |
| 歌单详情 | `/library/:id` | 歌曲列表、下载、多P分组 |
| 已下载 | `/library/downloaded` | 本地文件浏览 |
| 设置 | `/settings` | 应用设置 |
| 音频设置 | `/settings/audio` | 音质等级、格式优先级 |
| 下载管理 | `/settings/download-manager` | 下载任务管理 |

---

## 开发规则

### 重要规则

1. **UI 只能调用 AudioController**，不能直接调用 AudioService
2. **静音必须使用 `toggleMute()`**，不要用 `setVolume(0)`
3. **临时播放使用 `playTemporary()`**，不是 `playTrack()`
4. **Shuffle 模式下显示 `upcomingTracks`**，不要手动计算下一首
5. **进度条拖动只在 `onChangeEnd` 触发 seek**
6. **图片加载统一使用 `TrackThumbnail` / `ImageLoadingService`**

### 常用命令

```bash
flutter run                          # 运行应用
flutter analyze                      # 静态分析
flutter test                         # 运行测试
flutter pub run build_runner build --delete-conflicting-outputs  # 代码生成
flutter clean                        # 清理构建产物
```

---

## 更多资源

- [构建指南](build-guide.md) - 本地编译 Android APK 和 Windows 安装包
- [CLAUDE.md](../CLAUDE.md) - AI 辅助开发指南（详细架构和设计决策）
