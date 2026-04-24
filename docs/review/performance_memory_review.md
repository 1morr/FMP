# FMP 性能 / 内存专项审查报告

## 1. 审查范围

本次审查聚焦 Flutter 项目 `C:/Users/Roxy/Visual Studio Code/FMP` 的性能与内存风险点，覆盖：

- Riverpod provider、selector、watch/rebuild 范围
- Isar watch、查询与写入频率
- 图片加载、缩略图 URL 优化、磁盘/内存缓存
- 歌曲队列、播放历史、搜索结果等大列表渲染
- 音频后端资源管理（Android just_audio / Windows media_kit）
- 下载 isolate、进度流、下载列表刷新
- 歌词缓存、歌词显示与桌面歌词窗口同步
- Android / Windows 平台差异相关的资源使用

已阅读项目根 `CLAUDE.md` 与 `.serena/memories/` 中的 `download_system.md`、`ui_coding_patterns.md`、`refactoring_lessons.md`、`code_style.md`、`update_system.md`。本报告只基于静态代码审查，未修改业务代码，未运行 Flutter 性能 profiling。

## 2. 总体结论

整体看，项目已经有较多针对性能和内存的主动优化：

- 图片入口统一走 `ImageLoadingService` / `TrackThumbnail`，未发现直接 `Image.network()` / `Image.file()` 使用；`CachedNetworkImage` 配置了磁盘缓存和 `memCacheWidth/Height`。
- 网络图片缓存有容量上限和后台 isolate 扫描清理；歌词缓存有文件数和总大小限制。
- Windows 下载已经迁移到 isolate，下载进度只进内存流，避免高频 Isar watch 重建。
- 音频后端已做平台拆分：Android 用 `just_audio` 降低包体/内存，Windows 用 `media_kit` 支持设备切换；libmpv 已配置 `vid=no`、较小 demuxer/cache，避免 muxed 视频流解码造成数百 MB 内存峰值。
- 播放器 UI 多处使用 `select()`，队列页使用本地队列副本、`queueVersion` 和 `RepaintBoundary`，说明已经考虑高频 position 更新带来的 rebuild。

仍然存在几处真实可优化点，优先级最高的是：

1. `PlayerState.queue` 在每次 position 更新时被反复携带，可能让大队列场景下 selector/相等性检查做额外 O(N) 工作。
2. 播放历史 provider 每次历史变化都加载最多 1000 条记录，再在内存中过滤/排序/统计；历史页把同一天所有 item 一次性展开到一个 `Column`，日内记录多时会失去列表懒加载。
3. `TrackRepository.save()` 在 debug 构建中每次保存都构造 StackTrace，下载完成、队列/Track 更新或批量导入时 CPU 与日志 I/O 开销偏高。
4. `FileExistsCache` 只缓存“存在”的路径，缺少 negative cache；在大量未下载/缺 cover/avatar 的列表中，会重复发起 `File.exists()` microtask。
5. 下载管理页分组后用 `ListView(children: [...map])` 一次性构建全部 pending/paused/failed/completed 任务，不适合任务堆积场景。

以下问题按收益和确定性排序。

## 3. 性能/内存问题列表

### P1-01. 播放进度高频更新携带完整队列，导致大队列 selector 做额外 O(N) 工作

