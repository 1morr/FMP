# FMP 代码审查 - 快速修复指南

**生成日期**: 2026-02-17
**目的**: 提供最常见问题的即用修复代码

---

## 🚀 5 分钟快速修复（7 个问题）

### 1. SearchPage AppBar 缺少尾部间距

**文件**: `lib/ui/pages/search/search_page.dart`
**行号**: 113

```dart
// ❌ 修复前
appBar: AppBar(
  actions: [
    if (_searchController.text.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () { ... },
      ),
  ],
),

// ✅ 修复后
appBar: AppBar(
  actions: [
    if (_searchController.text.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () { ... },
      ),
    const SizedBox(width: 8),  // 添加尾部间距
  ],
),
```

---

### 2. 硬编码圆角值

**文件**: `lib/ui/pages/library/widgets/cover_picker_dialog.dart`
**行号**: 320

```dart
// ❌ 修复前
borderRadius: BorderRadius.circular(isSelected ? 5 : 8),

// ✅ 修复后
borderRadius: isSelected
    ? AppRadius.borderRadiusSm  // 4dp
    : AppRadius.borderRadiusLg, // 8dp
```

---

### 3. QueueManager.dispose() 不完整

**文件**: `lib/services/audio/queue_manager.dart`
**行号**: 231

```dart
// ❌ 修复前
void dispose() {
  _savePositionTimer?.cancel();
  _stateController.close();
}

// ✅ 修复后
void dispose() {
  _savePositionTimer?.cancel();
  _fetchingUrlTrackIds.clear();  // 清空 Set，释放引用
  _stateController.close();
}
```

---

### 4. AudioController.dispose() 需增强

**文件**: `lib/services/audio/audio_provider.dart`
**行号**: 577-590

```dart
// ❌ 修复前
@override
void dispose() {
  _stopPositionCheckTimer();
  _cancelRetryTimer();
  _networkRecoverySubscription?.cancel();
  for (final subscription in _subscriptions) {
    subscription.cancel();
  }
  _queueManager.dispose();
  _audioService.dispose();
  super.dispose();
}

// ✅ 修复后
@override
void dispose() {
  _stopPositionCheckTimer();
  _cancelRetryTimer();
  _networkRecoverySubscription?.cancel();

  // 取消所有订阅
  for (final subscription in _subscriptions) {
    subscription.cancel();
  }
  _subscriptions.clear();  // 清空列表

  // 清除 Mix 状态
  _mixState = null;

  _queueManager.dispose();
  _audioService.dispose();
  super.dispose();
}
```

---

### 5. 排行榜列表缺少 ValueKey

**文件**: `lib/ui/pages/explore/explore_page.dart` (行 206) 和 `lib/ui/pages/home/home_page.dart` (行 254)

```dart
// ❌ 修复前
ListView.builder(
  itemCount: tracks.length,
  itemBuilder: (context, index) {
    final track = tracks[index];
    return _ExploreTrackTile(
      track: track,
      rank: index + 1,
      isPlaying: isPlaying,
      onTap: () => ...,
    );
  },
)

// ✅ 修复后
ListView.builder(
  itemCount: tracks.length,
  itemBuilder: (context, index) {
    final track = tracks[index];
    return _ExploreTrackTile(
      key: ValueKey('${track.sourceId}_${track.pageNum}'),  // 添加 ValueKey
      track: track,
      rank: index + 1,
      isPlaying: isPlaying,
      onTap: () => ...,
    );
  },
)
```

**同样修复 HomePage**:
```dart
// lib/ui/pages/home/home_page.dart:254
return _RankingTrackTile(
  key: ValueKey('${track.sourceId}_${track.pageNum}'),  // 添加 ValueKey
  track: track,
  rank: index + 1,
  ...
);
```

---

### 6. Future.microtask 缺少错误处理

**文件**: `lib/services/audio/audio_provider.dart`
**行号**: 2340

