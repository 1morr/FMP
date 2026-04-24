# FMP 逻辑一致性与可维护性审查报告

## 1. 审查范围

- 审查对象：`C:\Users\Roxy\Visual Studio Code\FMP` 下的 Flutter/Dart 业务代码，重点覆盖 `lib/ui`、`lib/providers`、`lib/services`、`lib/data`。
- 已阅读项目约束：根目录 `CLAUDE.md`、`.serena/memories/code_style.md`、`download_system.md`、`update_system.md`、`ui_coding_patterns.md`、`refactoring_lessons.md`。
- 重点检查：命名与旧/新逻辑共存、重复实现、Riverpod 状态模式、FutureProvider invalidation、UI 统一规则、页面层与 service/provider 职责边界。
- 未修改业务代码；本报告只记录基于真实代码的审查结论。

## 2. 总体结论

整体上，项目的主干架构是清晰且较一致的：音频层通过 `AudioController` 隔离 UI 与后端，播放上下文 `_PlaybackContext` 已替代旧的散乱状态；下载完成后的 FutureProvider invalidation 与歌单 watch-driven 状态也基本符合项目约定。审查未发现大面积“旧逻辑与新逻辑并行导致必然错误”的情况。

主要可维护性问题集中在 3 类：

1. 少量公共组件把副作用隐藏在 `build()` 中，和项目的 Riverpod/UI 规范存在张力。
2. 图片加载尺寸提示、`ListTile.leading` 布局、`ValueKey` 等 UI 统一规则仍有局部遗漏。
3. 已有抽象（如 `TrackActionHandler`）还没有完全收拢各页面重复样板；部分兼容命名或旧工具方法仍保留，增加理解成本。

建议优先处理“低风险、局部统一”的问题，不建议为了形式统一而重构音频主链路、歌单 watch 模型或下载完成刷新模型。

## 3. 发现的问题列表

### 问题 1

- 等级：中
- 标题：`TrackThumbnail` / `TrackCover` 在 `build()` 中触发文件存在性检查副作用
- 影响模块：封面显示、下载文件存在性缓存、所有歌曲列表/播放页封面
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\track_thumbnail.dart`，`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\download\file_exists_cache.dart`
- 关键代码位置：`track_thumbnail.dart:58-70`、`track_thumbnail.dart:180-191`、`file_exists_cache.dart:43-51`、`file_exists_cache.dart:141-166`
- 问题描述：`TrackThumbnail.build()` 和 `TrackCover.build()` 在 `localCoverPath == null` 时直接调用 `ref.read(fileExistsCacheProvider.notifier).getFirstExisting(coverPaths)`；`getFirstExisting()` 会安排异步文件检查并最终更新 provider state。
- 为什么这是问题：项目规范明确要求避免在 build 中调用 notifier 方法或修改 provider/state。虽然当前实现用 `Future.microtask()` 延迟，避免了同步 build 期写 state，但副作用仍隐藏在渲染路径中；同时 `FileExistsCache` 只缓存存在路径，不缓存不存在路径，路径不存在时在后续 rebuild 中仍可能重复安排检查。
- 可能造成的影响：大量封面列表 rebuild 时更难推理 IO 检查频率；新增调用者容易误以为 build 中调用 notifier 是通用可接受模式；不存在的本地封面路径会反复进入 pending/检查流程。
- 推荐修改方向：把文件检查触发点从通用封面组件中下沉到页面进入/数据加载后预加载，或提供明确的 family provider / preload API；保留 `TrackThumbnail` 只负责消费缓存状态。短期也可为不存在路径增加有界 negative cache，减少重复检查。
- 修改风险：中。封面显示涉及面广，需验证已下载页、歌单详情、首页、播放器页。
- 是否值得立即处理：建议近期处理，尤其是列表页封面较多时。
- 分类：Riverpod 使用模式 / UI 副作用 / 文件缓存一致性。
- 如果要改建议拆成几步执行：1）为列表页统一预加载 cover paths；2）让 `TrackThumbnail` 不再主动触发检查；3）补充或手测下载完成后封面即时显示；4）再考虑 negative cache。

### 问题 2

- 等级：中
- 标题：部分 `ImageLoadingService.loadImage()` 调用缺少尺寸提示，和缩略图优化规则不一致
- 影响模块：首页歌单封面、已下载分类封面、封面 URL 预览、`TrackCover` 默认路径
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\home\home_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_category_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\widgets\cover_picker_dialog.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\track_thumbnail.dart`
- 关键代码位置：`home_page.dart:1218-1226`、`downloaded_category_page.dart:397-402`、`downloaded_category_page.dart:419-424`、`downloaded_page.dart:311-316`、`cover_picker_dialog.dart:262-266`、`track_thumbnail.dart:208-215`
- 问题描述：上述调用没有传 `width` / `height` / `targetDisplaySize`。项目文档要求调用 `loadImage()` 时传尺寸参数，避免 YouTube 缩略图默认选择不稳定的 `maxresdefault.jpg`。
- 为什么这是问题：首页歌单封面的 `PlaylistCoverData.networkUrl` 可能来自歌曲封面；封面选择 URL 预览也可能是平台缩略图。缺少尺寸会绕开项目既定的可靠尺寸选择策略。
- 可能造成的影响：YouTube 封面偶发显示 placeholder；不同页面同一封面 URL 表现不一致；后续维护者难以判断哪些调用需要尺寸。
- 推荐修改方向：为固定尺寸卡片传入实际尺寸或 `targetDisplaySize`；`TrackCover` 在非高清模式下也应给出合理默认 target（例如按组件常用显示尺寸设定），只在 `highResolution` 时使用更大 target。
- 修改风险：低。只影响图片 URL 候选和布局尺寸提示。
- 是否值得立即处理：值得立即处理，属于局部一致性修复。
- 分类：UI 一致性 / 图片加载策略。
- 如果要改建议拆成几步执行：1）修复明确固定大小的调用；2）调整 `TrackCover` 默认 target；3）手测 YouTube 歌单封面与封面选择预览。