- **等级**：高
- **标题**：高频 `PlayerState` 更新包含 `queue` 大列表
- **影响模块**：音频状态、迷你播放器、播放器页、队列页、首页队列预览
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/services/audio/player_state.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/services/audio/audio_provider.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/queue/queue_page.dart`
- **关键代码位置**：
  - `player_state.dart:27` `final List<Track> queue;`
  - `player_state.dart:137-210` `copyWith()` 每次创建新 `PlayerState` 都携带 `queue`
  - `audio_provider.dart:2313-2352` `_onPositionChanged()` 每个 position 事件调用 `state = state.copyWith(position: position)`
  - `audio_provider.dart:2488-2543` `_updateQueueState()` 将 `queue` 放入 `PlayerState`
  - `queue_page.dart:234-244` `ref.watch(audioControllerProvider.select((s) => s.queue))`
- **触发场景**：队列达到数千首（上限 `AppConstants.maxQueueSize = 10000`），正在播放时 position stream 高频更新；队列页、首页队列预览或任意监听 `queue`/`upcomingTracks` 的 UI 存在。
- **影响范围**：全局播放器状态；Android 与 Windows 都会受影响，队列越大越明显。
- **问题描述**：`PlayerState` 是一个包含完整 `queue` 列表的大对象。即使 `_onPositionChanged()` 只更新 `position`，新的 `PlayerState` 仍然携带旧的 `queue` 引用。Riverpod selector 对 `List<Track>` 的相等性判断在 Dart 中通常会使用列表结构相等/元素比较语义时产生 O(N) 风险；即使没有重建 UI，也会在高频状态更新时反复比较或传播大状态对象。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：position 更新是高频事件；大列表字段跟随同一个高频状态对象传播，会增加 selector 比较成本和对象引用扫描压力。队列页为了同步本地队列还额外读取 `queueVersion`，说明队列实际是低频结构状态，不应该与 position 高频状态耦合。
- **impact**：大队列播放时 CPU 占用升高、低端 Android 掉帧、电池消耗增加；队列页打开时更明显。
- **recommendation**：将队列结构拆出到独立 provider/state，例如 `queueStateProvider` 或 `QueueManager` 专属 `StateNotifier`，`audioControllerProvider` 只保留 `queueVersion`、`currentIndex`、`upcomingTracks` 等小字段；队列页监听队列 provider，播放器/mini player 继续监听高频播放进度 provider。短期可将 `queueProvider` 改为监听 `queueVersion` 后通过 notifier 读取队列，避免高频 position 更新触发大列表 selector。
- **risk**：中等。拆分 provider 会影响多个 UI 入口，需确保临时播放、detached、Mix 模式的队列显示语义不变。
- **immediate?**：是。若目标支持大队列或长时间播放，建议优先处理。
- **category**：Riverpod rebuild / CPU / 内存引用压力
- **steps**：
  1. 用 Flutter DevTools 在 1000/5000/10000 首队列下记录播放时 rebuild 和 CPU profile。
  2. 将队列结构状态从 `PlayerState` 拆到低频 provider。
  3. 队列页只在 `queueVersion` 或队列 provider 变化时同步本地副本。
  4. 回归：播放、下一首、临时播放恢复、清空队列后 detached、Mix 自动加载更多。
- **预期收益**：高
- **是真实高优先级问题还是理论可优化但收益有限**：真实高优先级问题，尤其是队列上限已设置到 10000。

### P1-02. 播放历史每次变化加载 1000 条并内存过滤/排序/统计

- **等级**：高
- **标题**：历史页和首页共享快照过宽，Isar 查询未利用索引/分页
- **影响模块**：播放历史页、首页最近播放、统计、筛选/搜索
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/providers/play_history_provider.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/data/repositories/play_history_repository.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/history/play_history_page.dart`
- **关键代码位置**：
  - `play_history_provider.dart:9-18` `playHistorySnapshotProvider` watch 后每次 `loadHistorySnapshot()`
  - `play_history_repository.dart:260-274` `loadHistorySnapshot(limit: 1000)`
  - `play_history_repository.dart:278-334` `queryHistory()` 先 `where().findAll()`，再内存筛选、排序、分页
  - `play_history_provider.dart:68-86` `filteredPlayHistoryProvider` 再次在内存中过滤/排序
  - `play_history_provider.dart:88-93` `playHistoryStatsProvider` 对同一快照遍历统计
- **触发场景**：播放歌曲新增历史、打开历史页、首页显示最近播放、切换历史筛选/排序/搜索。
- **影响范围**：历史数量上限 1000，当前可控；如果未来提高上限或用户频繁播放，影响会扩大。
- **问题描述**：当前设计用一个 `StreamProvider` 加载最多 1000 条完整历史作为共享快照，所有过滤、排序、分组、统计都在 Dart 内存中进行。仓库层 `queryHistory()` 也先全量 `findAll()` 再筛选，即使传入 offset/limit 也不能减少数据库读取量。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：每次历史 watch 触发都要分配最多 1000 个 Isar 对象列表；筛选/搜索/按播放次数排序会复制 list、构建 map、排序；统计又再次遍历。UI 上任何历史变化会让首页最近播放、历史页、统计都基于同一大快照重新计算。
- **impact**：历史页切换筛选/搜索时 CPU 峰值；播放记录新增时首页可能做不必要计算。当前 1000 条上限下不一定卡顿，但已经是确定性额外开销。
- **recommendation**：拆分用途：
  - 首页最近播放改用仓库 query：按 `playedAt desc` 获取足够小窗口并去重（如最多读取 50-100 条）。
  - 历史页改为分页或按日期范围查询，不要每次全量快照。
  - 统计使用 Isar 聚合/轻量查询，或仅在历史页进入时计算。
  - `queryHistory()` 应尽量在 Isar 查询层完成 source/date/search/排序/limit，而不是 `where().findAll()` 后内存处理。
- **risk**：中等。需要保持历史页多选、按天分组、删除后刷新行为一致。
- **immediate?**：是。该问题收益高且代码位置集中。
- **category**：Isar 查询 / CPU / 内存分配 / rebuild
- **steps**：
  1. 为播放历史字段确认索引（`playedAt`、`sourceType`、`trackKey`、标题搜索需求）。
  2. 将首页最近播放、历史页列表、统计拆成独立 provider。
  3. 在仓库层增加分页/日期范围/源筛选查询。
  4. 用 1000 条历史数据验证筛选、搜索、删除、多选、统计一致性。
- **预期收益**：高
- **是真实高优先级问题还是理论可优化但收益有限**：真实问题；当前上限 1000 让风险可控，但实现方式会随功能增长变成瓶颈。

### P1-03. 历史页按日期分组后同一天所有 item 一次性构建，破坏列表懒加载

