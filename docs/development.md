# FMP 开发文档

本文档面向想要了解项目架构或参与开发的开发者。

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| UI 框架 | Flutter (Dart ≥3.5) | Material Design 3 / Material You |
| 状态管理 | Riverpod 2.6+ | |
| 本地存储 | Isar 3.1+ | NoSQL 嵌入式数据库 |
| 音频后端 | just_audio (Android) / media_kit (桌面) | 平台分离架构 |
| 网络请求 | Dio 5.8+ | |
| 路由 | go_router 14.8+ | 声明式路由 |
| 国际化 | slang | 编译时类型安全 i18n |
| 加密 | crypto + encrypt + pointycastle | 网易云 eapi/weapi 加密 |

### 音频后端（平台分离架构）

| 平台 | 后端 | 说明 |
|------|------|------|
| Android | `just_audio` (ExoPlayer) | 省内存 (~10-15MB)，原生通知栏控制 |
| Windows/Linux | `media_kit` (libmpv) | 原生 httpHeaders 支持，支持设备切换 |

### 平台特定依赖

| 平台 | 依赖包 | 用途 |
|------|--------|------|
| Android | `audio_service` | 后台播放与通知栏 |
| Android | `permission_handler` | 权限管理 |
| Android | `flutter_inappwebview` | WebView 登录 |
| Windows | `media_kit_libs_windows_audio` | 音频解码 |
| Windows | `smtc_windows` | 系统媒体传输控件 |
| Windows | `tray_manager` | 系统托盘 |
| Windows | `window_manager` | 窗口管理 |
| Windows | `hotkey_manager` | 全局快捷键 |
| Windows | `desktop_multi_window` | 歌词弹出窗口 |
| Windows | `launch_at_startup` | 开机自启 |

---

## 项目结构

```
lib/
├── core/                          # 核心工具和配置
│   ├── constants/                 # 常量定义
│   │   ├── app_constants.dart     # 应用级常量（超时、重试等）
│   │   └── ui_constants.dart      # UI 常量（间距、圆角、动画等）
│   ├── theme/                     # 主题配置（Material You）
│   ├── services/                  # 核心服务（Toast、图片加载）
│   └── utils/                     # 工具类
│       ├── thumbnail_url_utils.dart   # 缩略图 URL 优化
│       ├── netease_crypto.dart        # 网易云 eapi/weapi 加密
│       └── auth_retry_utils.dart      # 认证 headers 构建
├── data/                          # 数据层
│   ├── models/                    # Isar 数据模型
│   ├── repositories/              # 数据仓库（CRUD）
│   └── sources/                   # 音源解析器
│       ├── base_source.dart       # 音源抽象基类
│       ├── bilibili_source.dart   # Bilibili 音源
│       ├── youtube_source.dart    # YouTube 音源
│       ├── netease_source.dart    # 网易云音乐音源
│       ├── source_exception.dart  # 统一异常基类
│       ├── source_provider.dart   # SourceManager + Providers
│       └── playlist_import/       # 外部歌单导入（搜索匹配）
│           ├── netease_playlist_source.dart
│           ├── qq_music_playlist_source.dart
│           └── spotify_playlist_source.dart
├── providers/                     # Riverpod Providers
├── services/                      # 业务逻辑层
│   ├── audio/                     # 音频播放核心
│   │   ├── audio_provider.dart    # AudioController（UI 唯一入口）
│   │   ├── audio_service.dart     # 抽象 AudioService 接口
│   │   ├── just_audio_service.dart      # Android: ExoPlayer
│   │   ├── media_kit_audio_service.dart # 桌面: libmpv
│   │   ├── audio_types.dart       # 统一播放状态类型
│   │   ├── queue_manager.dart     # 队列管理、Shuffle、持久化
│   │   └── audio_handler.dart     # Android 通知栏控制
│   ├── account/                   # 账号管理
│   │   ├── bilibili_account_service.dart
│   │   ├── youtube_account_service.dart
│   │   ├── netease_account_service.dart
│   │   └── netease_playlist_service.dart
│   ├── lyrics/                    # 歌词系统
│   │   ├── lyrics_auto_match_service.dart  # 自动匹配（多源）
│   │   ├── lrclib_source.dart     # lrclib.net
│   │   ├── netease_source.dart    # 网易云歌词
│   │   ├── qqmusic_source.dart    # QQ音乐歌词
│   │   ├── lyrics_cache_service.dart
│   │   ├── lyrics_window_service.dart  # 桌面歌词弹出窗口
│   │   ├── lrc_parser.dart
│   │   └── title_parser.dart
│   ├── cache/                     # 缓存服务（排行榜后台刷新）
│   ├── download/                  # 下载管理
│   ├── import/                    # URL 导入 + 外部歌单导入
│   ├── radio/                     # 直播/电台控制
│   ├── platform/                  # 平台特性（桌面窗口管理）
│   └── update/                    # 应用内更新（GitHub Releases）
├── ui/                            # UI 层
│   ├── layouts/                   # 响应式布局
│   ├── pages/                     # 页面
│   │   ├── home/                  # 首页（快捷操作、排行榜预览）
│   │   ├── explore/               # 探索页（完整排行榜）
│   │   ├── search/                # 搜索页（三源搜索）
│   │   ├── player/                # 全屏播放器
│   │   ├── queue/                 # 播放队列
│   │   ├── history/               # 播放历史
│   │   ├── library/               # 音乐库、歌单详情、已下载、导入预览
│   │   ├── live_room/             # 直播间（歌词匹配搜索）
│   │   ├── radio/                 # 电台页面
│   │   ├── download/              # 下载相关
│   │   └── settings/              # 设置（含子页面）
│   ├── widgets/                   # 可复用组件
│   └── windows/                   # 子窗口入口（歌词弹出窗口）
├── i18n/                          # 国际化资源
│   ├── zh-CN/                     # 简体中文
│   ├── zh-TW/                     # 繁体中文
│   └── en/                        # 英文
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
│  AudioService   │  │  QueueManager   │
│  (抽象接口)      │  │(队列、Shuffle)  │
└────────┬────────┘  └─────────────────┘
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌────────────┐
│just_   │ │media_kit   │
│audio   │ │AudioService│
│Service │ │            │
│(Android│ │(Windows/   │
│)       │ │Linux)      │
└────────┘ └────────────┘
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
│  AudioService, AccountService, etc.     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│          Data Layer                     │
│  Repositories, Sources, Models          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│        External Layer                   │
│  Isar, media_kit, just_audio, Dio      │
└─────────────────────────────────────────┘
```

