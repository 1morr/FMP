# 错误处理与崩溃防护审查报告

## 审查摘要

**总体评估**: 项目的错误处理整体水平较高，核心播放链路（AudioController → Sources → MediaKitAudioService）有完善的 try-catch 覆盖和重试机制。但存在一个严重的全局错误处理缺失问题，以及若干中等级别的改进空间。

| 类别 | 数量 |
|------|------|
| 🔴 严重问题 | 2 |
| 🟡 中等问题 | 5 |
| 🟢 良好实践 | 8 |

---

## 🔴 严重问题（可能导致崩溃）

### 问题 1: main.dart 缺少全局错误处理

- **文件**: `lib/main.dart`
- **行号**: 整个 `main()` 函数
- **问题描述**: `main.dart` 没有配置 `FlutterError.onError` 和 `runZonedGuarded`。这意味着：
  1. Flutter 框架层的渲染错误（如 Widget build 中的异常）会使用默认的红屏处理，在 release 模式下可能导致灰屏
  2. 未捕获的 Dart 异步异常（如 `Future` 中未 catch 的错误）会直接丢失，无法记录
  3. 没有全局错误日志收集机制，生产环境难以排查问题
- **风险等级**: 高
- **建议修复**:
```dart
void main(List<String> args) async {
  // 捕获 Flutter 框架错误
  FlutterError.onError = (FlutterErrorDetails details) {
    // 记录日志，release 模式下不显示红屏
    debugPrint('FlutterError: ${details.exception}');
    // 可选：上报到错误收集服务
  };

  // 捕获 Dart 未处理的异步错误
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // ... 现有初始化代码 ...
    runApp(ProviderScope(child: TranslationProvider(child: const FMPApp())));
  }, (error, stackTrace) {
    debugPrint('Uncaught error: $error\n$stackTrace');
  });
}
```

### 问题 2: AudioController.play() / pause() 缺少 try-catch

- **文件**: `lib/services/audio/audio_provider.dart`
- **行号**: 约第 593-601 行
- **问题描述**: `play()` 和 `pause()` 方法直接调用 `_audioService.play()` / `_audioService.pause()`，没有 try-catch 包裹。虽然 `_resumeWithFreshUrlIfNeeded()` 内部有部分错误处理，但如果 `_audioService.play()` 本身抛出异常（如 media_kit 底层错误），异常会直接传播到 UI 层。UI 层（如 `player_page.dart` 第 454 行）调用 `controller.togglePlayPause()` 时也没有 try-catch。
- **风险等级**: 高
- **建议修复**:
```dart
Future<void> play() async {
  try {
    if (await _resumeWithFreshUrlIfNeeded()) return;
    await _audioService.play();
  } catch (e, stack) {
    logError('Failed to play', e, stack);
    state = state.copyWith(error: e.toString());
  }
}

Future<void> pause() async {
  try {
    await _audioService.pause();
  } catch (e, stack) {
    logError('Failed to pause', e, stack);
  }
}
```

---

## 🟡 中等问题（错误处理不完善）

### 问题 3: BilibiliSource.getTrackInfo() 只捕获 DioException

- **文件**: `lib/data/sources/bilibili_source.dart`
- **行号**: 约第 141-169 行
- **问题描述**: `getTrackInfo()` 的 catch 块只捕获 `DioException`，但内部调用的 `_checkResponse()` 会抛出 `BilibiliApiException`，`data['owner']?['mid'] as int?` 等类型转换也可能抛出 `TypeError`。虽然 `BilibiliApiException` 会被上层 `_executePlayRequest` 捕获，但 `TypeError` 等其他异常会以原始形式传播。
- **风险等级**: 中
- **建议修复**: 添加通用 catch 块：
```dart
} on DioException catch (e) {
  throw _handleDioError(e);
} catch (e) {
  if (e is BilibiliApiException) rethrow;
  logError('Unexpected error in getTrackInfo: $e');
  throw BilibiliApiException(numericCode: -999, message: e.toString());
}
```
- **同样模式的方法**: `getVideoDetail()`（第 570 行）、`getRankingVideos()`（第 677 行）、`getVideoPages()`（第 524 行）、`parsePlaylist()`（第 416 行）、`searchLiveRooms()`（第 817 行）

### 问题 4: refreshAudioUrl() 完全没有 try-catch

- **文件**: `lib/data/sources/bilibili_source.dart` 第 341-357 行，`lib/data/sources/youtube_source.dart` 第 591-601 行
- **问题描述**: 两个 Source 的 `refreshAudioUrl()` 方法都没有 try-catch。虽然调用方（`QueueManager.ensureAudioUrl`）有错误处理，但 `refreshAudioUrl` 作为公开 API，缺少自身的错误处理不够健壮。特别是 `track.cid!` 的 force unwrap（bilibili_source.dart 第 349 行）在 `cid` 为 null 时会崩溃（虽然有 `if (track.cid != null)` 守卫，但 `cid!` 仍然是代码异味）。
- **风险等级**: 中
- **建议**: 这些方法的错误由调用方处理，当前设计可接受，但建议至少添加日志记录。