### 问题 3

- 等级：低
- 标题：仍有 `Row` 放在 `ListTile.leading` 中，违反项目列表性能/布局约定
- 影响模块：歌词源设置页、导入预览页
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\settings\lyrics_source_settings_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\import_preview_page.dart`
- 关键代码位置：`lyrics_source_settings_page.dart:180-200`、`import_preview_page.dart:478-514`、`import_preview_page.dart:700-721`、`import_preview_page.dart:852-872`
- 问题描述：这些 `ListTile` 的 `leading` 使用 `Row(mainAxisSize: MainAxisSize.min, ...)` 组合拖拽图标、选择图标和缩略图。
- 为什么这是问题：项目记忆中已记录 `ListTile.leading` 内放复杂 `Row` 容易造成布局抖动/滚动卡顿，并建议使用扁平 `InkWell + Padding + Row`。当前代码与该规范不一致。
- 可能造成的影响：长导入预览列表中布局成本增加；相似列表项写法继续分化；后续页面复制该模式。
- 推荐修改方向：对导入预览这类可能较长的列表优先改为扁平自定义行；歌词源设置页数据量很小，可作为低优先级统一项处理。
- 修改风险：低到中。主要是 UI 布局回归风险，需要目测对齐和点击区域。
- 是否值得立即处理：导入预览页建议处理；歌词源设置页可顺手统一。
- 分类：UI 一致性 / 列表布局性能。
- 如果要改建议拆成几步执行：1）先改 `_AlternativeTrackTile` 等导入预览子项；2）复用一个私有行组件；3）最后处理歌词源设置页。

### 问题 4

- 等级：低
- 标题：列表/网格局部缺少 `ValueKey`，和项目 diff 规范不完全一致
- 影响模块：封面选择网格、导入预览展开结果
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\widgets\cover_picker_dialog.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\import_preview_page.dart`
- 关键代码位置：`cover_picker_dialog.dart:178-199`、`import_preview_page.dart:648-652`、`import_preview_page.dart:812-817`
- 问题描述：`GridView.builder` 中 `_CoverGridItem` 未传 key；导入预览展开的搜索结果 `map()` 也未给 `_AlternativeTrackTile` 提供 key。
- 为什么这是问题：项目规范要求列表/网格项添加 `ValueKey(item.id)` 或稳定业务 key。当前主列表大多已遵守，但这些局部动态项仍遗漏。
- 可能造成的影响：筛选、展开、替换搜索结果时 Flutter diff 依赖位置而非业务身份；选中态/动画/图片缓存表现更难预测。
- 推荐修改方向：封面网格使用 `ValueKey(track.thumbnailUrl)`；导入预览搜索结果使用 `ValueKey('${track.sourceType.name}:${track.sourceId}:${track.pageNum ?? track.cid ?? 0}')` 或 `track.uniqueKey`。
- 修改风险：低。
- 是否值得立即处理：值得顺手处理。
- 分类：UI 一致性 / 列表 diff 稳定性。
- 如果要改建议拆成几步执行：1）给封面网格加 key；2）给导入预览展开项加 key；3）快速手测展开/选择替代曲目。

### 问题 5

