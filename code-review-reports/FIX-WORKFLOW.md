# FMP 代码审查 - 完整修复工作流

**生成日期**: 2026-02-17
**基于**: FINAL-COMPREHENSIVE-REPORT.md (38 个问题)
**预计总工作量**: ~30 小时
**工作流策略**: 5 阶段渐进式修复，按依赖关系排序

---

## 工作流总览

```
Phase 1 (快速修复)          Phase 2 (性能优化)         Phase 3 (稳定性)
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│ 7 个问题 ~1.5h  │─────▶│ 5 个问题 ~7h    │─────▶│ 6 个问题 ~6h    │
│ UI/内存/错误处理 │      │ 缓存/rebuild/IO │      │ 竞态/Timer/文件  │
└─────────────────┘      └─────────────────┘      └─────────────────┘
                                                          │
                              ┌────────────────────────────┘
                              ▼
                   Phase 4 (代码质量)          Phase 5 (可选优化)
                   ┌─────────────────┐      ┌─────────────────┐
                   │ 5 个问题 ~10h   │─────▶│ 5 个问题 ~8h    │
                   │ 统一组件/逻辑   │      │ 缓存/批量/设置  │
                   └─────────────────┘      └─────────────────┘
```

---

## Phase 1: 快速修复（立即执行）

**目标**: 修复所有 5 分钟级别的问题，建立修复节奏
**预计耗时**: 1.5 小时
**前置条件**: 无
**验证方式**: `flutter analyze` 通过

### Task 1.1: SearchPage AppBar 尾部间距
- **问题编号**: #1 (UI1)
- **优先级**: 🔴 高
- **文件**: `lib/ui/pages/search/search_page.dart:113`
- **耗时**: 5 分钟
- **依赖**: 无

**操作步骤**:
1. 打开 `search_page.dart`，定位到 AppBar 的 `actions` 列表
2. 在 actions 列表末尾添加 `const SizedBox(width: 8)`

```dart
// 修复后
appBar: AppBar(
  actions: [
    if (_searchController.text.isNotEmpty)
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () { ... },
      ),
    const SizedBox(width: 8),  // ← 添加
  ],
),
```

**验证**: 视觉检查 SearchPage 右侧间距与其他页面一致

---

### Task 1.2: 硬编码圆角值替换
- **问题编号**: #2 (UI2)
- **优先级**: 🔴 高
- **文件**: `lib/ui/pages/library/widgets/cover_picker_dialog.dart:320`
- **耗时**: 5 分钟
- **依赖**: 无

**操作步骤**:
1. 定位 `BorderRadius.circular(isSelected ? 5 : 8)`
2. 替换为 `AppRadius` 常量

```dart
// 修复后
borderRadius: isSelected
    ? AppRadius.borderRadiusSm   // 4dp
    : AppRadius.borderRadiusLg,  // 8dp
```

**验证**: 确认 `AppRadius` 已导入，圆角视觉效果正确

---

### Task 1.3: QueueManager.dispose() 补全
- **问题编号**: #4 (M1)
- **优先级**: 🔴 高
- **文件**: `lib/services/audio/queue_manager.dart:231`
- **耗时**: 5 分钟
- **依赖**: 无

**操作步骤**:
1. 在 `dispose()` 方法中 `_savePositionTimer?.cancel()` 之后添加 `_fetchingUrlTrackIds.clear()`

```dart
void dispose() {
  _savePositionTimer?.cancel();
  _fetchingUrlTrackIds.clear();  // ← 添加：清空 Set，释放引用
  _stateController.close();
}
```

**验证**: 编译通过，无运行时错误

---

### Task 1.4: AudioController.dispose() 增强
- **问题编号**: #5 (M2)
- **优先级**: 🔴 高
- **文件**: `lib/services/audio/audio_provider.dart:577-590`
- **耗时**: 15 分钟
- **依赖**: Task 1.3（QueueManager dispose 先修复）