### 问题 5: _loadMoreMixTracks() 中的 YouTubeSource 实例未释放

- **文件**: `lib/services/audio/audio_provider.dart`
- **行号**: 约第 1510 行
- **问题描述**: `_loadMoreMixTracks()` 中创建了 `final youtubeSource = YouTubeSource()` 局部实例，但在 try-catch-finally 中没有调用 `youtubeSource.dispose()`。如果 `YouTubeSource` 构造函数创建了 Dio 实例或其他资源，这些资源不会被释放。
- **风险等级**: 中（资源泄漏）
- **建议修复**: 在 finally 块中添加 `youtubeSource.dispose()`，或使用已有的全局 YouTubeSource 实例。

### 问题 6: Isolate 下载中的错误信息丢失

- **文件**: `lib/services/download/download_service.dart`
- **行号**: 约第 640-660 行
- **问题描述**: Isolate 下载完成后，如果 `downloadError != null`，只抛出 `Exception('Download failed: $downloadError')`，丢失了原始异常的堆栈信息。此外，Isolate 内部的错误通过 `SendPort` 传递时只传递了字符串消息，无法区分网络错误、磁盘空间不足等不同类型的错误。
- **风险等级**: 低
- **建议**: 在 Isolate 消息中传递错误类型信息，以便主线程做出更精确的错误处理。

### 问题 7: 部分 Provider 的 error 回调丢弃了 StackTrace

- **文件**: `lib/ui/pages/explore/explore_page.dart` 第 131 行等多处
- **问题描述**: 多个 `.when()` 调用中的 `error` 回调使用 `(_, __)` 丢弃了 error 和 stackTrace 参数，没有记录日志。虽然 Provider 内部可能已经记录了错误，但 UI 层完全忽略错误详情，不利于调试。
- **风险等级**: 低
- **建议**: 至少在 debug 模式下记录错误：
```dart
error: (error, stack) {
  debugPrint('Ranking load error: $error');
  return _buildRankingContent(tracks: [], isLoading: false, error: t.general.loadFailed, ...);
},
```

---

## 🟢 良好实践（值得肯定的做法）

### 1. 完善的 AppException 体系
`lib/core/errors/app_exception.dart` 定义了清晰的异常层次结构（NetworkException、ServerException、NotFoundException 等），`ErrorHandler.wrap()` 方法能将各种原始异常统一转换为 AppException，`_handleDioError()` 覆盖了所有 DioExceptionType。

### 2. 播放请求竞态条件防护
`AudioController` 使用 `_playRequestId` + `_isSuperseded()` 机制防止快速切歌导致的竞态条件，`_navRequestId` 防止快速点击上/下一首的竞态，`_LockWithId` 确保播放操作的互斥性。这是非常成熟的并发控制设计。

### 3. 网络错误渐进式重试
`_scheduleRetry()` 实现了指数退避重试（1s → 2s → 4s → 8s → 16s），配合 `_onNetworkRecovered()` 网络恢复自动重试，以及 `retryManually()` 手动重试入口。PlayerState 中有 `isNetworkError`、`isRetrying`、`nextRetryAt` 等状态字段，UI 可以精确显示重试状态。

### 4. YouTube 播放 Fallback 机制
`_executePlayRequest()` 中，YouTube 播放失败后会尝试 `getAlternativeAudioStream()` 获取备选流（排除已失败的 URL），实现了多层降级：audioOnly → muxed → HLS。

### 5. 统一的 ErrorDisplay 组件
`lib/ui/widgets/error_display.dart` 提供了统一的错误显示组件，支持多种错误类型（network、server、notFound、permission、empty、general），有 compact 和 full 两种模式，支持重试回调。

### 6. 数据库初始化错误处理
`app.dart` 中 `databaseProvider.when()` 正确处理了 loading、error、data 三种状态，数据库初始化失败时显示错误页面而不是崩溃。

### 7. 下载系统的断点续传和错误恢复
`DownloadService._startDownload()` 有完善的错误处理：DioException.cancel 保存续传进度、其他错误标记为 failed 并保存进度、finally 块清理资源并触发下一个任务调度。

### 8. 歌词服务的优雅降级
歌词自动匹配（`_tryAutoMatchLyrics`）使用 `unawaited()` 后台执行，失败只记录警告不影响播放。多源歌词搜索（lrclib → netease → qqmusic）每个源独立 try-catch，单个源失败不影响其他源。

---

## 改进建议优先级排序

1. **[高优先级]** 在 `main.dart` 添加 `FlutterError.onError` 和 `runZonedGuarded` 全局错误处理
2. **[高优先级]** 为 `AudioController.play()` / `pause()` 添加 try-catch
3. **[中优先级]** 统一 BilibiliSource 中只捕获 DioException 的方法，添加通用 catch 块
4. **[中优先级]** 修复 `_loadMoreMixTracks()` 中 YouTubeSource 实例的资源泄漏
5. **[低优先级]** 改进 Isolate 下载的错误类型传递
6. **[低优先级]** UI 层 `.when()` error 回调中添加 debug 日志
7. **[建议]** 考虑添加全局错误日志收集（如 Sentry 或本地日志文件），便于排查生产环境问题
