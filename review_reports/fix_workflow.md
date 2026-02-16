# FMP 代码审查修复 Workflow

> 基于 `review_reports/00_summary.md` 审查汇总
> 总计：11 个严重问题 + 27 个中等问题
> 预估总工时：3-5 个工作日（按单人全职计算）

---

## Phase 1: 稳定性与崩溃防护（预估 2-3h）

> 目标：消除可能导致应用崩溃的问题，建立全局错误兜底机制

### Task 1.1: main.dart 添加全局错误处理
- **优先级**: P0
- **文件**: `lib/main.dart`
- **修改内容**:
  1. 添加 `FlutterError.onError` 捕获 Flutter 框架层渲染错误
  2. 用 `runZonedGuarded` 包裹整个 `main()` 函数体，捕获未处理的异步异常
  3. Release 模式下替换红屏为友好的错误页面
  4. 将错误写入项目已有的 logger 系统
- **参考代码**:
  ```dart
  void main(List<String> args) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      logError('FlutterError: ${details.exception}', details.exception, details.stack);
    };

    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      MediaKit.ensureInitialized();
      // ... 现有初始化代码 ...
      runApp(ProviderScope(child: TranslationProvider(child: const FMPApp())));
    }, (error, stackTrace) {
      logError('Uncaught error', error, stackTrace);
    });
  }
  ```
- **验证**: 在 debug 模式下故意抛出未捕获异常，确认日志正确记录且应用不崩溃
- **依赖**: 无

### Task 1.2: AudioController.play()/pause()/togglePlayPause() 添加 try-catch
- **优先级**: P0
- **文件**: `lib/services/audio/audio_provider.dart`
- **修改内容**:
  1. `play()` 方法包裹 try-catch，catch 中 `logError` + `state = state.copyWith(error: ...)`
  2. `pause()` 方法包裹 try-catch，catch 中 `logError`（pause 失败不需要更新 error state）
  3. `togglePlayPause()` 如果调用了 play/pause 则已被覆盖，检查是否有其他未保护的路径
  4. `seekTo()`、`seekForward()`、`seekBackward()` 检查是否有 try-catch
- **参考代码**:
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
- **验证**: 模拟 media_kit 异常（如断网时播放），确认错误被捕获且 UI 显示错误状态
- **依赖**: 无

### Task 1.3: BilibiliSource 补全通用 catch 块
- **优先级**: P1
- **文件**: `lib/data/sources/bilibili_source.dart`
- **修改内容**:
  为以下方法添加通用 catch 块（在现有 `on DioException catch` 之后）：
  1. `getTrackInfo()` (~L141)
  2. `getVideoDetail()` (~L570)
  3. `getRankingVideos()` (~L677)
  4. `getVideoPages()` (~L524)
  5. `parsePlaylist()` (~L416)
  6. `searchLiveRooms()` (~L817)
- **模式**:
  ```dart
  } on DioException catch (e) {
    throw _handleDioError(e);
  } catch (e) {
    if (e is BilibiliApiException) rethrow;
    logError('Unexpected error in methodName: $e');
    throw BilibiliApiException(numericCode: -999, message: e.toString());
  }
  ```
  > **注意**：BilibiliApiException 构造函数参数已从 `code` 改为 `numericCode`（2026-02 统一异常基类重构）
- **验证**: 确认 `flutter analyze` 无新增 warning
- **依赖**: 无

### Task 1.4: _loadMoreMixTracks() 中 YouTubeSource 实例释放
- **优先级**: P1
- **文件**: `lib/services/audio/audio_provider.dart` (~L1510)
- **修改内容**:
  - 方案 A（推荐）：使用已有的全局 YouTubeSource 实例而非创建局部实例
  - 方案 B：在 finally 块中调用 `youtubeSource.dispose()`
- **验证**: 确认 Mix 播放模式下加载更多曲目正常工作
- **依赖**: 无

---

## Phase 2: 性能优化（预估 3-4h）

> 目标：消除 MiniPlayer 高频 rebuild，修复列表滚动抖动，优化 Provider 监听粒度

### Task 2.1: MiniPlayer 拆分子 Widget 减少 rebuild
- **优先级**: P0
- **文件**: `lib/ui/widgets/player/mini_player.dart`
- **修改内容**:
  将 MiniPlayer 拆分为 4 个独立的 ConsumerWidget：
  1. `_MiniPlayerProgressBar` — 只 `ref.watch(audioControllerProvider.select((s) => s.progress))`
  2. `_MiniPlayerTrackInfo` — 只 `ref.watch(currentTrackProvider)`
  3. `_MiniPlayerControls` — 只 `ref.watch(isPlayingProvider)` + volume 相关
  4. `MiniPlayer`（外壳）— 只 `ref.watch(currentTrackProvider)` 判断是否显示

  外壳 MiniPlayer 不再 watch 整个 `audioControllerProvider`。