- **等级**：高
- **标题**：`SliverList/ListView` 只懒加载日期组，不懒加载组内历史项
- **影响模块**：播放历史页
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/history/play_history_page.dart`
- **关键代码位置**：
  - `play_history_page.dart:458-470` `ListView.builder` 的 item 是日期组
  - `play_history_page.dart:504-572` `_buildDateGroup()` 内部 `...histories.map(...)` 展开全部条目
- **触发场景**：某一天播放记录很多（例如循环播放或长时间使用产生数百条同日记录）并打开历史页。
- **影响范围**：历史页 UI 构建、滚动、图片解码、`TrackThumbnail` 文件检查。
- **问题描述**：外层 `ListView.builder` 只对日期组懒加载。每个日期组内部用 `Column` + spread 一次性构建该日期下所有历史项。若当天有 500 条记录，首屏只需要几十条，但会一次性创建 500 个 `ListTile`、`TrackThumbnail`、菜单区域等 widget。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：组内所有 item 同时构建会增加 widget/element 内存；每个 `TrackThumbnail` 会参与图片 provider、FileExistsCache 逻辑；多选状态变化时整个组更容易重建。
- **impact**：历史页首屏打开慢、滚动卡顿、内存峰值增加。移动端尤其明显。
- **recommendation**：将分组数据 flatten 成统一的 sliver item 列表（header + track item），用单个 `SliverList`/`ListView.builder` 懒加载所有行；或者使用 `CustomScrollView`，每个日期 header 和 item 都作为独立 sliver child。
- **risk**：中等。需要重写折叠/多选分组逻辑，但业务语义清晰。
- **immediate?**：是，建议与 P1-02 一起处理。
- **category**：列表渲染 / 内存 / rebuild
- **steps**：
  1. 构造 `HistoryListRow.header/dateItem` 扁平列表。
  2. 折叠状态过滤掉被折叠组的 item。
  3. 保持 header 级全选/半选逻辑。
  4. 用单日 500/1000 条数据做滚动测试。
- **预期收益**：高
- **是真实高优先级问题还是理论可优化但收益有限**：真实高优先级问题；触发条件是同日记录集中。

### P1-04. `TrackRepository.save()` 每次保存都构造 StackTrace 并输出多条 debug 日志

- **等级**：高
- **标题**：热路径数据库保存包含昂贵 debug 日志和调用栈构造
- **影响模块**：Track 保存、下载完成、队列去重、搜索导入、音频 URL 更新
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/data/repositories/track_repository.dart`
- **关键代码位置**：
  - `track_repository.dart:84-93` `save()` 打印 title、playlistInfo、`StackTrace.current`
  - `track_repository.dart:97-108` `saveAll()` 也输出批量日志
- **触发场景**：下载完成添加路径、批量导入/批量队列 `getOrCreateAll()`、播放刷新 audioUrl、清理下载路径、同步本地文件。
- **影响范围**：Debug 构建和开发 profiling 最明显；Release 下 `_minLevel = info` 会过滤 debug，但 `logDebug()` 的字符串参数在调用前已插值完成，复杂字符串仍可能先构造。
- **问题描述**：`save()` 是数据层热路径，却每次构造 `track.playlistInfo.map(...).join(...)` 和 `StackTrace.current.toString().split(...).take(...).join(...)`。其中 StackTrace 构造和字符串处理很昂贵，且日志本身会进入 500 条缓冲和 debug console。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：大量保存时会分配调用栈字符串、列表、日志对象，并输出控制台；下载/导入批量操作时 CPU 和 I/O 噪音明显，还会污染日志缓冲，降低真正错误日志可读性。
- **impact**：开发/调试环境中批量操作变慢；profile/debug 的性能判断被日志污染。Release 仍存在字符串参数先求值的潜在开销。
- **recommendation**：删除 `save()` 中调用栈日志；如确需诊断，改为临时 feature/debug flag 包裹，并避免默认开启。`AppLogger.debug` 可改成 lazy message（传闭包）或在调用点先判断 debug level 后再构造复杂字符串。
- **risk**：低。只影响诊断日志，不影响业务。
- **immediate?**：是。
- **category**：CPU / 日志 I/O / 内存分配
- **steps**：
  1. 移除或 gated `StackTrace.current` 日志。
  2. 将 playlistInfo 详细日志降级为按需诊断。
  3. 批量下载/导入时观察日志输出和 CPU 变化。
- **预期收益**：高
- **是真实高优先级问题还是理论可优化但收益有限**：真实高优先级问题，因为代码在热路径且开销确定。

### P2-05. `FileExistsCache` 缺少 negative cache，缺失文件会重复异步检查

