# Phase 3 稳定性增强 - 修复总结

**日期**: 2026-02-17
**范围**: FIX-WORKFLOW.md Phase 3 (6 个任务)
**结果**: 修复 3 个，跳过 3 个（经代码审查确认已修复或无需修改）

---

## 已修复

### 1. DownloadService Isolate 取消竞态 (Task 3.1)

**文件**: `lib/services/download/download_service.dart`

**问题**: `pauseTask()` 和 `_startDownload()` 的 `finally` 块都会递减 `_activeDownloads`，导致计数变为负数。

**根因分析**:
```
用户点击暂停 → pauseTask() 执行:
  1. _activeDownloadIsolates.remove(taskId)  ← 从 map 移除
  2. receivePort.close() + isolate.kill()
  3. _activeDownloads--                       ← 第一次递减

receivePort 关闭导致 await for 循环退出 → finally 执行:
  4. _activeDownloadIsolates.remove(task.id)  ← 返回 null（已被移除）
  5. _activeDownloads--                       ← 第二次递减 ❌
```

**修复**:
```dart
// finally 块
final wasStillActive = _activeDownloadIsolates.remove(task.id) != null;
_activeCancelTokens.remove(task.id);
if (wasStillActive) {
  _activeDownloads--;
}
```

同时移除了 `await for` 循环后的 `_activeDownloadIsolates.remove(task.id)`（行 670），统一由 `finally` 处理清理，避免正常完成路径下 `finally` 误判为"已被外部取消"。

---

### 2. 元数据保存错误处理 (Task 3.3a)

**文件**: `lib/services/download/download_service.dart` (`_saveMetadata` 方法)

**问题**: `metadataFile.writeAsString()` 无 try-catch，磁盘满或权限不足时会抛出 `FileSystemException`，中断整个下载完成流程（包括路径保存、状态更新）。

**修复**:
```dart
try {
  await metadataFile.writeAsString(jsonEncode(metadata));
} on FileSystemException catch (e) {
  logWarning('Failed to save metadata for ${track.title}: $e');
  // 元数据保存失败不应阻止下载完成
}
```

元数据是辅助信息（封面、统计数据等），其保存失败不应影响音频文件的下载记录。

---

### 3. 下载失败主动提示 (Task 3.5)

**文件**:
- `lib/services/download/download_service.dart` — 新增 `DownloadFailureEvent` 类和 `failureStream`
- `lib/providers/download/download_providers.dart` — 监听失败流并显示 Toast
- `lib/i18n/{zh-CN,zh-TW,en}/library.i18n.json` — 新增 `downloadFailed` 翻译键

**问题**: 下载失败时仅更新数据库状态为 `failed`，用户在非下载管理页面无法感知失败。

**修复**:

服务层新增失败事件流：
```dart
class DownloadFailureEvent {
  final int taskId;
  final int trackId;
  final String trackTitle;
  final String errorMessage;
}

// 在 DioException（非取消）和通用 catch 中发射事件
_failureController.add(DownloadFailureEvent(...));
```

Provider 层监听并显示 Toast：
```dart
service.failureStream.listen((event) {
  ref.read(toastServiceProvider).showError(
    t.library.downloadFailed(title: event.trackTitle),
  );
});
```

注意：用户主动暂停/取消不会触发失败提示（`DioExceptionType.cancel` 路径不发射事件）。

---

## 跳过的任务及理由

### Task 3.2: AudioController 快速切歌竞态 — 已修复

`_restoreSavedState()` 已有完整的 `_isSuperseded` 检查链：
- 行 781: `final requestId = ++_playRequestId` — 递增请求 ID
- 行 825: URL 获取后检查 `_isSuperseded(requestId)`
- 行 841-844: `setUrl` 后检查，若被取代则调用 `_audioService.stop()` 后返回

报告中描述的"setUrl 和 play 之间被取代时短暂播放错误歌曲"场景已被覆盖。

### Task 3.4: Timer 未取消 — 已修复

四个服务类的 `dispose()` 均已正确实现：

| 服务类 | Timer 取消 | StreamController 关闭 | 额外清理 |
|--------|-----------|---------------------|----------|
| `RankingCacheService` | `_refreshTimer?.cancel()` ✅ | `_stateController.close()` ✅ | `_networkRecoveredSubscription?.cancel()` |
| `RadioRefreshService` | `_refreshTimer?.cancel()` ✅ | `_stateController.close()` ✅ | — |
| `RadioController` | `_stopTimers()` ✅ | — | 3 个 StreamSubscription 取消 |
| `ConnectivityNotifier` | `_pollingTimer?.cancel()` ✅ | `_networkRecoveredController.close()` ✅ | `super.dispose()` |

### Task 3.6: YouTube 限流检测优化 — 无需修改

`_isRateLimitError()` 使用字符串匹配检测 `youtube_explode_dart` 库抛出的异常，已覆盖 `429`、`rate`、`quota`、`too many` 关键词。HTTP 429 状态码的 `DioException` 由独立的 `_handleDioError()` 方法处理（通过 `SourceApiException.classifyDioError`），两条路径互不干扰。添加 HTTP 状态码检测到字符串匹配方法中是冗余的。

---

## 验证

```
flutter analyze → No issues found!
```
