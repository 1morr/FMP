# 内存安全与资源管理审查报告

## 审查摘要

FMP 项目在内存安全和资源管理方面整体表现**良好**。核心音频系统的资源管理非常规范，所有 StreamSubscription 都在 dispose 中正确取消，Timer 都有对应的 cancel 逻辑，media_kit Player 有完整的释放流程。

**统计：**
- 🔴 严重问题：1 个
- 🟡 中等问题：5 个
- 🟢 良好实践：8 个

---

## 🔴 严重问题（可能导致内存泄漏或崩溃）

### 问题 1: RankingCacheService 单例的 dispose 不完整 — Provider onDispose 为空操作

- **文件**: `lib/services/cache/ranking_cache_service.dart`
- **行号**: 约第 160-170 行（`rankingCacheServiceProvider`）
- **问题描述**:
  `RankingCacheService` 是全局单例（`static late final instance`），其 Provider 的 `ref.onDispose` 回调中注释写着"不銷毀全局單例，只取消網絡監聽"，但实际上 **什么都没做**。这意味着：
  - `_refreshTimer`（每小时触发一次）永远不会被取消
  - `_networkRecoveredSubscription` 永远不会被取消
  - `_stateController` 永远不会被关闭

  虽然作为全局单例在应用生命周期内存在是合理的，但如果 Provider 被重建（例如依赖变化），旧的网络监听不会被清理，可能导致重复监听。

  ```dart
  // 当前代码
  ref.onDispose(() {
    // 不銷毀全局單例，只取消網絡監聯
  });
  ```

- **建议修复**:
  ```dart
  ref.onDispose(() {
    // 取消网络监听（单例本身不销毁）
    service._networkRecoveredSubscription?.cancel();
    service._networkRecoveredSubscription = null;
    service._networkMonitoringSetup = false;
  });
  ```

---

## 🟡 中等问题（潜在风险）

### 问题 1: FileExistsCache 无大小限制 — 可能无限增长

- **文件**: `lib/providers/download/file_exists_cache.dart`
- **行号**: 全文件
- **问题描述**:
  `FileExistsCache` 使用 `Set<String>` 存储已验证存在的文件路径，但没有任何大小限制或 LRU 淘汰机制。对于拥有大量下载歌曲的用户，这个 Set 会持续增长。每个路径字符串约 100-200 字节，1000 首歌曲约 200KB，10000 首约 2MB。

  虽然对于音乐播放器来说不太可能达到极端数量，但缺少上限保护不够健壮。

- **建议修复**:
  考虑添加最大缓存条目数限制（如 5000），超出时清除最早添加的条目。或者在页面切换时清理不再需要的路径。

### 问题 2: _MixPlaylistState.seenVideoIds 无限增长

- **文件**: `lib/services/audio/audio_provider.dart`
- **行号**: 约第 335 行（`_MixPlaylistState`）
- **问题描述**:
  Mix 播放模式下，`seenVideoIds` 集合会随着不断加载新歌曲而持续增长，没有上限。在极端情况下（用户长时间使用 Mix 模式），这个 Set 可能积累数千个 ID。

  每个 YouTube video ID 约 11 字符，1000 个约 11KB，实际影响较小，但设计上缺少保护。

- **建议修复**:
  当 `seenVideoIds` 超过一定阈值（如 500）时，移除最早添加的一半条目。或者在退出 Mix 模式时清空。

### 问题 3: import_preview_page 使用 ListView 而非 ListView.builder

- **文件**: `lib/ui/pages/library/import_preview_page.dart`
- **行号**: 约第 112 行
- **问题描述**:
  导入预览页面使用 `ListView(children: [...])` 配合 `shrinkWrap: true`，而非 `ListView.builder`。当导入的歌单包含大量歌曲（如 500+ 首）时，所有列表项会一次性构建，导致：
  - 初始渲染时间长
  - 内存占用高（所有 Widget 同时存在）

  ```dart
  Flexible(
    child: ListView(
      shrinkWrap: true,
      children: [
        // 所有歌曲一次性构建
        ...state.matchedTracks.asMap().entries.map((entry) { ... }),
      ],
    ),
  )
  ```

- **建议修复**:
  重构为 `CustomScrollView` + `SliverList.builder`，按需构建列表项。对于分组（未匹配/已匹配），可以使用多个 Sliver。

### 问题 4: RadioRefreshService 单例的 _stateController 不会被关闭

- **文件**: `lib/services/radio/radio_refresh_service.dart`
- **行号**: 约第 32 行、第 145-148 行
- **问题描述**:
  `RadioRefreshService` 是全局单例，其 `dispose()` 方法会关闭 `_stateController`，但 Provider 定义中直接返回 `RadioRefreshService.instance`，没有 `ref.onDispose` 调用 `dispose()`。

  ```dart
  final radioRefreshServiceProvider = Provider<RadioRefreshService>((ref) {
    return RadioRefreshService.instance;
    // 没有 ref.onDispose
  });
  ```

  这意味着 `_refreshTimer` 和 `_stateController` 在应用生命周期内永远不会被清理。作为单例这是可以接受的，但如果 `_stateController` 的监听者被销毁而控制器本身不关闭，可能导致微小的内存泄漏。

- **建议修复**:
  作为全局单例，这是可接受的设计。但建议在 Provider 中添加注释说明为什么不调用 dispose，避免后续维护者误解。

### 问题 5: AudioController.dispose() 中 _audioService.dispose() 是 async 但未 await