- **预期效果**: 播放时 rebuild 频率从每秒多次降低到仅进度条每秒更新，其他子组件只在切歌/播放状态变化时 rebuild
- **验证**: 使用 Flutter DevTools 的 Widget rebuild 计数器，对比修改前后 MiniPlayer 的 rebuild 次数
- **依赖**: 无

### Task 2.2: ExploreTrackTile 和 RankingTrackTile 改为扁平布局
- **优先级**: P0
- **文件**:
  - `lib/ui/pages/explore/explore_page.dart` (`_ExploreTrackTile`, ~L267)
  - `lib/ui/pages/home/home_page.dart` (`_RankingTrackTile`, ~L997)
- **修改内容**:
  1. 将 `ListTile + leading: Row(...)` 替换为 `InkWell + Padding + Row` 扁平布局
  2. 统一排名数字宽度为 `28`（支持三位数排名）
  3. 考虑提取为共享的 `RankingTrackTile` 组件（放在 `lib/ui/widgets/`）
- **目标布局**:
  ```dart
  InkWell(
    onTap: () => ...,
    onLongPress: () => ...,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('$rank', ...)),
          const SizedBox(width: 12),
          TrackThumbnail(track: track, size: AppSizes.thumbnailMedium),
          const SizedBox(width: 12),
          Expanded(child: Column(/* title, subtitle */)),
          _buildMenuButton(),
        ],
      ),
    ),
  )
  ```
- **验证**: 快速滚动排行榜列表，确认无布局抖动
- **依赖**: 无

### Task 2.3: HomePage 拆分 section 为独立 ConsumerWidget
- **优先级**: P1
- **文件**: `lib/ui/pages/home/home_page.dart`
- **修改内容**:
  1. 将 `_buildNowPlaying` 提取为 `_NowPlayingSection extends ConsumerWidget`，只 watch `currentTrackProvider` + `isPlayingProvider`
  2. 将 `_buildQueuePreview` 提取为 `_QueuePreviewSection extends ConsumerWidget`，只 watch `queueProvider`
  3. 外层 `_HomePageState.build()` 不再 watch `audioControllerProvider`
- **验证**: 播放时首页不再因 position 更新而整体 rebuild
- **依赖**: 无

### Task 2.4: FileExistsCache 使用 .select() 减少级联 rebuild
- **优先级**: P1
- **文件**: `lib/ui/widgets/track_thumbnail.dart` (~L50) 及其他使用 `fileExistsCacheProvider` 的组件
- **修改内容**:
  - 方案 A（简单）：在 TrackThumbnail 中使用 `ref.watch(fileExistsCacheProvider.select((state) => state.contains(specificPath)))` 只监听特定路径
  - 方案 B（彻底）：重构 FileExistsCache 为更细粒度的通知机制
  - 推荐方案 A，改动最小
- **验证**: 下载完成一首歌后，确认只有该歌曲的缩略图 rebuild，而非所有可见缩略图
- **依赖**: 无

### Task 2.5: 其他中等性能优化（可选，按需处理）
- **文件/内容**:
  - `lyrics_display.dart`: `_ensureRefWidth` 改为采样测量（最多 20 行）
  - `now_playing_indicator.dart`: 考虑用 CustomPainter 替代 Widget 树
  - `search_page.dart`: 将 `allTracks` 合并列表移到 provider 内部
  - `queue_page.dart`: `_onPositionsChanged` 添加简单节流
- **优先级**: P2
- **依赖**: 无

---

## Phase 3: 错误/空状态 UI 统一（预估 2-3h）

> 目标：所有页面统一使用 ErrorDisplay 组件，消除样式不一致

### Task 3.1: 审查并增强 ErrorDisplay 组件
- **优先级**: P0
- **文件**: `lib/ui/widgets/error_display.dart`
- **修改内容**:
  1. 确认 `ErrorDisplay` 支持以下场景：
     - 全页错误（带重试按钮）
     - 全页空状态（自定义图标 + 标题 + 可选操作按钮）
     - compact 模式（用于列表内嵌错误）
  2. 如果缺少 `ErrorDisplay.empty()` 命名构造函数，添加它
  3. 确保支持自定义图标、标题、副标题、操作按钮列表