```dart
// ❌ 修复前
Future.microtask(() async {
  try {
    // 播放完成逻辑
    ...
  } finally {
    _isHandlingCompletion = false;
  }
});

// ✅ 修复后
Future.microtask(() async {
  try {
    // 播放完成逻辑
    ...
  } catch (e, stack) {
    logError('Track completion handler failed', e, stack);
  } finally {
    _isHandlingCompletion = false;
  }
});
```

---

### 7. Isolate 错误传递结构化

**文件**: `lib/services/download/download_service.dart`
**函数**: `_isolateDownload`

```dart
// ❌ 修复前
try {
  // 下载逻辑
} catch (e) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error, e.toString()));
}

// ✅ 修复后
try {
  // 下载逻辑
} on DioException catch (e) {
  // 传递结构化错误信息
  final errorType = e.type == DioExceptionType.connectionTimeout
      ? 'timeout'
      : e.type == DioExceptionType.cancel
      ? 'cancelled'
      : 'network';
  sendPort.send(_IsolateMessage(
    _IsolateMessageType.error,
    '{"type":"$errorType","message":"${e.message}"}',
  ));
} on FileSystemException catch (e) {
  sendPort.send(_IsolateMessage(
    _IsolateMessageType.error,
    '{"type":"filesystem","message":"${e.message}"}',
  ));
} catch (e) {
  sendPort.send(_IsolateMessage(
    _IsolateMessageType.error,
    '{"type":"unknown","message":"$e"}',
  ));
}
```

---

## ⚡ 1 小时修复（3 个关键性能问题）

### 8. PlaylistDetailPage 分组重复计算

**文件**: `lib/ui/pages/library/playlist_detail_page.dart`
**行号**: 172

**问题**: 每次 build 都重新计算分组，500 首歌耗时 15-30ms

```dart
// ❌ 修复前
@override
Widget build(BuildContext context) {
  final tracks = ref.watch(playlistDetailProvider(widget.playlistId))
      .valueOrNull?.tracks ?? [];

  // 每次 build 都执行分组计算
  final groupedTracks = _groupTracksByPage(tracks);

  return ListView.builder(...);
}

// ✅ 修复后
class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  List<Track> _cachedTracks = [];
  Map<int, List<Track>> _cachedGroupedTracks = {};

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(playlistDetailProvider(widget.playlistId))
        .valueOrNull?.tracks ?? [];

    // 只在 tracks 长度变化时重新计算
    if (tracks.length != _cachedTracks.length) {
      _cachedTracks = tracks;
      _cachedGroupedTracks = _groupTracksByPage(tracks);
    }

    return ListView.builder(
      itemCount: _cachedGroupedTracks.length,
      itemBuilder: (context, index) {
        final pageNum = _cachedGroupedTracks.keys.elementAt(index);
        final pageTracks = _cachedGroupedTracks[pageNum]!;
        return _buildPageGroup(pageNum, pageTracks);
      },
    );
  }
}
```

**更好的方案**（使用 useMemoized）:
```dart
import 'package:flutter_hooks/flutter_hooks.dart';

class PlaylistDetailPage extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(playlistDetailProvider(widget.playlistId))
        .valueOrNull?.tracks ?? [];

    // 使用 useMemoized 缓存分组结果
    final groupedTracks = useMemoized(
      () => _groupTracksByPage(tracks),
      [tracks.length],  // 只在长度变化时重新计算
    );

    return ListView.builder(...);
  }
}
```

---

### 9. HomePage 过度 rebuild

**文件**: `lib/ui/pages/home/home_page.dart`
**行号**: 86-88

**问题**: 监听 3 个 provider，任何一个变化都导致整页重建

