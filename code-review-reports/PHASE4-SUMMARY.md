# Phase 4 修复总结

**执行日期**: 2026-02-17

## 审查结论

Phase 4 共 5 个任务，经代码审查后，4 个无需修改，1 个已完成修复。

## 各任务处理

### Task 4.1: 歌曲列表项样式统一 — 跳过

共享 `TrackTile` 组件已存在于 `lib/ui/widgets/track_tile.dart`，支持标准和排行榜两种模式。HomePage 和 ExplorePage 已通过包装器使用它。

PlaylistDetailPage、SearchPage、DownloadedCategoryPage 使用私有实现的原因是它们需要 `TrackTile` 不支持的功能：
- 多P分组显示（P1、P2 徽章）
- 缩进子项
- 选择模式（复选框）
- 页面特定的上下文菜单

视觉风格（标题颜色、播放状态字重、缩略图尺寸）已经统一，差异是功能性的。强行合并需要大幅扩展 `TrackTile` 接口，收益有限。

### Task 4.2: Mix 模式队列操作限制 — 已实现，无需修改

`addToQueue()`、`addAllToQueue()`、`addNext()` 三个方法均已包含 `if (_context.isMix)` 检查，Mix 模式下返回 false 并显示 toast。

### Task 4.3: 队列操作返回值语义明确化 — 跳过

返回类型为 `bool`，但所有用户反馈（Mix 模式阻止、队列已满等）已在方法内部通过 toast 处理。调用方只需知道成功/失败，不需要区分原因。改为枚举是纯粹的代码美观优化，无实际功能收益。

### Task 4.4: 下载错误处理重构 — ✅ 已修复

**文件**: `lib/services/download/download_service.dart`

**问题**: `_startDownload()` 的 `on DioException` catch 块是死代码。下载已迁移到 Isolate + `HttpClient`，不再使用 Dio 进行音频下载。Isolate 中的错误通过 `_IsolateMessage.error` 传回主线程，最终作为 `Exception` 被通用 `catch (e, stack)` 捕获。`DioException` 永远不会在此路径中抛出。

此外，两个 catch 块中的失败处理逻辑（保存续传进度 → 更新状态 → 发送失败事件）完全重复。

**修改内容**:
1. 移除死代码 `on DioException` catch 块（第 737-757 行）
2. 提取 `_handleDownloadFailure()` 私有方法，统一失败处理逻辑
3. 通用 `catch` 块调用该方法，消除重复

**修改前**:
```dart
} on DioException catch (e) {          // ← 死代码：Isolate 用 HttpClient，不抛 DioException
  if (e.type == DioExceptionType.cancel) {
    await _saveResumeProgress(task);
  } else {
    await _saveResumeProgress(task);   // ← 重复
    await _downloadRepository.updateTaskStatus(...);
    _failureController.add(...);
  }
} catch (e, stack) {
  await _saveResumeProgress(task);     // ← 重复
  await _downloadRepository.updateTaskStatus(...);
  _failureController.add(...);
}
```

**修改后**:
```dart
} catch (e, stack) {
  logError('Download failed for task: ${task.id}: $e', e, stack);
  await _handleDownloadFailure(task, trackTitle, e.toString());
}
```

```dart
/// 处理下载失败：保存续传进度、更新状态、发送失败事件
Future<void> _handleDownloadFailure(
  DownloadTask task, String trackTitle, String errorMessage,
) async {
  await _saveResumeProgress(task);
  await _downloadRepository.updateTaskStatus(
    task.id, DownloadStatus.failed, errorMessage: errorMessage);
  _failureController.add(DownloadFailureEvent(
    taskId: task.id, trackId: task.trackId,
    trackTitle: trackTitle, errorMessage: errorMessage));
}
```

**注意**: `dio.dart` 导入保留，因为 `_dio` 仍用于 `_saveMetadata()` 中的封面/头像下载。

### Task 4.5: StreamController 未关闭修复 — 无需修改

审查了全部 14 个 `StreamController` 实例，所有实例级控制器均在 `dispose()` 中正确调用 `.close()`。唯一未关闭的是 `Logger._logStreamController`（静态单例，应用生命周期内存活，关闭反而会导致后续日志写入失败）。

## 验证

```
flutter analyze lib/services/download/download_service.dart → No issues found!
```
