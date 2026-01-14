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
| 音频播放 | just_audio | 0.9.x |
| 后台播放 | just_audio_background | 0.0.x |
| 网络请求 | Dio | 5.8.x |
| 路由 | go_router | 14.8.x |

### 平台特定依赖
- **Windows/Linux**: tray_manager, window_manager, hotkey_manager, just_audio_media_kit, media_kit_libs_windows_audio
- **Android**: just_audio_background, permission_handler

> **注意**: Windows 平台使用 `just_audio_media_kit` 而非 `just_audio_windows`，
> 后者存在平台线程问题，会导致长视频 seek 时消息队列溢出。详见 `audio_system` memory。

## 开发进度
- **Phase 1**: 基础架构 ✅ 已完成
- **Phase 2**: 核心播放 ✅ 已完成
- **Phase 3**: 音乐库 ✅ 已完成
- **Phase 4**: 完整 UI 🔄 进行中 (大部分完成)
- **Phase 5**: 平台特性 ⏳ 待开始
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
1. **音源集成**: Bilibili (已实现), YouTube (待实现)
2. **播放控制**: 播放/暂停、进度控制、播放速度、播放模式
3. **播放队列**: 持久化队列、拖拽排序、断点续播
4. **音乐库**: 歌单管理、外部导入、搜索功能
5. **临时播放**: 搜索/歌单点击歌曲临时播放，完成后恢复原队列
6. **静音切换**: 带记忆的静音功能，恢复原音量
7. **桌面特性**: 系统托盘、全局快捷键 (待实现)
8. **移动特性**: 后台播放、通知栏控制 (待实现)
9. **下载管理**: 离线下载、批量下载、预计算路径、下载状态缓存

## 重要记忆文件
- `audio_system` - 音频系统详细架构文档
- `architecture` - 整体架构概览
- `code_style` - 代码风格规范
- `download_system_details` - 下载系统详细文档
- `download_system_impl` - 下载系统实现状态
- `code_issues_2026-01-14` - 代码问题与优化建议

## 重要文档
- `docs/PRD.md` - 产品需求文档
- `docs/TECHNICAL_SPEC.md` - 技术规格文档
- `docs/WORKFLOW.md` - 实现工作流