- **等级**：中
- **标题**：只缓存存在路径，未下载/缺封面头像路径重复 `File.exists()`
- **影响模块**：封面/头像、本地下载标记、播放页信息弹窗、列表滚动
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/providers/download/file_exists_cache.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/widgets/track_thumbnail.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/core/extensions/track_extensions.dart`
- **关键代码位置**：
  - `file_exists_cache.dart:10-13` 注释说明只缓存存在文件
  - `file_exists_cache.dart:33-39` `exists()` 未命中即安排检查并返回 false
  - `file_exists_cache.dart:44-52` `getFirstExisting()` 未命中安排刷新
  - `file_exists_cache.dart:142-168` pending 去重只覆盖正在检查的一批，检查完成后缺失路径不缓存
  - `track_thumbnail.dart:68-71` build 中 localCoverPath null 时触发 `getFirstExisting()`
  - `track_extensions.dart:56-80` cover/avatar 都依赖 `getFirstExisting()`
- **触发场景**：大量曲目有下载路径但缺 `cover.jpg`/`avatar.jpg`，或文件被删除但 DB 路径尚未清理；列表滚动反复进出视口。
- **影响范围**：所有显示 `TrackThumbnail`、`TrackCover`、本地头像的 UI。
- **问题描述**：缓存最大 5000 条只保存存在路径。不存在的路径检查完成后不记忆，下一次 widget build 或滚动回该 item 会再次 `File.exists()`。`_pendingRefreshPaths` 只能避免同一时刻重复检查，无法避免后续重复检查。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：文件系统 exists 是 I/O 操作；缺失路径越多，重复 microtask 越多。Android 外部存储和 Windows 机械盘/网络盘下会更明显。
- **impact**：列表滚动时 I/O 抖动；缺图歌曲多时缩略图加载延迟和 CPU wakeup 增多。
- **recommendation**：增加 bounded negative cache（例如 `Map<String, DateTime> missingPaths`，TTL 30-120 秒或容量 5000）；`markAsExisting()` 时移除 negative；`remove/clearAll/invalidate` 清理两类缓存。也可把 `filePathExistsProvider` 扩展为三态：unknown/existing/missing，减少 build 中反复调 notifier。
- **risk**：中。negative cache 可能导致用户手动复制封面后短时间不显示，需要 TTL 或显式 invalidate 处理。
- **immediate?**：建议近期处理，尤其下载库/歌单大列表场景。
- **category**：文件 I/O / rebuild / 内存缓存策略
- **steps**：
  1. 添加缺失路径缓存和 TTL。
  2. `getFirstExisting()` 对 all-known-missing 直接返回 null，不再安排 microtask。
  3. 下载完成、同步本地文件、删除文件时更新/清理缓存。
  4. 用缺 cover 的 500 条下载记录滚动测试。
- **预期收益**：中
- **是真实高优先级问题还是理论可优化但收益有限**：真实问题，收益取决于缺图/路径失效比例。

### P2-06. 下载管理页一次性构建全部非下载中任务

- **等级**：中
- **标题**：下载任务分组使用 `ListView(children)` 和 spread map，任务堆积时内存峰值高
- **影响模块**：下载管理页
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/settings/download_manager_page.dart`
- **关键代码位置**：
  - `download_manager_page.dart:100-150` `tasksAsync.when` 后按状态分组
  - `download_manager_page.dart:122-148` `ListView(children: [...pending.map, ...paused.map, ...])`
  - `download_manager_page.dart:175-185` 只有 downloading 区域使用 builder
- **触发场景**：批量下载歌单后 pending/paused/failed/completed 任务很多，打开下载管理页。
- **影响范围**：下载任务页 UI 构建、`trackByIdProvider(task.trackId)` provider 数量、内存。
- **问题描述**：非 downloading 分组通过 `...tasks.map((task) => _DownloadTaskTile(task: task))` 一次性创建所有 tile。每个 tile 又 watch `trackByIdProvider` 和 `downloadTaskProgressProvider`，大量任务会同时创建大量 provider 订阅。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：一次性 widget 构建 + 每项 FutureProvider 查询 Track，任务数越多越明显；completed/failed 清理前可能堆积。
- **impact**：打开下载管理页卡顿、内存上升、数据库并发查询增多。
- **recommendation**：将任务按 header + item flatten，使用单个 `ListView.builder`；或者分组使用 sliver builder。对 `trackByIdProvider` 可考虑批量预取任务对应 track 标题，避免每 tile 单独 FutureProvider。
- **risk**：低到中。UI 结构调整但业务简单。
- **immediate?**：建议近期处理。
- **category**：列表渲染 / provider 数量 / Isar 查询
- **steps**：
  1. 构建 `_DownloadListRow.header/item/slot` 扁平列表。
  2. 用 `ListView.builder` 渲染所有行。
  3. 任务超过 500 时验证打开速度和滚动。
- **预期收益**：中
- **是真实高优先级问题还是理论可优化但收益有限**：真实问题，但只有任务堆积时触发。

### P2-07. 本地下载分类详情扫描仍在主 isolate 执行