- **验证**: 组件 API 满足所有页面的错误/空状态需求
- **依赖**: 无

### Task 3.2: 逐页替换手动拼装的错误/空状态
- **优先级**: P0
- **涉及文件**（按修改量排序）:

  | 页面 | 需替换的状态 | 当前问题 |
  |------|-------------|---------|
  | `explore_page.dart` | 错误状态 | 图标 size: 48 |
  | `downloaded_category_page.dart` | 错误 + 空状态 | 图标 size: 64 |
  | `downloaded_page.dart` | 错误 + 空状态 | 图标 size: 64 |
  | `playlist_detail_page.dart` | 错误 + 空状态 | 图标 size: 64 |
  | `download_manager_page.dart` | 空状态 | Colors.grey 硬编码 |
  | `library_page.dart` | 空状态 | 图标 size: 80 |
  | `radio_page.dart` | 空状态 | 图标 size: 80 |
  | `queue_page.dart` | 空状态 | 图标 size: 64 |
  | `play_history_page.dart` | 空状态 | 需确认 |

- **替换模式**:
  ```dart
  // 错误状态
  // Before: Icon(Icons.error_outline, size: 48/64) + Text + Button
  // After:
  ErrorDisplay(
    type: ErrorType.general,
    message: t.general.loadFailed,
    onRetry: _onRefresh,
  )

  // 空状态
  // Before: Icon(Icons.xxx, size: 64/80) + Text + optional Button
  // After:
  ErrorDisplay.empty(
    icon: Icons.library_music,
    title: t.library.emptyPlaylist,
    action: TextButton(onPressed: ..., child: Text(t.library.createPlaylist)),
  )
  ```
- **验证**: 逐页检查错误和空状态的视觉效果一致
- **依赖**: Task 3.1

---

## Phase 4: 菜单与功能一致性（预估 2-3h）

> 目标：补全缺失的菜单项，统一各页面的操作能力

### Task 4.1: 搜索页本地结果添加「歌词匹配」菜单
- **优先级**: P0
- **文件**: `lib/ui/pages/search/search_page.dart`
- **修改内容**:
  1. `_LocalGroupTile._buildMenuItems` (~L1368): 添加 `matchLyrics` 菜单项
  2. `_LocalTrackTile._buildMenuItems` (~L1513): 添加 `matchLyrics` 菜单项
  3. 对应的 `_handleMenuAction` 添加 `matchLyrics` case 处理
- **参考**: `_SearchResultTile` 中已有的 `matchLyrics` 实现
- **验证**: 搜索页「歌单中」区域的歌曲菜单出现「歌词匹配」选项，点击后正常弹出歌词搜索
- **依赖**: 无

### Task 4.2: 首页历史记录添加「歌词匹配」菜单
- **优先级**: P0
- **文件**: `lib/ui/pages/home/home_page.dart`
- **修改内容**:
  1. `_buildHistoryMenuItems` (~L499): 在 `add_to_playlist` 之后添加 `matchLyrics` 菜单项
  2. 对应的 `_handleHistoryMenuAction` 添加 `matchLyrics` case
- **参考**: `play_history_page.dart` 中已有的 `matchLyrics` 实现
- **验证**: 首页历史记录区域的歌曲菜单出现「歌词匹配」选项
- **依赖**: 无

### Task 4.3: DownloadedCategoryPage 添加桌面右键菜单 + 补全菜单项
- **优先级**: P0
- **文件**: `lib/ui/pages/library/downloaded_category_page.dart`
- **修改内容**:
  1. 为 `_GroupHeader` 和歌曲列表项添加 `ContextMenuRegion` 包裹
  2. 歌曲菜单添加 `add_to_playlist` 和 `matchLyrics` 选项
  3. 确保菜单项顺序与其他页面一致：播放 → 下一首播放 → 添加到队列 → 添加到歌单 → 歌词匹配 → 删除下载
- **参考**: `playlist_detail_page.dart` 的 ContextMenuRegion 使用方式
- **验证**: 桌面端右键点击歌曲弹出完整菜单
- **依赖**: 无

### Task 4.4: 统一 Toast i18n 命名空间
- **优先级**: P1
- **文件**: i18n 文件 + 各页面
- **修改内容**:
  1. 在 i18n 中创建公共命名空间 `t.common`（或 `t.general`），包含：
     - `addedToQueue` / `addedToNext` / `addedToPlaylist`
     - `play` / `playNext` / `addToQueue` / `addToPlaylist` / `matchLyrics`
  2. 各页面的 Toast 消息和菜单文字改用公共 key
  3. 删除各页面重复定义的 i18n key（保留向后兼容则标记 deprecated）