- 等级：低
- 标题：搜索历史同时存在 FutureProvider 和 StateNotifier 两套入口，实际只使用后者
- 影响模块：搜索页、搜索历史状态
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\search_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\search\search_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\search\search_service.dart`
- 关键代码位置：`search_provider.dart:601-643`、`search_page.dart:787-790`、`search_service.dart:121-123`、`search_service.dart:224-260`
- 问题描述：`searchHistoryProvider` 是快照型 `FutureProvider`，但搜索页实际 watch 的是 `searchHistoryManagerProvider`；搜索完成后通过 `loadHistory()` 手动刷新 StateNotifier。`searchHistoryProvider` 未见实际消费，也不会在历史变化后被 invalidate。
- 为什么这是问题：同一数据源有两套状态入口，容易让后续代码选错 provider；FutureProvider 入口若被新页面使用，会出现新增/删除后不刷新的问题。
- 可能造成的影响：搜索历史 UI 行为分裂；后续维护者需要同时理解两套刷新方式。
- 推荐修改方向：删除未使用的 `searchHistoryProvider`，或统一迁移为 watch-driven/StateNotifier 单入口；如果保留 FutureProvider，所有写操作后必须明确 invalidate。
- 修改风险：低。先确认全库无引用后删除即可。
- 是否值得立即处理：值得立即处理。
- 分类：Riverpod 状态源重复 / FutureProvider invalidation。
- 如果要改建议拆成几步执行：1）全局确认无引用；2）删除 `searchHistoryProvider`；3）保留 `searchHistoryManagerProvider` 作为唯一入口或改名强调用途。

### 问题 6

- 等级：低
- 标题：`TrackActionHandler` 已抽象通用动作，但各页面仍重复组装 adapter 与反馈回调
- 影响模块：首页、探索页、搜索页、歌单详情、已下载详情、播放历史
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\handlers\track_action_handler.dart` 及多个页面文件
- 关键代码位置：`track_action_handler.dart:95-144`、`home_page.dart:974-1018`、`explore_page.dart:398-442`、`search_page.dart:926-969`、`playlist_detail_page.dart:1623-1666`、`downloaded_category_page.dart:968-1002`、`play_history_page.dart:19-52`
- 问题描述：项目已有 `TrackActionHandler` 统一处理 play/play_next/add_to_queue/add_to_playlist/matchLyrics/add_to_remote，但每个页面仍重复创建 `AudioControllerTrackActionAdapter` 和 `CallbackTrackActionFeedbackSink`，并重复写 toast 与登录提示回调。
- 为什么这是问题：抽象只收拢了一半，页面层仍有大量样板；新增菜单动作或修改反馈文案时容易漏改某个页面。
- 可能造成的影响：相同菜单动作跨页面反馈不一致；页面代码变长，业务差异被样板淹没。
- 推荐修改方向：增加一个 UI helper/factory，例如 `handleStandardTrackAction(context, ref, action, track, ...)`，保留各页面只传差异化回调（下载、删除、远程删除、多 P 批量动作）。不要把 destructive 或多 P 特例强行塞进通用 handler。
- 修改风险：中。动作入口较多，需逐页验证菜单行为。
- 是否值得立即处理：建议在下一次菜单动作相关修改时处理。
- 分类：重复实现 / 页面层职责简化。
- 如果要改建议拆成几步执行：1）先抽出不含页面特殊逻辑的 helper；2）迁移 Explore/Home/Search 三个相似页面；3）再迁移 Playlist/Downloaded/History；4）保留特殊动作在页面本地。

### 问题 7