- **等级**：中
- **标题**：分类列表扫描用了 isolate，但分类详情扫描没有 isolate
- **影响模块**：已下载分类详情页、本地文件扫描
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/providers/download/download_providers.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/providers/download/download_scanner.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/library/downloaded_category_page.dart`
- **关键代码位置**：
  - `download_providers.dart:251-258` `downloadedCategoriesProvider` 使用 `Isolate.run()`
  - `download_providers.dart:260-263` `downloadedCategoryTracksProvider` 直接 `DownloadScanner.scanFolderForTracks(folderPath)`
  - `download_scanner.dart:227-330` 扫描目录、读取 metadata、jsonDecode、排序
  - `downloaded_category_page.dart:163-231` 页面直接 watch 该 FutureProvider
- **触发场景**：打开包含大量视频文件夹 / 多 P 文件 / metadata 的下载分类详情页。
- **影响范围**：已下载详情页首屏、刷新、删除后 invalidate。
- **问题描述**：分类列表已经意识到文件扫描需要 isolate，但进入某个分类后 `scanFolderForTracks()` 仍在主 isolate 中执行，包含目录遍历、文件 exists/read、JSON decode 和排序。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：文件系统和 JSON 解析在 UI isolate 上执行，会阻塞帧调度；扫描结果大时还会产生明显内存分配。
- **impact**：大下载目录打开详情页时 UI 卡顿。Windows 大目录和 Android 外部存储都可能触发。
- **recommendation**：仿照 `scanCategoriesInIsolate` 增加 `scanFolderTracksInIsolate(folderPath)` 顶层函数，并在 `downloadedCategoryTracksProvider` 用 `Isolate.run()`。注意 `Track`/嵌入对象跨 isolate 可传递性；若有问题可先返回 DTO，再主 isolate 构造 Track。
- **risk**：中。需要确认 Isar model/Track 对象跨 isolate message 是否稳定；更稳妥是返回 plain map/DTO。
- **immediate?**：建议近期处理，尤其下载库规模较大。
- **category**：文件 I/O / UI isolate 阻塞 / JSON CPU
- **steps**：
  1. 新增详情扫描顶层 isolate 函数。
  2. 返回简单 DTO 或可传递 Track 列表。
  3. 删除/刷新后继续 invalidate provider。
  4. 用大目录打开详情页观察 frame time。
- **预期收益**：中
- **是真实高优先级问题还是理论可优化但收益有限**：真实问题，收益取决于下载分类大小。

### P2-08. 同步本地文件逐 Track 保存，可能触发大量 Isar 写入和日志

- **等级**：中
- **标题**：本地文件同步阶段逐条 `TrackRepository.save()`，大目录下写入/日志成本高
- **影响模块**：已下载页“同步本地文件”
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/services/download/download_path_sync_service.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/data/repositories/track_repository.dart`
- **关键代码位置**：
  - `download_path_sync_service.dart:90-148` 对 `trackPathsMap` 每个 Track 逐个 `getById()` + `save()`
  - `download_path_sync_service.dart:151-160` 清理不匹配路径时逐个 `save()`
  - `track_repository.dart:84-93` 每次 save 带详细日志/StackTrace
- **触发场景**：用户在已下载页执行本地同步，目录中有大量文件，或 DB 中有大量旧下载路径需要清理。
- **影响范围**：同步对话框期间 UI responsiveness、Isar 写事务数量、日志输出。
- **问题描述**：同步服务分两阶段逐个 Track 查询和保存，每个保存单独事务。配合 P1-04 的 `TrackRepository.save()` 日志，批量同步时会产生大量事务和日志。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：大量小事务比批量 `putAll` 更慢；每个事务可能触发 Isar watch；每次 save 都构造日志字符串和调用栈。
- **impact**：同步大目录耗时长；可能让页面/数据库监听多次刷新。
- **recommendation**：收集 `toUpdate` 后使用仓库批量保存（`saveAll` 或专用 `updateDownloadPathsBatch`），并减少 save 日志。清理阶段同样批量 putAll。进度回调可按文件夹扫描进度保留，不必每条 DB 写入后更新。
- **risk**：中。需要确保多歌单 path 合并逻辑不变。
- **immediate?**：建议与 P1-04 一并处理。
- **category**：Isar 写入 / I/O / 日志 CPU
- **steps**：
  1. 将同步阶段分为“扫描收集”和“一次批量写入”。
  2. 对清理路径也批量保存。
  3. 同步后 invalidate 下载分类和 FileExistsCache。
- **预期收益**：中
- **是真实高优先级问题还是理论可优化但收益有限**：真实问题，但只在用户主动同步时触发。

### P2-09. 歌词展示每秒 position 更新都会重建整个歌词 Stack

- **等级**：中
- **标题**：同步歌词组件监听 position，行未变化也会 rebuild
- **影响模块**：播放器页歌词、右侧详情歌词、桌面歌词同步
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/widgets/lyrics_display.dart`
- **关键代码位置**：
  - `lyrics_display.dart:258-267` `_buildSyncedLyrics()` watch `position` 并计算当前行
  - `lyrics_display.dart:277-283` 只在行变化时滚动，但 build 已经发生
  - `lyrics_display.dart:318-345` `ScrollablePositionedList.builder` 每次 build 重新创建外层树
- **触发场景**：显示同步歌词时播放歌曲，尤其歌词行间隔较长（几秒内当前行不变）。
- **影响范围**：歌词页/详情页；低端设备或歌词很长时更明显。
- **问题描述**：组件通过 `ref.watch(position)` 获取播放位置，因此每次 position 更新都会 rebuild `_buildSyncedLyrics()` 的外层 Stack/LayoutBuilder/NotificationListener，即使当前歌词行没有变化。虽然滚动只在行变化时触发，但 rebuild 仍发生。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：position 是高频状态；LRC 当前行通常每 2-5 秒才变化，绝大多数 position 更新不需要 UI 重建。当前实现每次都做行索引查找和 widget 构建。
- **impact**：歌词界面播放时 CPU 占用增加；若右侧详情和全屏歌词同时存在，会重复计算。
- **recommendation**：增加 `currentLyricsLineIndexProvider`，在 provider 层根据 position + parsedLyrics + offset 输出行索引，并用 `select`/相等性保证只有行变化时通知 UI。或者在 widget 中用 `ref.listen(positionProvider)` 更新本地 `_currentLineIndex`，只有行变化时 `setState()`。
- **risk**：中。需确保 seek、offset 调整、歌词切换、用户手动滚动恢复逻辑不退化。
- **immediate?**：可排在 P1/P2 前几项之后。
- **category**：rebuild / CPU
- **steps**：
  1. 抽出当前歌词行索引计算。
  2. UI 只监听 lineIndex，不直接 watch position。
  3. seek/offset/歌词切换时强制重算并滚动。
- **预期收益**：中
- **是真实高优先级问题还是理论可优化但收益有限**：真实优化，收益中等。

### P2-10. `NetworkImageCacheService.setMaxCacheSizeMB()` 直接丢弃 CacheManager 引用，旧实例未显式 dispose

- **等级**：中
- **标题**：图片缓存大小变更时旧 `CacheManager` 可能短期持有资源
- **影响模块**：网络图片缓存、设置页缓存大小调整
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/core/services/network_image_cache_service.dart`
- **关键代码位置**：
  - `network_image_cache_service.dart:42` static `_cacheManager`
  - `network_image_cache_service.dart:84-89` `setMaxCacheSizeMB()` 将 `_cacheManager = null`
  - `network_image_cache_service.dart:94-106` 下次访问创建新 `CacheManager`