- **涉及页面**: explore_page, home_page, search_page, playlist_detail_page, downloaded_category_page, play_history_page
- **验证**: 所有页面的 Toast 消息文字完全一致
- **依赖**: 无

---

## Phase 5: 内存安全加固（预估 1-2h）

> 目标：修复资源泄漏风险，添加缓存保护

### Task 5.1: RankingCacheService Provider onDispose 添加清理
- **优先级**: P0
- **文件**: `lib/services/cache/ranking_cache_service.dart` (~L160)
- **修改内容**:
  ```dart
  ref.onDispose(() {
    service._networkRecoveredSubscription?.cancel();
    service._networkRecoveredSubscription = null;
    service._networkMonitoringSetup = false;
  });
  ```
- **验证**: 确认 Provider 重建时不会产生重复网络监听
- **依赖**: 无

### Task 5.2: AudioController.dispose() 异步资源释放
- **优先级**: P1
- **文件**: `lib/services/audio/audio_provider.dart` + `lib/providers/` 中定义 audioControllerProvider 的位置
- **修改内容**:
  在 Provider 的 `ref.onDispose` 中添加异步清理：
  ```dart
  ref.onDispose(() {
    // StateNotifier.dispose() 是同步的，无法 await
    // 在 Provider 层面补充异步清理
    controller._audioService.dispose();
  });
  ```
- **验证**: 热重载后确认无资源泄漏警告
- **依赖**: 无

### Task 5.3: FileExistsCache 添加大小限制
- **优先级**: P2
- **文件**: `lib/providers/download/file_exists_cache.dart`
- **修改内容**:
  添加最大条目数限制（如 5000），超出时清除最早添加的条目。可以改用 `LinkedHashSet` 或维护插入顺序。
- **验证**: 模拟大量路径添加，确认缓存不超过限制
- **依赖**: 无

### Task 5.4: import_preview_page 改用 ListView.builder
- **优先级**: P2
- **文件**: `lib/ui/pages/library/import_preview_page.dart` (~L112)
- **修改内容**:
  将 `ListView(children: [...])` + `shrinkWrap: true` 重构为 `CustomScrollView` + `SliverList.builder`
- **验证**: 导入 500+ 首歌曲的歌单，确认页面不卡顿
- **依赖**: 无

---

## Phase 6: UI 规范统一（预估 2-3h）

> 目标：消除硬编码值，统一组件风格

### Task 6.1: 消除硬编码颜色
- **优先级**: P1
- **涉及文件与替换**:

  | 文件 | 硬编码 | 替换为 |
  |------|--------|--------|
  | `download_manager_page.dart` L108 | `Colors.grey` | `colorScheme.outline` |
  | `download_manager_page.dart` L110 | `Colors.grey` | `colorScheme.outline` |
  | `download_manager_page.dart` L345-351 | `Colors.orange/grey/green/red` | `colorScheme.tertiary/outline/primary/error` |
  | `settings_page.dart` L1473 | `Colors.grey` | `colorScheme.outline` |
  | `settings_page.dart` L1535 | `Colors.grey` | `colorScheme.outline` |
  | `settings_page.dart` L298 | `Color(0xFF6750A4)` | `colorScheme.primary` |

- **注意**: 保留语义色彩（LIVE 标签的 `Colors.red`、歌词匹配度的 `Colors.green/orange/red`）
- **验证**: 切换深色/浅色主题，确认替换后的颜色在两种主题下都合适
- **依赖**: 无

### Task 6.2: 消除硬编码 BorderRadius 和动画时长
- **优先级**: P2
- **涉及文件**:
  - `cover_picker_dialog.dart` L320: `BorderRadius.circular(5/8)` → `AppRadius.borderRadiusSm` / `AppRadius.borderRadiusMd`
  - `lyrics_source_settings_page.dart` L128: `BorderRadius.circular(12)` → `AppRadius.borderRadiusLg`
  - `horizontal_scroll_section.dart` L126: `Duration(milliseconds: 400)` → `AnimationDurations.slow` 或新增常量
- **验证**: 视觉效果无变化
- **依赖**: 无

### Task 6.3: 统一菜单项内部布局风格
- **优先级**: P2
- **涉及文件**: `library_page.dart` 的 ContextMenu 部分
- **修改内容**: 将 `Row` 风格的菜单项改为 `ListTile` 风格（与其他页面一致）
- **验证**: 菜单视觉效果与其他页面一致
- **依赖**: 无

