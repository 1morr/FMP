# FMP 项目 - 架构概览

## 分层架构图

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
│  │AudioProvider │ │PlaylistProv. │ │SearchProvider│    ...      │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Service Layer                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │AudioService │ │PlaylistSvc  │ │ SearchSvc   │ │ ImportSvc │  │
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

## 核心模块

### Data Models (Isar Collections)
| 模型 | 文件 | 说明 |
|------|------|------|
| Track | `data/models/track.dart` | 歌曲/音频实体 |
| Playlist | `data/models/playlist.dart` | 歌单 |
| PlayQueue | `data/models/play_queue.dart` | 播放队列 |
| Settings | `data/models/settings.dart` | 应用设置 |
| SearchHistory | `data/models/search_history.dart` | 搜索历史 |
| DownloadTask | `data/models/download_task.dart` | 下载任务 |

### Repositories
| 仓库 | 文件 | 职责 |
|------|------|------|
| TrackRepository | `data/repositories/track_repository.dart` | Track CRUD |
| PlaylistRepository | `data/repositories/playlist_repository.dart` | Playlist CRUD |
| QueueRepository | `data/repositories/queue_repository.dart` | Queue 持久化 |
| SettingsRepository | `data/repositories/settings_repository.dart` | Settings 管理 |

### Sources (音源解析)
| 音源 | 文件 | 状态 |
|------|------|------|
| BaseSource | `data/sources/base_source.dart` | 抽象基类 |
| BilibiliSource | `data/sources/bilibili_source.dart` | ✅ 已实现 |
| YouTubeSource | - | ⏳ 待实现 |

### Services
| 服务 | 文件 | 职责 |
|------|------|------|
| AudioService | `services/audio/audio_service.dart` | 底层音频播放（封装 just_audio） |
| AudioController | `services/audio/audio_provider.dart` | 高层音频控制（UI 使用） |
| QueueManager | `services/audio/queue_manager.dart` | 播放队列管理 |
| PlaylistService | `services/library/playlist_service.dart` | 歌单业务逻辑 |
| SearchService | `services/search/search_service.dart` | 多源搜索 |
| ImportService | `services/import/import_service.dart` | 外部导入 |

> **详细音频系统文档见：** `audio_system` 记忆文件

### Providers
| Provider | 文件 | 类型 |
|----------|------|------|
| databaseProvider | `providers/database_provider.dart` | FutureProvider<Isar> |
| audioServiceProvider | `services/audio/audio_provider.dart` | Provider<AudioService> |
| playlistProvider | `providers/playlist_provider.dart` | StateNotifierProvider |
| searchProvider | `providers/search_provider.dart` | StateNotifierProvider |

## UI 结构

### 页面 (Pages)
| 页面 | 路径 | 文件 |
|------|------|------|
| 首页 | `/` | `ui/pages/home/home_page.dart` |
| 搜索 | `/search` | `ui/pages/search/search_page.dart` |
| 播放器 | `/player` | `ui/pages/player/player_page.dart` |
| 队列 | `/queue` | `ui/pages/queue/queue_page.dart` |
| 音乐库 | `/library` | `ui/pages/library/library_page.dart` |
| 歌单详情 | `/library/:id` | `ui/pages/library/playlist_detail_page.dart` |
| 设置 | `/settings` | `ui/pages/settings/settings_page.dart` |

### 路由配置
- 使用 `go_router` 进行声明式路由
- Shell Route 包含底部导航的页面
- 播放器页面独立于 Shell (全屏)

## 响应式断点

| 类型 | 宽度 | 导航 |
|------|------|------|
| Mobile | < 600dp | 底部导航栏 |
| Tablet | 600-1200dp | 底部/侧边导航 |
| Desktop | > 1200dp | 侧边导航 + 三栏布局 |