```dart
// ❌ 修复前
@override
Widget build(BuildContext context) {
  final recentHistory = ref.watch(recentHistoryProvider);
  final bilibiliRanking = ref.watch(bilibiliRankingCacheProvider);
  final youtubeRanking = ref.watch(youtubeRankingCacheProvider);

  return Scaffold(
    body: Column(
      children: [
        _buildQuickActions(),
        _buildRecentHistory(recentHistory),
        _buildBilibiliRanking(bilibiliRanking),
        _buildYoutubeRanking(youtubeRanking),
      ],
    ),
  );
}

// ✅ 修复后 - 方案 1: 使用 select 精确监听
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Column(
      children: [
        _buildQuickActions(),
        _RecentHistorySection(),  // 独立 Widget
        _BilibiliRankingSection(), // 独立 Widget
        _YoutubeRankingSection(),  // 独立 Widget
      ],
    ),
  );
}

// 独立的 Widget，只监听自己需要的数据
class _RecentHistorySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentHistory = ref.watch(recentHistoryProvider);
    return _buildRecentHistory(recentHistory);
  }
}

class _BilibiliRankingSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(bilibiliRankingCacheProvider);
    return _buildBilibiliRanking(ranking);
  }
}

class _YoutubeRankingSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(youtubeRankingCacheProvider);
    return _buildYoutubeRanking(ranking);
  }
}
```

---

### 10. 文件操作错误处理不健壮

**文件**: `lib/services/download/download_service.dart`

**问题 1**: 元数据保存无错误处理（行 844）

```dart
// ❌ 修复前
await metadataFile.writeAsString(jsonEncode(metadata));

// ✅ 修复后
try {
  await metadataFile.writeAsString(jsonEncode(metadata));
} on FileSystemException catch (e) {
  logWarning('Failed to save metadata for ${task.id}: $e');
  // 元数据保存失败不应阻止下载完成
}
```

**问题 2**: 文件存在性检查和添加路径之间有 TOCTOU 竞态（行 709）

```dart
// ❌ 修复前
if (await File(savePath).exists()) {
  await _trackRepository.addDownloadPath(...);
} else {
  logError('Download completed but file not found');
  throw Exception('Downloaded file not found');
}

// ✅ 修复后
try {
  // 先检查文件是否存在
  final file = File(savePath);
  if (!await file.exists()) {
    logError('Download completed but file not found: $savePath');
    throw Exception('Downloaded file not found');
  }

  // 添加路径，如果文件在此期间被删除，会抛出异常
  await _trackRepository.addDownloadPath(
    trackId: task.trackId,
    playlistId: task.playlistId,
    path: savePath,
  );
} on FileSystemException catch (e) {
  logError('Failed to verify or save download path: $e');
  throw Exception('File operation failed: ${e.message}');
} catch (e) {
  logError('Unexpected error saving download path: $e');
  rethrow;
}
```

---

## 🔧 2 小时修复（服务类 dispose 方法）

### 11. Timer 未取消（5 个服务类）

#### RankingCacheService

**文件**: `lib/services/cache/ranking_cache_service.dart`

```dart
// ✅ 添加 dispose 方法
class RankingCacheService {
  Timer? _refreshTimer;
  final _stateController = StreamController<int>.broadcast();

  // 现有代码...

  // 新增 dispose 方法
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _stateController.close();
  }
}
```

#### RadioRefreshService

**文件**: `lib/services/radio/radio_refresh_service.dart`

```dart
// ✅ 添加 dispose 方法
class RadioRefreshService {
  Timer? _refreshTimer;

  // 现有代码...

  // 新增 dispose 方法
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
```

#### RadioController

**文件**: `lib/services/radio/radio_controller.dart`

```dart
// ✅ 添加 dispose 方法
class RadioController extends StateNotifier<RadioState> {
  Timer? _playDurationTimer;
  Timer? _infoRefreshTimer;

  // 现有代码...

  // 新增 dispose 方法
  @override
  void dispose() {
    _playDurationTimer?.cancel();
    _playDurationTimer = null;
    _infoRefreshTimer?.cancel();
    _infoRefreshTimer = null;
    super.dispose();
  }
}
```

#### ConnectivityService

**文件**: `lib/services/connectivity_service.dart`