**操作步骤**:
1. 在 subscriptions 循环后添加 `_subscriptions.clear()`
2. 在 `_queueManager.dispose()` 前添加 `_mixState = null`

```dart
@override
void dispose() {
  _stopPositionCheckTimer();
  _cancelRetryTimer();
  _networkRecoverySubscription?.cancel();

  for (final subscription in _subscriptions) {
    subscription.cancel();
  }
  _subscriptions.clear();  // ← 添加

  _mixState = null;  // ← 添加

  _queueManager.dispose();
  _audioService.dispose();
  super.dispose();
}
```

**验证**: 使用 DevTools Memory 视图，反复进入/退出播放页面，确认无内存泄漏

---

### Task 1.5: 排行榜列表添加 ValueKey
- **问题编号**: #3 (P0-3)
- **优先级**: 🔴 高
- **文件**: `lib/ui/pages/explore/explore_page.dart:206`, `lib/ui/pages/home/home_page.dart:254`
- **耗时**: 15 分钟
- **依赖**: 无

**操作步骤**:
1. **ExplorePage**: 在 `_ExploreTrackTile` 构造中添加 `key: ValueKey(...)`
2. **HomePage**: 在 `_RankingTrackTile` 构造中添加 `key: ValueKey(...)`

```dart
// explore_page.dart
return _ExploreTrackTile(
  key: ValueKey('${track.sourceId}_${track.pageNum}'),  // ← 添加
  track: track,
  rank: index + 1,
  ...
);

// home_page.dart
return _RankingTrackTile(
  key: ValueKey('${track.sourceId}_${track.pageNum}'),  // ← 添加
  track: track,
  rank: index + 1,
  ...
);
```

**验证**: 使用 DevTools Performance 视图，刷新排行榜数据，确认不再全量重建

---

### Task 1.6: Future.microtask 添加错误处理
- **问题编号**: #6 (E3)
- **优先级**: 🔴 高
- **文件**: `lib/services/audio/audio_provider.dart:2340`
- **耗时**: 15 分钟
- **依赖**: 无

**操作步骤**:
1. 在 `_onTrackCompleted` 的 `Future.microtask` 中添加 `catch` 块

```dart
Future.microtask(() async {
  try {
    // 播放完成逻辑 ...
  } catch (e, stack) {
    logError('Track completion handler failed', e, stack);  // ← 添加
  } finally {
    _isHandlingCompletion = false;
  }
});
```

**验证**: 编译通过，模拟播放完成场景无异常

---

### Task 1.7: Isolate 错误传递结构化
- **问题编号**: #7 (E2)
- **优先级**: 🔴 高
- **文件**: `lib/services/download/download_service.dart` (`_isolateDownload`)
- **耗时**: 30 分钟
- **依赖**: 无

**操作步骤**:
1. 将 `catch (e)` 替换为分类型捕获
2. 传递 JSON 结构化错误信息

```dart
} on DioException catch (e) {
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

**验证**: 模拟网络断开下载，确认主线程收到结构化错误

---

### Phase 1 完成检查

```bash
flutter analyze  # 确认无新增 warning
```

- [ ] 所有 7 个修复编译通过
- [ ] SearchPage 间距视觉正确
- [ ] 圆角值使用 AppRadius 常量
- [ ] dispose 方法完整
- [ ] ValueKey 已添加
- [ ] 错误处理覆盖完整
- [ ] 提交 commit: `fix: phase 1 - quick fixes for 7 high-priority issues`

---

## Phase 2: 性能优化（本周完成）

**目标**: 解决 3 个高优先级性能瓶颈 + 2 个中优先级性能问题
**预计耗时**: 7 小时
**前置条件**: Phase 1 完成
**验证方式**: DevTools Performance + Memory 视图

### Task 2.1: PlaylistDetailPage 分组缓存
- **问题编号**: #8 (P0-1)
- **优先级**: 🔴 高
- **文件**: `lib/ui/pages/library/playlist_detail_page.dart:172`
- **耗时**: 1 小时
- **依赖**: 无
- **预期收益**: 减少 90% 计算，滚动流畅度显著提升

**问题分析**:
每次 `build` 都执行 `_groupTracksByPage(tracks)` 分组计算，500 首歌耗时 15-30ms，导致滚动卡顿。

**方案 A（推荐 - State 缓存）**:
```dart
class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  List<Track> _cachedTracks = [];
  Map<int, List<Track>> _cachedGroupedTracks = {};

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(playlistDetailProvider(widget.playlistId))
        .valueOrNull?.tracks ?? [];

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