---

## 数据模型

| 模型 | 说明 |
|------|------|
| Track | 歌曲/音频实体（支持 bilibili / youtube / netease 三种 SourceType） |
| Playlist | 歌单（含所有者信息、导入源、刷新设置） |
| PlayQueue | 播放队列（含 Mix 模式状态、播放位置持久化） |
| Settings | 应用设置（音质配置、认证设置、流优先级） |
| Account | 平台账号信息（登录状态、用户信息、VIP 状态） |
| RadioStation | 电台/直播站点 |
| PlayHistory | 播放历史记录 |
| SearchHistory | 搜索历史 |
| DownloadTask | 下载任务 |
| LyricsMatch | 歌词匹配记录（Track ↔ 歌词源） |
| LiveRoom | 直播间信息 |
| HotkeyConfig | 全局快捷键配置（桌面端） |
| VideoDetail | 视频详情（评论区等） |

---

## 音源支持

### Bilibili（直接音源）
- 视频音频提取（DASH 音频流 / durl 混流）
- 多P视频支持
- 直播间音频流（HLS）
- 收藏夹导入
- 需 `Referer: https://www.bilibili.com` 请求头

### YouTube（直接音源）
- 视频音频提取（`youtube_explode_dart` + InnerTube API）
- YouTube Mix/Radio 动态无限播放列表
- 播放列表导入
- 音频格式优先级：audio-only (androidVr) > muxed > HLS
- 支持 Opus / AAC 格式选择

### 网易云音乐（直接音源）
- 歌曲搜索（`/api/cloudsearch/pc`）
- 歌曲播放（eapi 加密获取音频流）
- 歌单导入（支持标准链接 / 短链接 `163cn.tv`）
- VIP 歌曲标识（`fee` 字段判断）
- 歌词直接获取（无需搜索匹配）
- 账号系统（QR 码登录 / Cookie 登录）

### 外部歌单导入（搜索匹配模式）
- **网易云音乐** - 提取歌曲信息后通过搜索匹配到 Bilibili/YouTube 播放
- **QQ音乐** - 多种链接格式，自带签名加密
- **Spotify** - Embed 页面解析，无需认证