### Task 6.4: 提取 PlaylistCard 共享操作
- **优先级**: P2
- **涉及文件**:
  - `lib/ui/pages/home/home_page.dart` (`_HomePlaylistCard`)
  - `lib/ui/pages/library/library_page.dart` (`_PlaylistCard`)
- **修改内容**:
  提取共享的 `PlaylistCardActions` mixin 或工具类，包含：
  - `addAllToQueue()`
  - `shuffleAddToQueue()`
  - `playMix()`
  - `refreshPlaylist()`
  - `showEditDialog()`
  - `showDeleteConfirm()`
  - `showOptionsMenu()`
- **验证**: 两个页面的歌单卡片操作行为完全一致
- **依赖**: 无

---

## Phase 7: 代码风格统一（预估 0.5-1h） ✅ COMPLETED

> 目标：统一小细节，提升代码一致性

### Task 7.1: 统一 const Icon 使用 ✅
- **优先级**: P2
- **涉及文件**: `explore_page.dart` 中菜单 Icon 缺少 `const`
- **修改内容**: 为所有可以 const 的 Icon 添加 `const` 关键字
- **完成情况**: ✅ 已完成 - 为 explore_page.dart 的 5 个菜单 Icon 添加了 const
- **验证**: ✅ `flutter analyze` 无新增 warning

### Task 7.2: 确认 PlayHistoryPage cid vs pageNum 等价性 ✅
- **优先级**: P2
- **文件**: `lib/ui/pages/history/play_history_page.dart` L556
- **修改内容**: 添加注释说明 cid 与 pageNum 的区别
- **完成情况**: ✅ 已完成 - 添加了详细注释说明：
  - `cid`: Bilibili 分P的唯一标识符（稳定的唯一ID）
  - `pageNum`: 分P的显示序号（1, 2, 3...）
  - 当前代码正确使用 cid 进行比较
- **结论**: cid 和 pageNum **不等价**，当前实现正确

### Task 7.3: Provider .when() error 回调添加 debug 日志 ✅
- **优先级**: P2
- **涉及文件**: `explore_page.dart`、`play_history_page.dart`、`create_playlist_dialog.dart`
- **修改内容**: 将 `error: (_, __)` 改为 `error: (error, stack) { debugPrint(...); return ...; }`
- **完成情况**: ✅ 已完成 - 修改了以下位置：
  - `explore_page.dart`: Bilibili 排行榜错误处理
  - `explore_page.dart`: YouTube 排行榜错误处理
  - `play_history_page.dart`: 播放历史统计错误处理
  - `create_playlist_dialog.dart`: 歌单封面加载错误处理

### Task 7.4: RadioRefreshService Provider 添加注释 ✅
- **优先级**: P2
- **文件**: `lib/services/radio/radio_refresh_service.dart`
- **修改内容**: 在 Provider 定义处添加注释说明为什么不调用 dispose（全局单例设计）
- **完成情况**: ✅ 已完成 - 添加了详细注释说明：
  1. RadioRefreshService.instance 是全局单例，生命週期與應用相同
  2. 單例的 dispose() 由應用退出時統一處理
  3. Provider 僅作為訪問入口，不擁有資源所有權

---

## 执行顺序与依赖关系

```
Phase 1 (稳定性)     ──→ Phase 2 (性能)     ──→ Phase 5 (内存)
     │                       │
     │                       ▼
     │                 Phase 3 (错误UI)  ──→ Phase 6 (UI规范)
     │                                           │
     ▼                                           ▼
Phase 4 (菜单一致性)                       Phase 7 (代码风格)
```

- Phase 1 和 Phase 4 可以并行
- Phase 2 和 Phase 3 可以并行
- Phase 5、6、7 依赖前面的 Phase 完成后再做（避免冲突）
- 每个 Phase 内的 Task 之间大部分无依赖，可以并行

## 验证清单

每个 Phase 完成后执行：
- [ ] `flutter analyze` 无新增 warning/error
- [ ] `flutter build apk` 编译通过
- [ ] `flutter build windows` 编译通过
- [ ] 手动测试核心流程：搜索 → 播放 → 切歌 → 暂停 → 恢复
- [ ] 手动测试修改涉及的页面

全部完成后执行：
- [ ] 深色/浅色主题切换测试
- [ ] Android + Windows 双平台测试
- [ ] 长时间播放测试（30min+），观察内存占用趋势
- [ ] 快速滚动排行榜列表，确认无抖动
- [ ] 各页面错误/空状态视觉一致性检查