**方案 B（HookConsumerWidget）**:
```dart
final groupedTracks = useMemoized(
  () => _groupTracksByPage(tracks),
  [tracks.length],
);
```

**操作步骤**:
1. 添加 `_cachedTracks` 和 `_cachedGroupedTracks` 字段
2. 在 build 中添加长度比较守卫
3. 替换直接调用为缓存读取

**验证**:
```
flutter run --profile
# DevTools Performance 视图 → 滚动 500+ 首歌单 → 帧率稳定 55-60 FPS
```

---

### Task 2.2: HomePage 过度 rebuild 优化
- **问题编号**: #9 (P0-2)
- **优先级**: 🔴 高
- **文件**: `lib/ui/pages/home/home_page.dart:86-88`
- **耗时**: 2 小时
- **依赖**: Task 1.5（ValueKey 先添加）
- **预期收益**: 减少 70% rebuild，提升响应速度

**问题分析**:
HomePage 同时 `ref.watch` 3 个 provider（recentHistory, bilibiliRanking, youtubeRanking），任何一个变化都导致整页重建。

**修复方案（拆分独立 Widget）**:

```dart
// 主页面只负责布局
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Column(
      children: [
        _buildQuickActions(),
        _RecentHistorySection(),   // 独立 ConsumerWidget
        _BilibiliRankingSection(), // 独立 ConsumerWidget
        _YoutubeRankingSection(),  // 独立 ConsumerWidget
      ],
    ),
  );
}

// 每个 Section 独立监听自己的 provider
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

**操作步骤**:
1. 将 3 个 `ref.watch` 从主 build 中移除
2. 创建 3 个独立的 `ConsumerWidget` 子类
3. 将对应的 build 方法移入各自的 Widget
4. 确保 `_buildXxx` 方法可被子 Widget 访问（提取为静态方法或顶层函数）

**验证**:
- DevTools Performance 视图：刷新单个排行榜时，其他 Section 不重建
- 使用 `debugPrintRebuildDirtyWidgets = true` 确认 rebuild 范围

---

### Task 2.3: FileExistsCache 页面级预加载
- **问题编号**: #14 (P1-1)
- **优先级**: 🟡 中
- **文件**: 多个页面
- **耗时**: 2 小时
- **依赖**: 无

**问题分析**:
FileExistsCache 的异步检查在 build 中触发，导致首次渲染时出现闪烁。

**修复方案**:
1. 在页面 `initState` 或 `didChangeDependencies` 中预加载
2. 使用 `FutureBuilder` 或 loading 状态避免闪烁

**操作步骤**:
1. 识别所有使用 `fileExistsCacheProvider` 的页面
2. 在页面初始化时批量预加载相关文件路径
3. 添加 loading 占位符避免闪烁

**验证**: 页面首次加载无闪烁，下载状态图标立即显示

---

### Task 2.4: PlayerPage const 构造函数优化
- **问题编号**: #15 (P1-2)
- **优先级**: 🟡 中
- **文件**: `lib/ui/pages/player/player_page.dart`
- **耗时**: 2 小时
- **依赖**: 无

**操作步骤**:
1. 审查 PlayerPage 中所有子 Widget
2. 将不依赖运行时数据的 Widget 标记为 `const`
3. 提取静态部分为独立 const Widget

**验证**: DevTools Performance 视图确认 rebuild 范围缩小

---

### Task 2.5: 文件删除异步化
- **问题编号**: #16 (P1-3)
- **优先级**: 🟡 中
- **文件**: 删除操作相关代码
- **耗时**: 2 小时（与 Task 3.3 文件操作错误处理可合并）
- **依赖**: 无

**问题分析**:
批量删除 100 首歌的文件操作阻塞主线程 2-3 秒。

**修复方案**:
```dart
// 使用 compute 或 Isolate 执行批量删除
Future<void> deleteFiles(List<String> paths) async {
  await compute(_deleteFilesInIsolate, paths);
}