- 等级：低
- 标题：本地音频路径检查逻辑存在扩展方法与播放 delegate 双实现
- 影响模块：音频预取、本地下载播放路径验证
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\core\extensions\track_extensions.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_stream_manager.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart`
- 关键代码位置：`track_extensions.dart:16-29`、`track_extensions.dart:35-47`、`audio_stream_manager.dart:182-192`、`audio_stream_delegate.dart:112-125`
- 问题描述：`TrackExtensions.localAudioPath` / `validDownloadPaths` 使用同步 `File.existsSync()` 判断本地文件；`AudioStreamDelegate._inspectLocalFiles()` 也执行类似检查，并负责清理无效路径。`AudioStreamManager.prefetchTrack()` 还先用 `track.hasLocalAudio` 做一次同步预检查。
- 为什么这是问题：本地路径有效性的权威逻辑不唯一；扩展方法注释提到“文件不存在会自动清空”，但扩展方法本身无法清 DB，真正清理发生在 delegate。语义容易误导。
- 可能造成的影响：后续调用者可能在 UI 或非播放路径使用同步 IO；无效下载路径清理策略被重复实现并产生差异。
- 推荐修改方向：让播放链路统一通过 `AudioStreamDelegate` 判断和修复本地路径；减少或重命名扩展方法中容易误导的同步检查；`prefetchTrack()` 可直接依赖 delegate 的选择逻辑，或只检查已知的缓存状态。
- 修改风险：低到中。需确认预取不会为已下载歌曲触发网络请求。
- 是否值得立即处理：不紧急，但适合作为音频路径维护的清理项。
- 分类：重复实现 / 旧工具方法保留。
- 如果要改建议拆成几步执行：1）统计 `localAudioPath` / `validDownloadPaths` 引用；2）移除或限制未使用扩展；3）调整 `prefetchTrack()`；4）验证本地下载歌曲播放与无效路径修复。

### 问题 8

- 等级：低
- 标题：`currentTrack` 兼容命名与 `playingTrack` / `queueTrack` 新语义并存，增加理解成本
- 影响模块：音频状态选择器、桌面托盘/SMTC、播放器 UI
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\player_state.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\windows_desktop_provider.dart`
- 关键代码位置：`player_state.dart:20-25`、`player_state.dart:112-113`、`audio_provider.dart:2649-2651`、`windows_desktop_provider.dart:17-26`
- 问题描述：`PlayerState` 已明确区分实际播放的 `playingTrack` 与队列位置的 `queueTrack`，但仍保留 `currentTrack => playingTrack` 的兼容 getter；`currentTrackProvider` 也继续暴露该兼容命名。
- 为什么这是问题：新旧命名共同存在时，新维护者容易把 `currentTrack` 理解为队列当前项，而不是实际播放项；项目中临时播放、detached、radio return 都依赖二者语义差异。
- 可能造成的影响：新增 UI 可能使用错误字段判断播放态或队列态；托盘/标题栏等集成代码继续传播旧命名。
- 推荐修改方向：短期保留兼容 getter，但内部新代码优先使用 `playingTrackProvider` / `queueTrackProvider` 或显式字段；在文档中标记 `currentTrack` 是兼容别名。长期可逐步把 provider 命名迁移到 `playingTrackProvider`。
- 修改风险：中。字段影响面较广，不建议一次性大规模替换。
- 是否值得立即处理：不建议立即大改；建议作为渐进式命名清理。
- 分类：命名一致性 / 新旧语义共存。
- 如果要改建议拆成几步执行：1）新增显式 selector provider；2）新代码禁用 `currentTrack`；3）逐步替换非关键 UI；4）最后评估是否保留兼容 getter。

## 4. 当前可接受 / 建议保持不动的设计

- 音频三层结构和 UI 只调用 `AudioController` 的规则保持良好，未见 UI 直接调用 `audioServiceProvider`。
- `_PlaybackContext`、`PlayMode`、请求 ID 和 `_isSuperseded()` 思路符合项目近期重构经验，建议保持，不要重新拆回多个布尔字段。
- `QueueManager` 负责 shuffle / upcomingTracks / loop，UI 使用 `upcomingTracks` 的方向是正确的。
- `PlaylistListNotifier` 使用 Isar `watchAll()`，同时保留 `allPlaylistsProvider` 作为快照型读取并在注释中说明需要 invalidate，这是可接受的混合模型。
- 下载完成事件在 `downloadServiceProvider` 中批量 debounce 刷新 `downloadedCategoriesProvider` / `downloadedCategoryTracksProvider`，并对歌单详情使用静默 `refreshTracks()`，符合避免闪烁的设计目标。
- 未发现 `Image.network()` / `Image.file()` 直接散落在 UI 层；统一图片服务的大方向值得保持。
- 播放页进度 Slider 使用 `onChangeEnd` 才 seek，符合项目“拖动时不 seek”的规则。

## 5. 可立即落地的统一性修复建议

1. 给所有 `ImageLoadingService.loadImage()` 缺尺寸调用补齐 `width` / `height` / `targetDisplaySize`，优先修复首页歌单封面和封面选择预览。
2. 删除或合并未使用的 `searchHistoryProvider`，保留一个搜索历史状态入口。
3. 给 `CoverPickerDialog` 网格项和 `ImportPreviewPage` 展开项添加稳定 `ValueKey`。
4. 把导入预览页中 `ListTile.leading: Row(...)` 改为扁平自定义行，减少后续复制该反模式的概率。
5. 抽一个轻量 `handleStandardTrackAction(...)` helper，优先迁移 Home / Explore / Search 三个页面，减少相同菜单动作样板。
6. 为 `TrackThumbnail` 的本地封面检查设计明确预加载入口或 negative cache，再逐步移除 build 中的 notifier 调用。
7. 在音频状态 selector 中新增显式 `playingTrackProvider` / `queueTrackProvider`，后续代码避免继续扩大 `currentTrack` 兼容别名的使用范围。
