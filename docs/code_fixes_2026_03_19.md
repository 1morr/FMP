# Code Fixes - 2026-03-19

本次代码审查修复了以下逻辑不统一和可优化的问题。

## 1. 魔法数字提取为常量

### 1.1 `previous()` 中的 3 秒阈值
- **文件**: `lib/services/audio/audio_provider.dart:1151`
- **问题**: `previous()` 方法中使用硬编码的 `3` 秒来判断是否重新开始当前歌曲
- **修复**: 新增 `AppConstants.previousTrackThresholdSeconds` 常量
- **原因**: 与项目中其他播放控制常量保持一致，便于统一调整

### 1.2 media_kit seek 验证延迟
- **文件**: `lib/services/audio/media_kit_audio_service.dart:523`
- **问题**: `seekToLive()` 中使用硬编码的 `300ms` 等待 seek 生效
- **修复**: 新增 `AppConstants.seekVerificationDelay` 常量（与已有的 `seekStabilizationDelay` 区分）
- **原因**: `seekStabilizationDelay`（500ms）用于 seek 前等待播放器就绪，`seekVerificationDelay`（300ms）用于 seek 后验证位置变化，两者用途不同

### 1.3 Mix 播放列表加载参数
- **文件**: `lib/services/audio/audio_provider.dart:1618-1621`
- **问题**: `_loadMoreMixTracks()` 中使用硬编码的 `minNewTracksRequired=10`, `maxAttempts=10`, `sameVideoRetries=3`, `retryDelay=1s`
- **修复**: 新增 `AppConstants.mixMinNewTracksRequired`, `mixMaxLoadAttempts`, `mixSameVideoRetries`, `mixRetryDelay`
- **原因**: 集中管理 Mix 模式的配置参数，便于调优

### 1.4 下载进度更新阈值
- **文件**: `lib/services/download/download_service.dart:1079`
- **问题**: Isolate 下载中使用硬编码的 `0.05`（5%）作为进度更新间隔
- **修复**: 新增 `AppConstants.downloadProgressUpdateThreshold`
- **原因**: 与其他常量统一管理

## 2. 缺失的 ValueKey

### 2.1 已下载页面分类卡片
- **文件**: `lib/ui/pages/library/downloaded_page.dart:162`
- **问题**: `GridView.builder` 中的 `_CategoryCard` 缺少 `ValueKey`，且构造函数未接受 `key` 参数
- **修复**:
  - 构造函数添加 `super.key`
  - 使用 `ValueKey(categories[index].folderPath)` 作为唯一标识
- **原因**: CLAUDE.md 明确要求列表/网格项加 `ValueKey(item.id)`，缺少 key 会导致列表更新时状态混乱

### 2.2 电台页面站点卡片
- **文件**: `lib/ui/pages/radio/radio_page.dart:168`
- **问题**: `GridView.builder` 中的 `ContextMenuRegion` 缺少 `ValueKey`
- **修复**: 添加 `ValueKey(station.id)`
- **原因**: 同上，确保列表项正确复用

## 审查中排除的误报

以下问题经验证后确认不是真正的 bug：

1. **`_isPlayingOutOfQueue` 使用 `track.id` 比较** — 在此上下文中，两个 Track 都来自数据库，Isar ID 是稳定的，使用 `id` 比较是正确的
2. **RadioController.play() 中的状态捕获顺序** — `_captureMusicRestoreState()` 读取的是 Riverpod state 快照，不会被后续的 `_pauseMusicPlayback()` 影响
3. **`_onAudioError` 使用 `.then()` 而非 `await`** — 该方法是 void 回调，不能使用 async/await，`.then()` 是正确的模式
4. **`ensureAudioUrl` 注释与返回类型** — 注释正确描述了 `(Track, String?)` 返回类型，`ensureAudioStream` 是另一个方法
5. **下载 `contentLength` 检查** — `contentLength > 0` 的逻辑正确处理了 -1（未知长度）的情况