- **触发场景**：用户在设置页调整图片缓存大小，随后继续加载图片。
- **影响范围**：缓存数据库连接、文件服务、内存缓存；通常只短期影响。
- **问题描述**：缓存大小变更时只将静态引用置空，没有显式释放旧 `CacheManager`。旧实例可能仍被现有 `CachedNetworkImage` 或未完成请求持有，直到 GC；若频繁调整设置，可能同时存在多个 manager 实例。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：旧 manager 的内存 cache、repository、未完成请求可能继续存活；新 manager 创建后会重新打开缓存 repository。
- **impact**：一般较小，只在设置变更时触发；不是播放/滚动热路径。
- **recommendation**：如果 `flutter_cache_manager` 版本支持 `dispose()`，在置空前显式释放旧 manager；否则限制设置变更频率并在文档中接受短期 GC。也可避免每次 value 变化即时创建新 manager，等用户确认后应用。
- **risk**：低到中。需确认 CacheManager dispose API 与当前版本兼容。
- **immediate?**：否。
- **category**：内存资源生命周期
- **steps**：
  1. 检查当前 `flutter_cache_manager` API。
  2. 在 `setMaxCacheSizeMB` 中安全 dispose 旧 manager。
  3. 设置页滑块如连续触发，考虑 debounce/确认后应用。
- **预期收益**：低到中
- **是真实高优先级问题还是理论可优化但收益有限**：理论可优化，收益有限。

### P2-11. `AppLogger` 在 release/profile 仍始终 `debugPrint` info+ 日志

- **等级**：中
- **标题**：日志输出策略可能影响长时间播放/下载的 I/O 和 CPU
- **影响模块**：全局日志、播放、下载、网络源请求
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/core/logger.dart`
- **关键代码位置**：
  - `logger.dart:55` release/profile 最小等级为 info
  - `logger.dart:129-136` 所有满足等级日志进入缓冲和 stream
  - `logger.dart:149-156` 始终 `debugPrint(fullMessage)`
- **触发场景**：release/profile 长时间播放、下载、自动刷新、网络错误重试，产生 info/warning/error 日志。
- **影响范围**：所有平台；Windows 控制台和 Android logcat 行为不同。
- **问题描述**：即使不是 debug 模式，info+ 日志仍会进入缓冲、stream，并调用 `debugPrint`。项目中 `logInfo/logWarning` 分布在播放、下载、刷新等路径，若某些路径频繁输出，会带来额外字符串和 I/O 开销。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：日志对象最多保留 500 条，内存可控；但输出和 stream 分发是同步运行路径上的额外工作。`debugPrint` 在 Flutter 中有节流，但仍会排队字符串输出。
- **impact**：多数场景较低；异常/重试/批量下载时日志量会明显。
- **recommendation**：release 默认最小等级调到 warning，或增加用户/开发者开关控制 info 日志；复杂日志使用 lazy message 避免被过滤前构造字符串。
- **risk**：低。可能减少用户反馈时可用日志，需要开发者选项开启详细日志。
- **immediate?**：否，但建议纳入日志策略优化。
- **category**：日志 I/O / CPU / 内存缓冲
- **steps**：
  1. 统计 release/profile 常规播放 10 分钟日志量。
  2. 将默认 release min level 改 warning 或可配置。
  3. 保留错误和用户主动导出日志能力。
- **预期收益**：中
- **是真实高优先级问题还是理论可优化但收益有限**：真实但中低优先级。

### P3-12. `TrackRepository.getByIds()` 使用 `ids.indexOf(id)`，队列恢复大列表时 O(N²)

- **等级**：低到中
- **标题**：批量按 ID 恢复顺序时存在 O(N²) 实现
- **影响模块**：队列恢复、播放歌单、批量 Track 查询
- **具体文件路径**：`C:/Users/Roxy/Visual Studio Code/FMP/lib/data/repositories/track_repository.dart`
- **关键代码位置**：`track_repository.dart:27-40`
- **触发场景**：启动恢复包含大量曲目的队列，或任何调用 `getByIds()` 且 ids 很大的路径。
- **影响范围**：启动初始化、播放大歌单、下载歌单查询。
- **问题描述**：`getAll(ids)` 返回与输入 ids 对齐的列表后，又 for 每个 id 调用 `ids.indexOf(id)` 获取索引。`indexOf` 在循环内是 O(N)，整体 O(N²)。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：大队列（数千/一万）启动恢复时 CPU 开销不必要；日志还会输出完整 ids（见 P1-04 相关日志策略）。
- **impact**：大队列启动或批量操作变慢。若 ids 含重复，当前逻辑可能也无法保留所有重复项。
- **recommendation**：直接按 `tracks` 下标迭代：`for (var i = 0; i < ids.length; i++) { final track = tracks[i]; if (track != null) result.add(track); }`。避免打印完整 ids。
- **risk**：低。
- **immediate?**：可顺手修复。
- **category**：CPU / 启动性能
- **steps**：
  1. 替换 `ids.indexOf(id)` 循环。
  2. 大队列启动恢复测试。
- **预期收益**：中（大队列）/低（普通队列）
- **是真实高优先级问题还是理论可优化但收益有限**：真实问题，但只在大列表下收益明显。

### P3-13. 播放队列持久化每 10 秒无条件写 Isar

- **等级**：低到中
- **标题**：暂停/无队列/位置未变化时仍周期保存播放位置
- **影响模块**：队列持久化、Isar 写入、磁盘 I/O
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/services/audio/queue_manager.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/services/audio/queue_persistence_manager.dart`
- **关键代码位置**：
  - `queue_manager.dart:801-805` 10 秒 `Timer.periodic`
  - `queue_manager.dart:836-842` `_savePosition()` 无条件调用 `savePositionNow()`
  - `queue_persistence_manager.dart:92-102` 每次保存写 queue
