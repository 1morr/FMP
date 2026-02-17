# Phase 1 修复总结

**执行日期**: 2026-02-17
**修复数量**: 6/7（Task 1.1 已修复，跳过）
**验证**: `flutter analyze` — No issues found

---

## 跳过的任务

### Task 1.1: SearchPage AppBar 尾部间距
**状态**: ✅ 已修复（无需操作）

代码中 `search_page.dart:112` 已存在 `const SizedBox(width: 8)`，无需重复添加。

---

## 已完成的修复

### Task 1.2: 硬编码圆角值替换
**文件**: `lib/ui/pages/library/widgets/cover_picker_dialog.dart`

```dart
// 修复前
borderRadius: BorderRadius.circular(isSelected ? 5 : 8),

// 修复后
borderRadius: BorderRadius.circular(isSelected ? AppRadius.sm : AppRadius.md),
```

**说明**: 将魔法数字替换为 `ui_constants.dart` 中定义的统一常量（`sm=4dp`, `md=8dp`），保持与项目 UI 常量体系一致。值从 `5→4` 的微调在视觉上几乎无差异，但统一了设计语言。

---

### Task 1.3: QueueManager.dispose() 补全
**文件**: `lib/services/audio/queue_manager.dart`

```dart
void dispose() {
  _savePositionTimer?.cancel();
  _fetchingUrlTrackIds.clear();  // ← 新增
  _stateController.close();
}
```

**说明**: `_fetchingUrlTrackIds` 是一个 `Set<int>`，在 dispose 时未清空。虽然 Set 本身内存占用不大，但清空它是良好的资源释放习惯，避免 dispose 后仍持有对 track ID 的引用。

---

### Task 1.4: AudioController.dispose() 增强
**文件**: `lib/services/audio/audio_provider.dart`

```dart
void dispose() {
  _stopPositionCheckTimer();
  _cancelRetryTimer();
  _networkRecoverySubscription?.cancel();
  for (final subscription in _subscriptions) {
    subscription.cancel();
  }
  _subscriptions.clear();  // ← 新增：释放列表引用
  _mixState = null;         // ← 新增：释放 Mix 播放状态
  _queueManager.dispose();
  _audioService.dispose();
  super.dispose();
}
```

**说明**:
- `_subscriptions.clear()` — cancel 只是停止监听，clear 释放列表中对 StreamSubscription 对象的引用
- `_mixState = null` — `_MixPlaylistState` 包含 `seenVideoIds` Set 和播放列表元数据，置 null 帮助 GC 及时回收

---

### Task 1.5: 排行榜列表添加 ValueKey
**文件**: `lib/ui/pages/explore/explore_page.dart`, `lib/ui/pages/home/home_page.dart`

```dart
// explore_page.dart
return _ExploreTrackTile(
  key: ValueKey('${track.sourceId}_${track.pageNum}'),  // ← 新增
  track: track,
  rank: index + 1,
  ...
);

// home_page.dart
_RankingTrackTile(
  key: ValueKey('${displayTracks[i].sourceId}_${displayTracks[i].pageNum}'),  // ← 新增
  track: displayTracks[i],
  rank: i + 1,
),
```

同时为两个 Widget 的构造函数添加了 `super.key` 参数。

**说明**: 没有 key 时，Flutter 在列表数据变化后只能按索引位置做 diff，可能导致不必要的全量重建。`sourceId + pageNum` 组合唯一标识一首歌，让 framework 精确识别哪些项发生了变化。

---

### Task 1.6: Future.microtask 添加错误处理
**文件**: `lib/services/audio/audio_provider.dart` (`_onTrackCompleted`)

```dart
Future.microtask(() async {
  try {
    // 播放完成逻辑 ...
  } catch (e, stack) {
    logError('Track completion handler failed', e, stack);  // ← 新增
  } finally {
    _isHandlingCompletion = false;
  }
});
```

**说明**: 原代码只有 `try/finally` 没有 `catch`。`Future.microtask` 中的未捕获异常会变成 unhandled async error，在 release 模式下可能导致静默失败且无日志。添加 catch 确保异常被记录，便于排查播放完成后的跳转问题。

---

### Task 1.7: Isolate 错误传递结构化
**文件**: `lib/services/download/download_service.dart` (`_isolateDownload`)

```dart
// 修复前
} catch (e) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error, e.toString()));
}

// 修复后
} on SocketException catch (e) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error,
    '{"type":"network","message":"${e.message}"}'));
} on HttpException catch (e) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error,
    '{"type":"http","message":"${e.message}"}'));
} on FileSystemException catch (e) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error,
    '{"type":"filesystem","message":"${e.message}"}'));
} catch (e) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error,
    '{"type":"unknown","message":"$e"}'));
}
```

**与 FIX-WORKFLOW 的偏差**: 原方案建议捕获 `DioException`，但 Isolate 内使用的是 `dart:io` 的 `HttpClient`（不是 Dio），因此改为捕获 `SocketException`、`HttpException`、`FileSystemException`——这些才是 `HttpClient` 实际会抛出的异常类型。

**说明**: 结构化 JSON 错误让主线程可以区分网络错误、HTTP 协议错误、文件系统错误，为后续 Phase 3 的下载失败提示（Task 3.5）提供基础。当前主线程消费端将错误作为字符串嵌入 Exception，JSON 格式向后兼容。
