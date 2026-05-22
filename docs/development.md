# FMP 开发文档

本文档面向想了解项目结构或参与开发的贡献者。更详细的 agent 规则、数据库迁移规则和项目特定编码约束维护在 [AGENTS.md](../AGENTS.md)。

## 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| UI | Flutter / Dart | Material 3，Android + Windows 响应式 UI |
| 状态管理 | Riverpod 2.x | Providers、StateNotifier、FutureProvider、StreamProvider |
| 本地存储 | Isar 3.x | 持久化应用数据和设置 |
| 路由 | go_router | 声明式路由 |
| 网络 | Dio | 音源 API 和媒体请求 |
| 国际化 | slang | 生成类型安全翻译代码 |
| 音频 | just_audio / media_kit | Android 使用 just_audio，桌面使用 media_kit |
| 加密 | crypto / encrypt / pointycastle | 网易云 eapi/weapi 支持 |

## 平台分工

| 平台 | 音频后端 | 平台特性 |
|------|----------|----------|
| Android | `JustAudioService` / ExoPlayer | 后台播放、通知栏控制、存储权限 |
| Windows | `MediaKitAudioService` / libmpv | 音频设备切换、SMTC、托盘、全局快捷键、歌词子窗口 |

Windows 本地构建还需要部分原生工具：

| 工具 | 相关插件 | 用途 |
|------|----------|------|
| NuGet CLI | `flutter_inappwebview_windows` | 下载 WebView2、WIL 等原生依赖 |
| Rust toolchain | `smtc_windows` | 构建 cargokit 原生库 |

安装和排错细节见 [构建指南](build-guide.md)。

## 架构地图

FMP 大体采用 UI -> Provider/Controller -> Service -> Data/Source 的分层。最重要的边界是音频边界：UI 必须调用 `AudioController`，不要直接调用 `AudioService`。

```
UI pages/widgets
  -> Riverpod providers/controllers
  -> services/* 业务逻辑
  -> data/repositories 访问 Isar
  -> data/sources 访问外部平台
```

关键目录：

```
lib/
├── core/          # 常量、主题、共享服务、工具
├── data/          # models、repositories、外部音源解析
├── providers/     # Riverpod provider 定义
├── services/      # audio、account、lyrics、download、library、update 等业务逻辑
├── ui/            # pages、widgets、layouts、windows
├── i18n/          # slang 翻译资源
├── app.dart       # app 入口和路由接线
└── main.dart      # 进程启动和平台初始化
```