- **触发场景**：应用打开但未播放、暂停很久、position 没变化。
- **影响范围**：后台/空闲时磁盘写入；移动端电池。
- **问题描述**：位置保存定时器在 `QueueManager.initialize()` 后一直运行，没有检查是否正在播放、队列是否为空、position/currentIndex 是否变化。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：每 10 秒写一次 Isar，即使数据不变；长时间后台或暂停会产生无意义 I/O。若有 watch PlayQueue 的 UI/工具页，可能触发刷新。
- **impact**：单次很小，长时间运行累积；移动端更敏感。
- **recommendation**：记录上次保存的 `(currentIndex, positionMs)`，只有变化超过阈值时保存；或由 `AudioController` 在播放中更新/保存，暂停/stop/app lifecycle 时 flush。保持 seek 后 `savePositionNow()` 立即保存。
- **risk**：中。需确保崩溃/关闭时位置不丢失。
- **immediate?**：否，但适合电池/后台优化阶段。
- **category**：I/O / 电池 / Isar 写入
- **steps**：
  1. 增加 dirty check 和 position delta 阈值。
  2. 暂停/停止/app lifecycle 时保存一次。
  3. 回归重启恢复位置。
- **预期收益**：低到中
- **是真实高优先级问题还是理论可优化但收益有限**：真实但收益有限。

### P3-14. 搜索结果混排 getter 每次 build 都重新生成列表

- **等级**：低到中
- **标题**：`mixedOnlineTracks` getter 在 UI 中多次访问会重复排序/交错
- **影响模块**：搜索页
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/providers/search_provider.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/search/search_page.dart`
- **关键代码位置**：
  - `search_provider.dart:80-100` `mixedOnlineTracks` getter
  - `search_provider.dart:102-130` `_interleaveResults()` 每次生成新 list
  - `search_page.dart:518-557` 多次访问 `state.mixedOnlineTracks`（标题 count、isNotEmpty、builder、childCount）
- **触发场景**：搜索结果很多、加载更多、切换选择模式或扩展分 P 导致搜索页 rebuild。
- **影响范围**：搜索页构建 CPU 和短期 list 分配。
- **问题描述**：`mixedOnlineTracks` 是计算型 getter，每次访问都会生成新列表；播放量排序还会复制并排序。搜索页同一 build 中多次访问该 getter，造成重复计算。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：每次 build 分配 list，并可能排序；结果数量越多越明显。
- **impact**：通常中低；搜索结果分页累积多时可见。
- **recommendation**：在 `_buildSearchResults` 中先 `final mixedTracks = state.mixedOnlineTracks;` 并复用；进一步可在 `SearchState` 更新时预计算并存储 mixed list，或 memoize（基于 `onlineResults` identity + order）。
- **risk**：低。
- **immediate?**：可顺手修复。
- **category**：CPU / 短期内存分配
- **steps**：
  1. 搜索页 build 内缓存 getter 结果。
  2. 如仍有热点，再将混排结果放入 state。
- **预期收益**：低到中
- **是真实高优先级问题还是理论可优化但收益有限**：真实但收益有限。

### P3-15. `ListTile.leading` 中仍有 `Row` 的残留用法

- **等级**：低到中
- **标题**：少数页面仍违背项目 ListTile 性能经验
- **影响模块**：导入预览页、歌词源设置页
- **具体文件路径**：
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/library/import_preview_page.dart`
  - `C:/Users/Roxy/Visual Studio Code/FMP/lib/ui/pages/settings/lyrics_source_settings_page.dart`