static Future<void> _deleteFilesInIsolate(List<String> paths) async {
  for (final path in paths) {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (_) {
      // 单个文件删除失败不影响其他文件
    }
  }
}
```

**验证**: 批量删除时 UI 不冻结

---

### Phase 2 完成检查

```bash
flutter analyze
flutter run --profile  # DevTools 性能验证
```

- [ ] PlaylistDetailPage 滚动 500+ 首歌帧率 ≥ 55 FPS
- [ ] HomePage 单个 Section 刷新不触发整页重建
- [ ] FileExistsCache 预加载无闪烁
- [ ] PlayerPage rebuild 范围缩小
- [ ] 批量删除不阻塞 UI
- [ ] 提交 commit: `perf: phase 2 - performance optimization for 5 bottlenecks`

---

## Phase 3: 稳定性增强（本周完成）

**目标**: 修复竞态条件、Timer 泄漏、文件操作错误处理
**预计耗时**: 6 小时
**前置条件**: Phase 1 完成（dispose 方法已修复）
**验证方式**: 压力测试 + DevTools Memory

### Task 3.1: DownloadService Isolate 取消竞态
- **问题编号**: #12 (R2)
- **优先级**: 🔴 高
- **文件**: `lib/services/download/download_service.dart:407-420`
- **耗时**: 30 分钟
- **依赖**: 无

**问题分析**:
`pauseTask()` 和 `_startDownload()` 的 `finally` 块都会移除 isolate 并递减 `_activeDownloads`，导致计数不准确。

**修复方案**:
```dart
void pauseTask(int taskId) {
  final isolateInfo = _activeDownloadIsolates.remove(taskId);
  if (isolateInfo != null) {
    isolateInfo.receivePort.close();
    isolateInfo.isolate.kill();
    _activeDownloads--;  // 在这里递减
  }
}

// _startDownload() finally 块
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

**验证**: 快速暂停/恢复下载 10 次，确认 `_activeDownloads` 计数准确

---

### Task 3.2: AudioController 快速切歌竞态
- **问题编号**: #13 (R3)
- **优先级**: 🔴 高
- **文件**: `lib/services/audio/audio_provider.dart` (`_restoreSavedState()`)
- **耗时**: 30 分钟
- **依赖**: Task 1.4（dispose 增强）

**问题分析**:
`setUrl` 和 `play` 之间被取代时，可能短暂播放错误歌曲。

