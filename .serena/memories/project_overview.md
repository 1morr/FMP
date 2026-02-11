# FMP (Flutter Music Player) - 项目概述

## 项目目的
跨平台音乐播放器，支持从 Bilibili 和 YouTube 获取音源，提供统一的播放体验，支持离线播放、大规模播放队列管理和完整的音乐库功能。

## 目标平台
- **MVP**: Android, Windows
- **未来**: iOS, Linux, macOS

## 技术栈

| 层级 | 技术 | 版本 |
|------|------|------|
| UI 框架 | Flutter | 3.x |
| 设计系统 | Material Design 3 | Material You |
| 编程语言 | Dart | 3.10+ |
| 状态管理 | Riverpod | 2.6.x |
| 本地存储 | Isar | 3.1.x |
| 音频播放 | media_kit | 1.1.x (直接使用，原生 httpHeaders) |
| 后台播放 | audio_service | 0.18.x (Android 媒体通知) |
| Windows 媒体 | smtc_windows | 1.1.x (Windows SMTC 媒体键) |
| 网络请求 | Dio | 5.8.x |
| 路由 | go_router | 14.8.x |

### 平台特定依赖
- **Windows**: tray_manager, window_manager, hotkey_manager, media_kit_libs_windows_audio, smtc_windows
- **Android**: media_kit_libs_android_audio, audio_service, permission_handler

> **注意**: 音频播放直接使用 `media_kit`，原生支持 `httpHeaders`，解决了原 `just_audio_media_kit` 代理方案的兼容性问题。详见 `audio_system` memory。

## 开发进度
- **Phase 1**: 基础架构 ✅ 已完成
- **Phase 2**: 核心播放 ✅ 已完成
- **Phase 3**: 音乐库 ✅ 已完成
- **Phase 4**: 完整 UI 🔄 进行中 (大部分完成)
- **Phase 5**: 平台特性 🔄 进行中 (YouTube音源已完成, 桌面特性已完成, 待快捷键自定义)
- **Phase 6**: 优化与完善 ⏳ 待开始

### 代码重构进度 (REFACTORING_PLAN.md)
- **Refactor Phase 1**: 性能优化 ✅ 已完成
- **Refactor Phase 2**: 代码质量 ✅ 已完成
- **Refactor Phase 3**: 基础设施 ✅ 已完成 (测试、下载优化、离线模式)
- **下载系统重构**: ✅ 已完成 (2026-01-14)
  - 预计算路径模式
  - DownloadStatusCache 缓存机制
  - 移除 syncDownloadedFiles

## 核心功能
1. **音源集成**: Bilibili (已实现), YouTube (已实现 - youtube_explode_dart)
2. **播放控制**: 播放/暂停、进度控制、播放速度、播放模式
3. **播放队列**: 持久化队列、拖拽排序、断点续播
4. **音乐库**: 歌单管理、外部导入、搜索功能
5. **临时播放**: 搜索/歌单点击歌曲临时播放，完成后恢复原队列
6. **静音切换**: 带记忆的静音功能，恢复原音量
7. **记住播放位置**: 长视频自动记忆播放位置，重新播放时从上次位置继续
8. **桌面特性**: 系统托盘、全局快捷键、窗口管理 ✅
9. **移动特性**: 后台播放、通知栏控制 ✅ (上一首/下一首已实现)
10. **下载管理**: 离线下载、批量下载、预计算路径、下载状态缓存、进度节流
11. **网络图片缓存**: CachedNetworkImage 本地缓存封面图片
12. **YouTube Mix/Radio 播放**: 支持導入和播放 YouTube Mix 播放列表（動態無限播放列表），使用 InnerTube API，狀態跨重啟持久化
13. **外部歌单导入**: 支持从网易云音乐、QQ音乐、Spotify 导入歌单，智能搜索匹配到 Bilibili/YouTube
14. **直播间/电台**: Bilibili 直播间音频播放、直播流刷新
15. **应用内更新**: GitHub Releases 自动检查更新，支持 Android APK / Windows ZIP 下载安装
16. **播放历史**: 时间轴列表、统计卡片、筛选排序
17. **音频质量设置**: 用户可配置音质等级、格式优先级、流类型优先级

## 重要记忆文件
- `audio_system` - 音频系统详细架构文档（含记住播放位置、Mix 模式功能）
- `architecture` - 整体架构概览
- `code_style` - 代码风格规范
- `download_system` - 下载系统文档（含进度节流机制）
- `image_handling` - 图片处理与缓存
- `ui_pages_details` - UI 页面详情
- `mix_playlist_design` - YouTube Mix 播放列表完整設計與實現文檔
- `playlist_import_feature_plan` - 外部歌单导入功能设计文档
- `update_system` - 应用内更新系统文档

## 重要文档
- `docs/PRD.md` - 产品需求文档
- `docs/TECHNICAL_SPEC.md` - 技术规格文档
- `docs/WORKFLOW.md` - 实现工作流