- **关键代码位置**：
  - `import_preview_page.dart:478-514`
  - `import_preview_page.dart:700-721`
  - `import_preview_page.dart:852-873`
  - `lyrics_source_settings_page.dart:180-200`
- **触发场景**：导入预览结果很多，列表滚动；歌词源设置项很少，影响可忽略。
- **影响范围**：导入预览页滚动布局。
- **问题描述**：项目 `CLAUDE.md` 和 `refactoring_lessons.md` 明确记录 `ListTile.leading` 内放 `Row` 会导致额外布局计算和滚动卡顿。当前仍在导入预览页和歌词源设置页存在。
- **为什么会造成额外内存占用 / rebuild / CPU / I/O 开销**：`ListTile` 对 leading 有特殊约束，复杂 leading 会增加 layout pass；导入预览页还包含 `TrackThumbnail`。
- **impact**：导入预览大量结果时滚动抖动；设置页只有 3 个源，收益很低。
- **recommendation**：导入预览页改成项目推荐的扁平 `InkWell + Padding + Row` 布局；歌词源设置页可不急，除非顺手统一。
- **risk**：低到中。导入预览交互较多，需保持展开、选择、搜索结果逻辑。
- **immediate?**：导入预览建议；歌词源设置不急。
- **category**：布局性能 / UI consistency
- **steps**：
  1. 优先改 `import_preview_page.dart` 三处列表项。
  2. 保持 checkbox/选中/缩略图/展开按钮布局。
  3. 大导入列表滚动测试。
- **预期收益**：中（导入预览）/低（设置页）
- **是真实高优先级问题还是理论可优化但收益有限**：导入预览是真实中等问题；设置页是理论优化。

## 4. 高收益优化优先级

1. **拆分高频播放器状态与低频队列状态**
   - 对应问题：P1-01
   - 收益：大队列播放时降低 selector 比较、状态传播和 rebuild 风险。
   - 建议先用 DevTools 验证大队列播放 CPU，然后拆 provider。

2. **重构播放历史查询与历史页列表渲染**
   - 对应问题：P1-02、P1-03
   - 收益：历史页打开、筛选、搜索、多选和首页最近播放都会受益。
   - 建议将“首页最近播放”“历史页分页列表”“统计”拆开，不再共享 1000 条大快照。

3. **移除 Track 保存热路径的调用栈 debug 日志**
   - 对应问题：P1-04
   - 收益：批量导入、下载完成、同步本地文件、音频 URL 更新时减少 CPU 和日志 I/O。
   - 风险低，可快速落地。

4. **补齐文件存在缓存的 negative cache，并把下载详情扫描放入 isolate**
   - 对应问题：P2-05、P2-07
   - 收益：大下载库滚动、打开下载分类详情时减少 I/O 抖动和 UI isolate 阻塞。

5. **下载管理页和本地同步批量化**
   - 对应问题：P2-06、P2-08
   - 收益：任务堆积和大目录同步场景明显改善。

6. **歌词当前行索引 provider 化**
   - 对应问题：P2-09
   - 收益：显示歌词播放时减少 position 高频 rebuild。

## 5. 当前可接受 / 不建议过早优化的点

- **图片加载体系整体可接受**：未发现直接 `Image.network()` / `Image.file()`；`ImageLoadingService` 会根据尺寸优化缩略图 URL，并为网络图设置 `memCacheWidth/Height`。多数调用已传 `width`/`height` 或 `targetDisplaySize`。
- **网络图片磁盘缓存策略可接受**：有平台默认容量（Android/iOS 16MB，桌面 32MB）、定期检查、后台 isolate 扫描和清理。`CacheManager` 旧实例 dispose 属于低频设置场景，不是热路径。
- **歌词缓存可接受**：`LyricsCacheService` 有文件数上限和 5MB 总大小限制，访问时间元数据采用 2 秒 debounce，设计合理。
- **下载进度设计可接受**：Windows 下载使用 isolate，进度每 5% 发送，主线程每 1 秒 flush 到内存 provider，不写 Isar，避免了已知 PostMessage / Isar watch 问题。
- **音频后端资源管理整体可接受**：`JustAudioService` 降低 Android ExoPlayer buffer；`MediaKitAudioService` 设置 `vid=no`、限制 demuxer/cache，对 muxed 音频内存峰值是关键优化。
- **队列页局部优化已有基础**：本地队列副本、`queueVersion`、`RepaintBoundary`、`ScrollablePositionedList` 都是正确方向；主要问题是队列仍挂在高频 `PlayerState` 上。
- **少量设置页 `ListTile.leading Row` 不必急修**：歌词源设置只有少数条目，收益有限；导入预览页因结果量可能较大，建议优先处理。
- **播放位置每 10 秒保存可暂时接受**：单次 I/O 很小，且保证恢复可靠；若后续做移动端后台/电池优化，再引入 dirty check。