```dart
// ✅ 添加 dispose 方法
class ConnectivityService {
  Timer? _pollingTimer;
  final _stateController = StreamController<bool>.broadcast();

  // 现有代码...

  // 新增 dispose 方法
  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _stateController.close();
  }
}
```

---

## 🎯 30 分钟修复（竞态条件）

### 12. DownloadService Isolate 取消竞态

**文件**: `lib/services/download/download_service.dart`
**行号**: 407-420

```dart
// ❌ 修复前
void pauseTask(int taskId) {
  final isolateInfo = _activeDownloadIsolates.remove(taskId);
  if (isolateInfo != null) {
    isolateInfo.receivePort.close();
    isolateInfo.isolate.kill();
  }
}

// _startDownload() 的 finally 块
finally {
  _activeDownloadIsolates.remove(task.id);  // 可能重复移除
  _activeCancelTokens.remove(task.id);
  _activeDownloads--;  // 计数可能不准确
}

// ✅ 修复后
void pauseTask(int taskId) {
  final isolateInfo = _activeDownloadIsolates.remove(taskId);
  if (isolateInfo != null) {
    isolateInfo.receivePort.close();
    isolateInfo.isolate.kill();
    _activeDownloads--;  // 在这里递减
  }
}

// _startDownload() 的 finally 块
finally {
  // 只在未被外部取消时清理
  if (_activeDownloadIsolates.containsKey(task.id)) {
    _activeDownloadIsolates.remove(task.id);
    _activeDownloads--;
  }
  _activeCancelTokens.remove(task.id);
  _triggerSchedule();
}
```

---

### 13. AudioController 快速切歌竞态

**文件**: `lib/services/audio/audio_provider.dart`
**函数**: `_restoreSavedState()`

```dart
// ❌ 修复前
Future<void> _restoreSavedState() async {
  final requestId = ++_playRequestId;

  // ... 获取 URL ...

  await _audioService.setUrl(url);
  await _audioService.play();  // 可能在这之前被取代
}

// ✅ 修复后
Future<void> _restoreSavedState() async {
  final requestId = ++_playRequestId;

  // ... 获取 URL ...

  await _audioService.setUrl(url);

  // 在 play 之前再次检查
  if (_isSuperseded(requestId)) {
    await _audioService.stop();  // 立即停止
    return;
  }

  await _audioService.play();
}
```

---

## 📚 测试建议

### 快速验证修复效果

**性能测试**:
```bash
# 使用 Flutter DevTools Performance 视图
flutter run --profile
# 然后在 DevTools 中：
# 1. 打开 Performance 视图
# 2. 滚动歌单详情页（500+ 首歌）
# 3. 观察帧率是否稳定在 55-60 FPS
```

**内存测试**:
```bash
# 使用 Flutter DevTools Memory 视图
flutter run --profile
# 然后在 DevTools 中：
# 1. 打开 Memory 视图
# 2. 反复进入/退出页面 10 次
# 3. 观察内存是否持续增长
```

**竞态条件测试**:
```dart
// 快速连续点击 5 首不同的歌曲
// 验证只播放最后一首
for (int i = 0; i < 5; i++) {
  await tester.tap(find.byKey(Key('track_$i')));
  await tester.pump(Duration(milliseconds: 100));
}
// 等待加载完成
await tester.pumpAndSettle();
// 验证播放的是第 5 首歌
expect(currentTrack.id, tracks[4].id);
```

---

## 🎉 完成检查清单

修复完成后，请检查：

- [ ] 代码编译通过（`flutter analyze`）
- [ ] 相关测试通过
- [ ] 使用 DevTools 验证性能改善
- [ ] 使用 DevTools 验证内存不泄漏
- [ ] 更新 CLAUDE.md（如有架构变更）
- [ ] 更新 Serena 记忆（如有设计决策）
- [ ] 提交 commit（使用清晰的 commit message）

---

**最后更新**: 2026-02-17
**维护者**: 开发团队