**修复方案**:
```dart
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

**验证**:
```dart
// 快速连续点击 5 首不同歌曲
// 验证只播放最后一首，无短暂错误播放
```

---

### Task 3.3: 文件操作错误处理加固
- **问题编号**: #10 (E1)
- **优先级**: 🔴 高
- **文件**: `lib/services/download/download_service.dart`
- **耗时**: 2-3 小时
- **依赖**: Task 1.7（Isolate 错误结构化）

**子任务**:

**3.3a: 元数据保存错误处理（行 844）**
```dart
try {
  await metadataFile.writeAsString(jsonEncode(metadata));
} on FileSystemException catch (e) {
  logWarning('Failed to save metadata for ${task.id}: $e');
  // 元数据保存失败不应阻止下载完成
}
```

**3.3b: TOCTOU 竞态修复（行 709）**
```dart
try {
  final file = File(savePath);
  if (!await file.exists()) {
    logError('Download completed but file not found: $savePath');
    throw Exception('Downloaded file not found');
  }
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

**验证**: 模拟磁盘满/权限不足场景，确认不崩溃

---

### Task 3.4: Timer 未取消修复（5 个服务类）
- **问题编号**: #11 (R1)
- **优先级**: 🔴 高
- **文件**: 5 个服务类
- **耗时**: 2 小时
- **依赖**: 无

**需要修复的服务类**:

| 服务类 | 文件 | Timer 字段 | 额外清理 |
|--------|------|-----------|----------|
| RankingCacheService | `ranking_cache_service.dart` | `_refreshTimer` | `_stateController.close()` |
| RadioRefreshService | `radio_refresh_service.dart` | `_refreshTimer` | 无 |
| RadioController | `radio_controller.dart` | `_playDurationTimer`, `_infoRefreshTimer` | `super.dispose()` |
| ConnectivityService | `connectivity_service.dart` | `_pollingTimer` | `_stateController.close()` |

**操作步骤**:
1. 为每个服务类添加或完善 `dispose()` 方法
2. 取消所有 Timer 并置 null
3. 关闭所有 StreamController
4. 确保 dispose 在应用退出时被调用

**模板**:
```dart
void dispose() {
  _refreshTimer?.cancel();
  _refreshTimer = null;
  _stateController.close();
}
```

**验证**: DevTools Memory 视图，长时间运行后无 Timer 泄漏

---

### Task 3.5: 下载失败主动提示
- **问题编号**: #17 (E4)
- **优先级**: 🟡 中
- **文件**: `lib/services/download/download_service.dart`
- **耗时**: 30 分钟
- **依赖**: Task 3.3

**操作步骤**:
1. 在下载失败回调中添加 Toast 提示
2. 区分网络错误、文件系统错误、取消等类型

**验证**: 断网下载时显示友好错误提示

---

### Task 3.6: YouTube 限流检测优化
- **问题编号**: #18 (E5)
- **优先级**: 🟡 中
- **文件**: `lib/data/sources/youtube_source.dart` (`_isRateLimitError`)
- **耗时**: 30 分钟
- **依赖**: 无

**问题分析**:
当前使用字符串匹配检测限流，不够可靠。

**操作步骤**:
1. 增加 HTTP 状态码 429 检测
2. 增加响应头 `Retry-After` 解析
3. 保留字符串匹配作为 fallback

**验证**: 模拟 429 响应，确认正确识别限流

---

### Phase 3 完成检查

```bash
flutter analyze
flutter test
```

- [ ] Isolate 取消竞态修复，计数准确
- [ ] 快速切歌无短暂错误播放
- [ ] 文件操作全部有 try-catch
- [ ] 5 个服务类 dispose 完整
- [ ] 下载失败有 Toast 提示
- [ ] YouTube 限流检测可靠
- [ ] 提交 commit: `fix: phase 3 - stability enhancement for race conditions and resource cleanup`

---

## Phase 4: 代码质量提升（下周完成）

**目标**: 统一 UI 组件、完善业务逻辑、重构错误处理
**预计耗时**: 10 小时
**前置条件**: Phase 1-3 完成
**验证方式**: 代码审查 + 功能测试

### Task 4.1: 歌曲列表项样式统一
- **问题编号**: #20 (UI3)
- **优先级**: 🟡 中
- **文件**: HomePage, ExplorePage, PlaylistDetailPage
- **耗时**: 4-6 小时
- **依赖**: Task 2.2（HomePage 拆分后更容易统一）

**操作步骤**:
1. 扩展现有 `TrackTile` 组件，支持排行榜模式
2. 统一 thumbnail 尺寸、文字样式、菜单操作
3. 逐页替换自定义实现

**验证**: 三个页面的歌曲列表项视觉一致

---

### Task 4.2: Mix 模式队列操作限制
- **问题编号**: #22 (L1)
- **优先级**: 🟡 中
- **文件**: `lib/services/audio/audio_provider.dart` (`addToQueue/addNext`)
- **耗时**: 1 小时
- **依赖**: 无

**操作步骤**:
1. 在 `addToQueue` 和 `addNext` 方法中检查 Mix 模式
2. Mix 模式下返回 false 并显示 Toast

**验证**: Mix 模式下添加队列操作被正确阻止

---

### Task 4.3: 队列操作返回值语义明确化
- **问题编号**: #23 (L2)
- **优先级**: 🟡 中
- **文件**: `lib/services/audio/audio_provider.dart`
- **耗时**: 1 小时
- **依赖**: Task 4.2

**操作步骤**:
1. 定义队列操作结果枚举（success, blocked, duplicate, error）
2. 替换 bool 返回值为枚举
3. UI 层根据结果显示不同提示

---

### Task 4.4: 下载错误处理重构
- **问题编号**: #19 (E6)
- **优先级**: 🟡 中
- **文件**: `lib/services/download/download_service.dart` (`_startDownload`)
- **耗时**: 2 小时
- **依赖**: Task 3.3（文件操作错误处理）

**操作步骤**:
1. 提取重复的错误处理逻辑为私有方法
2. 统一错误分类和日志格式
3. 减少代码重复

---

### Task 4.5: StreamController 未关闭修复
- **问题编号**: #25 (R4)
- **优先级**: 🟡 中
- **文件**: 部分服务类
- **耗时**: 1 小时
- **依赖**: Task 3.4（Timer dispose 已修复）

**操作步骤**:
1. 搜索所有 `StreamController` 实例
2. 确认每个都在 dispose 中调用 `.close()`
3. 补全缺失的关闭逻辑

---

### Phase 4 完成检查

- [ ] 歌曲列表项样式统一
- [ ] Mix 模式限制实现
- [ ] 队列操作返回值语义明确
- [ ] 下载错误处理无重复代码
- [ ] 所有 StreamController 正确关闭
- [ ] 提交 commit: `refactor: phase 4 - code quality improvements`

---

## Phase 5: 可选优化（按需执行）

**目标**: 进一步优化性能和代码复用
**预计耗时**: 8 小时
**前置条件**: Phase 1-4 完成
**优先级**: 低，按需安排

### Task 5.1: 共享菜单操作处理器
- **问题编号**: #33 (UI4)
- **文件**: 新建 `lib/ui/widgets/track_menu_handler.dart`
- **耗时**: 3 小时

### Task 5.2: 统一空状态组件
- **问题编号**: #34 (UI5)
- **文件**: 新建 `lib/ui/widgets/empty_state.dart`
- **耗时**: 1 小时

### Task 5.3: 批量队列操作方法
- **问题编号**: #35 (L3)
- **文件**: `lib/services/audio/audio_provider.dart`
- **耗时**: 2 小时

### Task 5.4: 动态图片缓存大小
- **问题编号**: #30
- **文件**: `network_image_cache_service.dart`
- **耗时**: 2 小时

### Task 5.5: Settings 页面 ListView.builder
- **问题编号**: #29
- **文件**: `lib/ui/pages/settings/settings_page.dart`
- **耗时**: 30 分钟

---

## 依赖关系图

```
Phase 1 (无依赖，可并行)
├── Task 1.1 (SearchPage AppBar)
├── Task 1.2 (圆角值)
├── Task 1.3 (QueueManager dispose) ──────┐
├── Task 1.4 (AudioController dispose) ◄──┘ (建议先修 1.3)
├── Task 1.5 (ValueKey) ─────────────────────┐
├── Task 1.6 (Future.microtask)              │
└── Task 1.7 (Isolate 错误) ────────────┐    │
                                         │    │
Phase 2 (依赖 Phase 1)                  │    │
├── Task 2.1 (分组缓存) ← 无依赖       │    │
├── Task 2.2 (HomePage rebuild) ◄────────┼────┘ (依赖 1.5)
├── Task 2.3 (FileExistsCache) ← 无依赖 │
├── Task 2.4 (PlayerPage const) ← 无依赖│
└── Task 2.5 (文件删除异步) ← 无依赖    │
                                         │
Phase 3 (依赖 Phase 1)                  │
├── Task 3.1 (Isolate 竞态) ← 无依赖    │
├── Task 3.2 (切歌竞态) ← 依赖 1.4      │
├── Task 3.3 (文件操作) ◄───────────────┘ (依赖 1.7)
├── Task 3.4 (Timer dispose) ← 无依赖
├── Task 3.5 (下载提示) ← 依赖 3.3
└── Task 3.6 (限流检测) ← 无依赖

Phase 4 (依赖 Phase 1-3)
├── Task 4.1 (列表项统一) ← 依赖 2.2
├── Task 4.2 (Mix 限制) ← 无依赖
├── Task 4.3 (返回值语义) ← 依赖 4.2
├── Task 4.4 (错误处理重构) ← 依赖 3.3
└── Task 4.5 (StreamController) ← 依赖 3.4

Phase 5 (依赖 Phase 4)
└── 所有任务可独立执行
```

---

## 进度跟踪

| Phase | 任务数 | 预计耗时 | 状态 |
|-------|--------|---------|------|
| Phase 1: 快速修复 | 7 | 1.5h | ⬜ 待开始 |
| Phase 2: 性能优化 | 5 | 7h | ⬜ 待开始 |
| Phase 3: 稳定性增强 | 6 | 6h | ⬜ 待开始 |
| Phase 4: 代码质量 | 5 | 10h | ⬜ 待开始 |
| Phase 5: 可选优化 | 5 | 8h | ⬜ 待开始 |
| **总计** | **28** | **~32.5h** | |

---

## 预期改善效果

| 指标 | 当前 | Phase 1-3 后 | 全部完成后 |
|------|------|-------------|-----------|
| 列表滚动帧率 | 45-55 FPS | 55-60 FPS | 60 FPS |
| 页面切换延迟 | 200-300ms | 150-200ms | 100-150ms |
| 歌单详情加载 | 1200ms | 400ms | 400ms |
| 内存泄漏风险 | 中等 | 低 | 极低 |
| 24h 运行内存 | 400-500 MB | 300-400 MB | 250-350 MB |
| 崩溃率 | 0.5% | 0.2% | 0.1% |

---

## Git 提交策略

```bash
# Phase 1
git commit -m "fix: SearchPage AppBar trailing spacing"
git commit -m "fix: replace hardcoded border radius with AppRadius"
git commit -m "fix: complete QueueManager and AudioController dispose"
git commit -m "perf: add ValueKey to ranking lists"
git commit -m "fix: add error handling for Future.microtask and Isolate"

# Phase 2
git commit -m "perf: cache PlaylistDetailPage group computation"
git commit -m "perf: split HomePage into independent ConsumerWidgets"
git commit -m "perf: preload FileExistsCache and optimize PlayerPage"
git commit -m "perf: async file deletion to prevent UI freeze"

# Phase 3
git commit -m "fix: resolve Isolate cancel and track-switch race conditions"
git commit -m "fix: robust file operation error handling in DownloadService"
git commit -m "fix: complete Timer disposal for all service classes"
git commit -m "fix: improve download failure notification and rate limit detection"

# Phase 4-5
git commit -m "refactor: unify track list item styles across pages"
git commit -m "feat: implement Mix mode queue operation restrictions"
git commit -m "refactor: restructure download error handling"
```

---

**最后更新**: 2026-02-17
**维护者**: 开发团队
**关联文档**:
- `FINAL-COMPREHENSIVE-REPORT.md` - 完整审查报告
- `ISSUES-CHECKLIST.md` - 问题清单
- `QUICK-FIX-GUIDE.md` - 快速修复代码