更完整的文件结构和当前 provider 规则见 [AGENTS.md](../AGENTS.md#file-structure-highlights)。

## 数据模型分类

`lib/data/models/` 里的文件不全是 Isar collection。

### 持久化 Isar Collections

以下 collection 注册在 `lib/providers/database_provider.dart`。字段变化时需要检查迁移/default repair，并同步检查数据库查看器。

数据库文件通过 `openFmpDatabase()` 打开，固定存放在应用 documents 目录下的 `FMP/` 子目录中。不要在其他位置手写 `getApplicationDocumentsDirectory()/fmp_database.isar`；需要路径或大小信息时复用 `resolveFmpDatabaseDirectory()` 和 `fmpDatabaseFileName`。

| Collection | 用途 |
|------------|------|
| `Track` | 歌曲/音频实体和音源元数据 |
| `Playlist` | 本地/导入歌单元数据 |
| `PlayQueue` | 队列、Mix 模式、播放持久化 |
| `Settings` | 应用设置、音质、认证、歌词、刷新间隔 |
| `SearchHistory` | 搜索历史 |
| `DownloadTask` | 下载队列/任务状态 |
| `PlayHistory` | 播放历史 |
| `RadioStation` | 电台/直播站点 |
| `LyricsMatch` | Track 到歌词源的匹配记录 |
| `LyricsTitleParseCache` | 运行期 AI 标题解析缓存 |
| `Account` | 平台登录/账号状态 |

### 非持久化 DTO / Value Objects

这些类型放在 data model 附近，是因为它们描述音源或 UI 数据；除非显式注册为 Isar schema，否则不需要数据库迁移。

| 类型 | 用途 |
|------|------|
| `LiveRoom` / `LiveSearchResult` | Bilibili 直播间搜索，以及转换成 radio/track |
| `VideoDetail` / `VideoPage` / `VideoComment` | 详情面板和元数据显示 |
| `HotkeyConfig` / `HotkeyBinding` | 通过 `Settings` 保存的 JSON 桌面快捷键配置 |

## 音源支持

| 音源 | 当前支持 |
|------|----------|
| Bilibili | 视频音频、多 P 视频、直播间音频、收藏夹导入 |
| YouTube | 视频音频、播放列表、Mix/Radio 动态队列、Opus/AAC 偏好 |
| Netease | 搜索、歌曲详情、eapi 音频流、歌单导入、VIP/可用性处理 |
| 外部歌单导入 | Netease、QQ Music、Spotify 搜索匹配导入 |

直接音源的 API 异常共享 `SourceApiException`，播放层可以统一处理不可用、限流、需要登录和网络错误等情况。

## 歌词系统概览

自动歌词匹配使用 `Settings.lyricsSourcePriorityList` 中的当前配置顺序，并跳过被禁用的歌词源。默认顺序是 Netease -> QQ Music -> lrclib，且默认自动匹配禁用 lrclib。

高层流程：

1. 已有 `LyricsMatch` 记录时直接用缓存。
2. 网易云 track 直接用 sourceId 获取歌词。
3. 导入自 Netease/QQ Music 的 track 用原平台 ID 直取。
4. 按用户配置的歌词源顺序搜索。
5. 根据设置选择是否使用 AI 标题解析或 AI 高级匹配。

自动匹配默认只接受同步歌词，除非开启 `allowPlainLyricsAutoMatch`。桌面歌词窗口使用独立 Flutter engine，关闭时隐藏而不是销毁。

## 路由

重要路由常量在 `lib/ui/router.dart`。

| 区域 | 路由 |
|------|------|
| 主导航 | `/`、`/search`、`/explore`、`/queue`、`/history`、`/library`、`/radio`、`/settings` |
| 详情页 | `/player`、`/radio-player`、`/library/:id`、`/library/downloaded`、`/library/downloaded/:folderName` |
| 设置 | `/settings/audio`、`/settings/lyrics-source`、`/settings/download-manager`、`/settings/account`、`/settings/account/bilibili-login`、`/settings/account/youtube-login`、`/settings/account/netease-login`、`/settings/user-guide`、`/settings/developer` |
| 开发者工具 | `/settings/developer/database`、`/settings/developer/logs` |

## 响应式布局

权威断点定义在 `lib/core/constants/breakpoints.dart`：

| 布局 | 宽度 | 导航方式 |
|------|------|----------|
| Mobile | `< 600dp` | 底部导航 |
| Tablet | `600-1200dp` | 紧凑侧边导航栏 |
| Desktop | `>= 1200dp` | 可收起侧边导航栏 + 可选详情面板 |

## 常用命令

```bash
flutter run
flutter run -d windows
flutter analyze
flutter test
flutter pub run build_runner build --delete-conflicting-outputs
dart run slang
```

本地 release 构建见 [构建指南](build-guide.md)，CI/release 行为见 [构建与发布指南](build-and-release.md)。

## 开发规则摘要

这里只保留简短摘要。详细当前规则见 [AGENTS.md](../AGENTS.md)。

- UI 代码调用 `AudioController`，不要直接调用平台音频 service。
- 修改 Isar collection 或注册 schema 时，需要检查迁移/default repair 和数据库查看器。
- UI 图片加载应使用 `TrackThumbnail`、`TrackCover` 或 `ImageLoadingService`。
- 公共 track actions 应走 `TrackActionCoordinator` 和共享 menu builders。
- 文件系统 `FutureProvider` 数据源被修改后必须 invalidate。
- 列表/网格重复项应使用稳定 key。
- `AppBar.actions` 如果最后一个是 `IconButton`，末尾应加 `SizedBox(width: 8)`。

## 更多文档

- [文档地图](README.md)
- [构建指南](build-guide.md)
- [构建与发布指南](build-and-release.md)
- [VM Service 调试指南](debugging-with-vm-service.md)
- [Agent 规则](../AGENTS.md)