- **文件**: `lib/services/audio/audio_provider.dart`
- **行号**: 约第 586 行
- **问题描述**:
  `AudioController.dispose()` 是同步方法（`void dispose()`），但内部调用了 `_audioService.dispose()` 和 `_queueManager.dispose()`。其中 `MediaKitAudioService.dispose()` 是 `Future<void>`（异步方法），包含多个 `await` 操作（取消订阅、关闭控制器、释放 Player）。

  由于 `StateNotifier.dispose()` 是同步的，`_audioService.dispose()` 的 Future 不会被等待，可能导致：
  - StreamController 未完全关闭
  - media_kit Player 未完全释放

  ```dart
  @override
  void dispose() {
    _stopPositionCheckTimer();
    _cancelRetryTimer();
    _networkRecoverySubscription?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();  // StreamSubscription.cancel() 也是 async
    }
    _queueManager.dispose();
    _audioService.dispose();  // Future<void> 未被 await！
    super.dispose();
  }
  ```

- **建议修复**:
  这是 Flutter/Riverpod 的已知限制（StateNotifier.dispose 是同步的）。实际上 Dart 的事件循环会最终执行这些 Future，但在极端情况下（如热重载）可能导致资源未完全释放。可以考虑在 Provider 的 `ref.onDispose` 中使用异步清理：

  ```dart
  ref.onDispose(() async {
    await controller._audioService.dispose();
  });
  ```

---

## 🟢 良好实践（值得肯定的做法）

### 1. MediaKitAudioService 的资源管理非常完善
- **文件**: `lib/services/audio/media_kit_audio_service.dart`
- 所有 13 个 StreamSubscription 都存储在 `_subscriptions` 列表中
- `dispose()` 方法逐一取消所有订阅并清空列表
- 所有 11 个 StreamController/BehaviorSubject 都在 dispose 中关闭
- `_player.dispose()` 正确释放 media_kit Player
- 使用 `BehaviorSubject`（rxdart）确保新监听者能立即获得最新值

### 2. media_kit 内存优化配置出色
- **文件**: `lib/services/audio/media_kit_audio_service.dart`，约第 190-220 行
- `PlayerConfiguration(bufferSize: 4 * 1024 * 1024)` — 将 demuxer 缓存从默认 32MB 降到 4MB
- `vid=no` — 完全禁用视频轨道解码，节省 200-400MB 内存
- `sid=no` — 禁用字幕轨道
- `demuxer-max-bytes=1MB` — 限制前向缓冲（默认 150MB）
- `demuxer-max-back-bytes=256KB` — 限制后向缓冲（默认 50MB）
- `cache=no` — 禁用额外缓存层
- 这些优化将 media_kit 的内存占用从可能的 200+MB 降低到约 5MB

### 3. AudioController 的 Timer 管理规范
- **文件**: `lib/services/audio/audio_provider.dart`
- `_positionCheckTimer` 有 `_startPositionCheckTimer()` / `_stopPositionCheckTimer()` 配对方法
- `_retryTimer` 有 `_cancelRetryTimer()` 方法
- `_networkRecoverySubscription` 在 dispose 中取消
- 所有 Timer 在 dispose 中都被正确清理

### 4. QueueManager 的 Timer 和 StreamController 正确清理
- **文件**: `lib/services/audio/queue_manager.dart`
- `_savePositionTimer` 在 dispose 中取消
- `_stateController` 在 dispose 中关闭
- `_fetchingUrlTrackIds` 使用 try/finally 确保在异常时也能移除

### 5. DownloadService 的 Isolate 清理完善
- **文件**: `lib/services/download/download_service.dart`
- `dispose()` 中遍历所有 `_activeDownloadIsolates`，关闭 ReceivePort 并 kill Isolate
- 同时清理旧的 CancelToken
- 清空 `_pendingProgressUpdates` 内存缓存
- Provider 的 `ref.onDispose` 正确调用 `service.dispose()`

### 6. Download Provider 的事件监听清理完善
- **文件**: `lib/providers/download/download_providers.dart`
- `completionSubscription` 和 `progressSubscription` 都在 `ref.onDispose` 中取消
- `debounceTimer` 也在 `ref.onDispose` 中取消
- 使用 debouncing（300ms）避免批量下载完成时的频繁 UI 刷新

### 7. 列表页面正确使用 Builder 模式
- **文件**: 多个页面
- `explore_page.dart` — 使用 `ListView.builder`
- `play_history_page.dart` — 使用 `ListView.builder`
- `playlist_detail_page.dart` — 使用 `CustomScrollView` + `SliverChildBuilderDelegate`
- 这些页面都正确使用了懒加载列表，避免一次性构建所有列表项

### 8. LyricsCacheService 有完善的 LRU 缓存策略
- **文件**: `lib/services/lyrics/lyrics_cache_service.dart`
- 最大缓存文件数：50（可配置）
- 最大缓存大小：5MB
- 使用 LRU 淘汰策略
- 访问时间持久化到文件
- 支持用户调整缓存大小

---

## 改进建议优先级排序

1. **[高]** 修复 `RankingCacheService` Provider 的 `onDispose` — 添加网络监听清理逻辑，防止 Provider 重建时重复监听
2. **[中]** 修复 `AudioController.dispose()` 中异步资源释放问题 — 在 Provider 层面使用异步 dispose
3. **[中]** 重构 `import_preview_page.dart` 的列表为 `ListView.builder` — 大歌单导入时可能卡顿
4. **[低]** 为 `FileExistsCache` 添加大小限制 — 当前实际影响较小
5. **[低]** 为 `_MixPlaylistState.seenVideoIds` 添加上限保护 — 当前实际影响较小
6. **[低]** 为 `RadioRefreshService` Provider 添加注释说明单例不 dispose 的原因 — 代码可维护性