---

## 歌词系统

多源自动匹配，优先级如下：

1. 已有匹配记录 → 直接使用缓存
2. 网易云歌曲 → 直接用 sourceId 获取歌词（跳过搜索）
3. 原平台 ID 直取（导入歌单保存的 originalSongId）
4. 网易云搜索匹配
5. QQ音乐搜索匹配
6. lrclib.net fallback

支持桌面端歌词弹出窗口（独立 Flutter engine，hide-instead-of-destroy）。

---

## 账号系统

| 平台 | 登录方式 | 特性 |
|------|----------|------|
| Bilibili | WebView Cookie 提取 | Cookie 自动刷新、收藏夹访问 |
| YouTube | WebView Cookie 提取 | InnerTube 认证、SAPISIDHASH |
| 网易云音乐 | QR 码 / WebView Cookie | MUSIC_U 长效 Token、eapi 加密 |

每个平台可独立配置是否在播放时使用登录状态（`useAuthForPlay`）。

---

## UI 页面与路由

| 页面 | 路径 | 功能 |
|------|------|------|
| 首页 | `/` | 快捷操作、排行榜预览、当前播放 |
| 探索 | `/explore` | Bilibili / YouTube 完整排行榜 |
| 搜索 | `/search` | Bilibili / YouTube / 网易云 三源搜索 |
| 播放器 | `/player` | 全屏播放器 |
| 队列 | `/queue` | 播放队列管理、拖拽排序 |
| 电台 | `/radio` | 电台列表 |
| 电台播放 | `/radio-player` | 电台播放详情 |
| 播放历史 | `/history` | 时间轴列表、统计卡片 |
| 音乐库 | `/library` | 歌单管理 |
| 歌单详情 | `/library/:id` | 歌曲列表、下载、多P分组 |
| 已下载 | `/library/downloaded` | 本地文件浏览 |
| 设置 | `/settings` | 应用设置 |
| 音频设置 | `/settings/audio` | 音质等级、格式/流优先级 |
| 歌词源设置 | `/settings/lyrics-source` | 歌词匹配源配置 |
| 下载管理 | `/settings/download-manager` | 下载任务管理 |
| 使用指南 | `/settings/user-guide` | 应用使用说明 |
| 账号管理 | `/settings/account` | 多平台账号登录/登出 |
| Bilibili 登录 | `/settings/account/bilibili-login` | WebView 登录 |
| YouTube 登录 | `/settings/account/youtube-login` | WebView 登录 |
| 网易云登录 | `/settings/account/netease-login` | QR码 / WebView 登录 |
| 开发者选项 | `/settings/developer` | 调试工具 |
| 数据库查看 | `/settings/developer/database` | Isar 数据库检查 |
| 日志查看 | `/settings/developer/logs` | 应用日志 |

---

## 开发规则

### 重要规则

1. **UI 只能调用 AudioController**，不能直接调用 AudioService
2. **静音必须使用 `toggleMute()`**，不要用 `setVolume(0)`
3. **临时播放使用 `playTemporary()`**，不是 `playTrack()`
4. **Shuffle 模式下显示 `upcomingTracks`**，不要手动计算下一首
5. **进度条拖动只在 `onChangeEnd` 触发 seek**
6. **图片加载统一使用 `TrackThumbnail` / `ImageLoadingService`**，禁止直接 `Image.network()`
7. **修改 Isar 模型后必须添加迁移逻辑**（`database_provider.dart` 中的 `_migrateDatabase()`）
8. **AppBar actions 列表末尾加 `SizedBox(width: 8)`**（当最后一项是 IconButton 时）
9. **避免在 `ListTile.leading` 中放 `Row`**（会导致滚动抖动）

### 常用命令

```bash
flutter run                          # 运行应用
flutter analyze                      # 静态分析
flutter test                         # 运行测试
flutter pub run build_runner build --delete-conflicting-outputs  # Isar 代码生成
dart run slang                       # 重新生成 i18n 文件
flutter clean                        # 清理构建产物
```

---

## 更多资源

- [构建指南](build-guide.md) - 本地编译 Android APK 和 Windows 安装包
- [CLAUDE.md](../CLAUDE.md) - AI 辅助开发指南（详细架构和设计决策）
