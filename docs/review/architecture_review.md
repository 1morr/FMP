# 架构与目录结构审查报告

## 1. 审查范围

- 审查项目：FMP Flutter 音乐播放器，目标平台 Android / Windows。
- 审查依据：`C:\Users\Roxy\Visual Studio Code\FMP\CLAUDE.md`、`.serena\memories\*.md` 中与架构、UI、下载、重构相关的约定，以及真实代码。
- 重点范围：音频三层架构、UI 到 `AudioController` 的调用约束、`AudioController` / `AudioService` / `QueueManager` / Source / Repository / Provider / UI 的边界，跨层调用、业务逻辑归属、目录职责。
- 未做事项：未修改业务代码，未运行重构或测试；本报告仅给出系统级架构审查结论。

## 2. 总体结论

当前项目的核心音频架构方向是清晰的：UI 基本遵守“只调用 `AudioController`，不直接调用 `AudioService`”的规则；`FmpAudioService` 抽象隔离了 just_audio 与 media_kit；`QueueManager` 承担队列与持久化协调；Source 层、Repository 层、Provider 层大体能对应 CLAUDE.md 中的分层说明。

主要架构问题不在核心播放链路是否混乱，而在“若干大型页面和服务承担过多编排职责”：远程歌单同步、下载路径配置、搜索分 P / 多选操作、备份导入等流程分散在 UI 或服务里，导致边界不够统一。另一个值得关注的点是 `RadioController` 与 `AudioController` 因共享播放器和媒体控制权形成双向协调，这符合当前产品设计，但长期应提炼为明确的共享播放器/媒体控制协调层。

没有发现需要立即阻断开发的 Critical 架构问题；建议把以下 Medium / High 项列入后续分阶段重构，而不是一次性大改。

## 3. 发现的问题列表

### 问题 1

- 等级：High
- 标题：RadioController 与 AudioController 存在双向协调和共享播放器所有权耦合
- 影响模块：电台播放、歌曲播放、通知栏 / Windows SMTC、共享 `AudioService`
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\radio\radio_controller.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
- 关键代码位置：`radio_controller.dart:222-227` 持有 `Ref`、`RadioRepository`、`RadioSource`、`FmpAudioService`；`radio_controller.dart:383-405` 直接读 `audioControllerProvider` 并设置回调；`radio_controller.dart:579-592` 调用 `AudioController.returnFromRadio()`；`radio_controller.dart:1117-1120` 直接注入 `audioServiceProvider`；`audio_provider.dart:1723-1724` 通过 `onPlaybackStarting` 停止电台。
- 问题描述：电台控制器既是业务控制器，又直接持有共享播放器、媒体控制回调、Provider Ref，并反向修改 `AudioController` 的回调字段。歌曲播放和电台播放通过互相读取/回调实现互斥与恢复。
- 为什么这是问题：当前设计能工作，但两个控制器之间的所有权边界不是接口化的；后续调整后台播放、通知栏、桌面 SMTC、恢复逻辑时，很容易在两个控制器之间形成隐式时序依赖。
- 可能造成的影响：电台和歌曲快速切换、通知栏控制权恢复、退出/销毁顺序变动时容易出现回调残留、状态不同步或媒体控制被错误接管。
- 推荐修改方向：不要直接合并到 `AudioController`；建议提炼一个小型 `SharedPlaybackCoordinator` / `PlaybackOwnershipCoordinator`，只负责“音乐/电台谁拥有共享播放器、如何暂停对方、如何恢复媒体控制”。`RadioController` 和 `AudioController` 只依赖该接口。
- 修改风险：中高。共享播放器、通知栏、SMTC、恢复位置都在链路上，必须小步迁移。
- 是否值得立即处理：不建议立即大改；若近期要继续扩展电台或后台媒体控制，则应先处理。
- 分类：建议列入后续重构计划
- 如果要改建议拆成几步执行：1) 先抽出只读所有权状态和互斥回调接口；2) 把 `onPlaybackStarting` / `isRadioPlaying` 替换成协调器；3) 再迁移媒体控制权恢复；4) 最后补电台/歌曲切换回归测试。

### 问题 2

- 等级：Medium
- 标题：Source 实例所有权未完全收敛到 SourceManager / Provider
- 影响模块：YouTube Mix、排行榜缓存、导入服务、歌单详情加载
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\source_provider.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\playlist_provider.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\import_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\popular_provider.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\cache\ranking_cache_service.dart`
- 关键代码位置：`source_provider.dart:10-18` 注册统一 Source；`source_provider.dart:151-154` SourceManager Provider 负责 dispose；`audio_provider.dart:815-823`、`audio_provider.dart:1503-1507` 临时创建 `YouTubeSource`；`playlist_provider.dart:347-359` 创建 `YouTubeSource`；`import_service.dart:350-352` 创建 `YouTubeSource`；`popular_provider.dart:77-83`、`popular_provider.dart:181-184` 创建 Source；`ranking_cache_service.dart:57-61` 自建 Source。
- 问题描述：项目已经有统一 `SourceManager`，但若干业务路径仍直接 `new` Source。部分调用有手动 dispose，部分依赖服务生命周期，所有权规则不一致。
- 为什么这是问题：Source 通常封装 Dio / YoutubeExplode / Cookie / 限流处理。绕过统一 Provider 会让配置、生命周期、测试替身和未来认证策略分散。
- 可能造成的影响：后续给 Source 增加全局拦截器、指标、缓存、认证策略时，容易漏掉 Mix、排行榜或导入路径；也会增加资源清理检查成本。
- 推荐修改方向：保留 `SourceManager` 为数据源入口；Mix 相关能力如果只在 `YouTubeSource` 上存在，可通过 `youtubeSourceProvider` 或一个 `YouTubeMixService` 注入，而不是在调用点新建。
- 修改风险：中。排行榜和 Mix 是用户可见路径，应先保证现有请求行为不变。
- 是否值得立即处理：建议在下一次 Source / Mix / 排行榜相关改动时顺手处理。
- 分类：建议列入后续重构计划
- 如果要改建议拆成几步执行：1) 给 `RankingCacheService`、`ImportService`、`PlaylistDetailNotifier` 注入 Source；2) 保持旧构造函数测试兼容；3) 移除直接 `YouTubeSource()`；4) 检查 dispose 所有权只在 Provider / 服务拥有者处发生。

### 问题 3

- 等级：Medium
- 标题：部分页面承担远程歌单、下载、分 P 编排等业务流程，UI 层偏厚
- 影响模块：歌单详情、搜索页、下载页、设置页
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\playlist_detail_page.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\search\search_page.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_category_page.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\settings\settings_page.dart`
- 关键代码位置：`playlist_detail_page.dart:640-720` 批量从 Bilibili / YouTube / Netease 远程歌单移除并刷新本地；`playlist_detail_page.dart:1688-1724` 单曲远程移除；`playlist_detail_page.dart:1102-1155` 下载歌单前置检查与入队；`playlist_detail_page.dart:1567-1588` 单曲下载菜单动作；`search_page.dart:794-900` 分 P 加载、展开、加入下一首/队列；`downloaded_category_page.dart:1005-1016` 删除文件后更新数据库和 Provider；`settings_page.dart:1871-1922` 备份导入导出入口分散在设置页。
- 问题描述：这些页面不仅渲染和响应交互，还直接编排多个服务、解析远程 ID、批量循环调用 API、更新本地 Provider、展示 Toast。
- 为什么这是问题：相同动作难以复用，页面变得很长，失败/回滚/刷新策略散落在 UI 中；这与项目“业务逻辑放在 Controller / Provider / Service”的趋势不完全一致。
- 可能造成的影响：多选和单选路径行为不一致；新增平台远程歌单时需要改多个 UI 文件；UI 变更容易误伤业务流程。
- 推荐修改方向：把“远程歌单增删 + 本地同步 + 刷新”提到 `RemotePlaylistActionService` 或现有 `PlaylistService` 的应用层方法；把搜索分 P 批量播放/入队封装到 `SearchNotifier` 或专门 handler；下载路径检查可以保留 UI 弹窗，但下载入队策略应由下载应用服务返回结果。
- 修改风险：中。需要保持现有 Toast、确认弹窗和刷新时机。
- 是否值得立即处理：值得分批处理，优先处理 `playlist_detail_page.dart` 中远程歌单逻辑。
- 分类：建议列入后续重构计划
- 如果要改建议拆成几步执行：1) 先为远程移除提取一个服务方法并让单曲/批量共用；2) 再提取下载入队用例；3) 最后处理搜索分 P 批量菜单逻辑。

### 问题 4

- 等级：Medium
- 标题：持久化边界在 Repository 与 Service 之间不够统一
- 影响模块：歌单管理、搜索历史、备份导入导出、导入刷新
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\library\playlist_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\search\search_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\backup\backup_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\import_service.dart`
- 关键代码位置：`playlist_service.dart:54-58` 同时持有 Repository 与 Isar；`playlist_service.dart:258-276` 直接事务批量删除/更新；`search_service.dart:70-84` 同时持有 `TrackRepository` 与 Isar；`search_service.dart:205-260` 直接 CRUD `searchHistorys`；`backup_service.dart:75-82`、`backup_service.dart:353-356`、`backup_service.dart:406-417` 直接读写多个集合；`import_service.dart:98-103` 同时持有 SourceManager、Repository、Isar。
- 问题描述：Repository 被定义为 CRUD 层，但多个 Service 为了事务或跨集合操作直接拿 Isar。像备份和批量删除这类跨集合事务是合理的，但搜索历史这类简单 CRUD 没有统一 Repository，边界显得不一致。
- 为什么这是问题：调用者难以判断“数据访问应该放 Repository 还是 Service”；测试替身也需要同时 mock Repository 与 Isar。
- 可能造成的影响：新增模型或迁移时容易遗漏服务中的直接 Isar 访问；数据库 watch / invalidate 策略分散。
- 推荐修改方向：保留跨集合事务在应用服务中，但把可独立 CRUD 的对象补齐 Repository（例如 SearchHistory）；对需要事务的 Repository 暴露批量方法或让 Service 明确命名为 Transaction/Application Service。
- 修改风险：中低。主要是搬迁代码和测试覆盖。
- 是否值得立即处理：不需要立即处理；建议和数据库审查/测试补齐一起做。
- 分类：建议列入后续重构计划
- 如果要改建议拆成几步执行：1) 标注哪些服务是跨集合事务服务；2) 给简单集合补 Repository；3) 移除重复直接 Isar CRUD；4) 更新 Provider 依赖。

### 问题 5

- 等级：Medium
- 标题：AudioController 仍然是核心大类，承担过多协调职责
- 影响模块：歌曲播放、队列、临时播放、Mix、网络重试、歌词自动匹配、媒体控制
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
- 关键代码位置：`audio_provider.dart:138-149` 持有 AudioService、QueueManager、AudioStreamManager、Toast、AudioHandler、SMTC、Repository、Lyrics、Settings、MixFetcher；`audio_provider.dart:1699-1814` 播放请求、互斥、电台停止、错误重试、歌词触发、Mix 加载触发；`audio_provider.dart:1830-1874` Source 错误分类处理；`audio_provider.dart:2552-2676` Provider wiring 与派生 Provider 也在同文件。
- 问题描述：项目已经抽出了 `AudioStreamManager`、`PlaybackRequestExecutor`、`QueueManager`、`TemporaryPlayHandler`、`MixPlaylistHandler`，这是好的方向；但 `AudioController` 仍然同时负责状态、业务协调、平台媒体控制、重试、副作用触发和 Provider 定义。
- 为什么这是问题：任何播放相关改动都容易触碰大文件；并发控制、错误处理和 UI 状态更新交织，局部修改风险较高。
- 可能造成的影响：新增播放模式或平台媒体控制功能时，回归范围扩大；单元测试难以隔离。
- 推荐修改方向：不要一次性拆大文件。优先把 Provider wiring 移到独立 provider 文件；再把网络重试、媒体控制同步、Mix 加载更多触发分别收敛为小组件。
- 修改风险：中高。播放链路敏感，必须每一步都有回归测试。
- 是否值得立即处理：不建议立即大规模重构；建议在新增音频功能前先做小步拆分。
- 分类：建议列入后续重构计划
- 如果要改建议拆成几步执行：1) 只移动 provider 定义不改行为；2) 抽媒体控制 binder；3) 抽 retry policy；4) 为 `_executePlayRequest` 建立单元测试后再继续拆。

### 问题 6

- 等级：Low
- 标题：服务层包含 BuildContext / showDialog，UI 与平台服务边界略混合
- 影响模块：下载路径选择、Android 存储权限
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_path_manager.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\storage_permission_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\change_download_path_dialog.dart`
- 关键代码位置：`download_path_manager.dart:29-45` 服务方法接收 `BuildContext` 并弹权限错误；`download_path_manager.dart:85-100` 在服务中构建 AlertDialog；`storage_permission_service.dart:32-57` 请求权限时持有 context；`storage_permission_service.dart:81-110`、`storage_permission_service.dart:143-170` 在服务内显示解释/设置对话框；`change_download_path_dialog.dart:190-214` UI 调用服务选择路径并执行维护。
- 问题描述：权限请求确实需要用户交互，但服务层直接依赖 Flutter UI，使下载路径服务不再是纯业务/平台能力。
- 为什么这是问题：测试和复用不方便；未来如果要在非弹窗入口、CLI/自动同步或不同 UI 样式中复用权限逻辑，会被当前对话框实现限制。
- 可能造成的影响：权限文案或交互修改需要动 service；服务层难以在无 BuildContext 场景调用。
- 推荐修改方向：保留当前行为，但后续可拆成 `StoragePermissionService` 只返回权限状态/下一步动作，UI Widget 负责展示解释和设置引导。
- 修改风险：低。
- 是否值得立即处理：不需要立即处理，除非下载路径交互要继续扩展。
- 分类：当前可接受
- 如果要改建议拆成几步执行：1) 定义权限结果枚举；2) UI 根据枚举弹窗；3) service 移除 `BuildContext` 参数。

### 问题 7

- 等级：Low
- 标题：应用级全局单例与 Provider 生命周期并存，初始化所有权不完全一致
- 影响模块：排行榜缓存、电台刷新、媒体控制 handler
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\main.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\cache\ranking_cache_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\radio\radio_refresh_service.dart`；`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
- 关键代码位置：`main.dart:37-41` 全局 `audioHandler` / `windowsSmtcHandler`；`main.dart:149-155` post-frame 初始化 `RankingCacheService.instance` 与 `RadioRefreshService.instance`；`ranking_cache_service.dart:192-202` Provider 只接入单例并取消网络监听；`radio_refresh_service.dart:17-20` late final 全局单例；`radio_refresh_service.dart:163-170` Provider 仅返回单例；`audio_provider.dart:2616-2617` 从全局 handler 注入控制器。
- 问题描述：部分长期服务由 `main.dart` 初始化为应用级单例，部分由 Riverpod 管理。当前设计有明确注释，但所有权分布在 bootstrap、service 和 provider 三处。
- 为什么这是问题：初始化顺序和测试替换会更复杂；Provider 看似拥有服务，但实际不负责 dispose。
- 可能造成的影响：未来做多窗口、测试容器、热重启、可配置缓存服务时容易遇到实例未初始化或旧监听残留。
- 推荐修改方向：若保持 app-lifetime 单例，应集中在 bootstrap 文档和 provider 注释中声明；若要增强测试性，可改为顶层 bootstrap provider 覆盖实例。
- 修改风险：低到中。
- 是否值得立即处理：不需要立即处理。
- 分类：当前可接受
- 如果要改建议拆成几步执行：1) 保留现有单例但补集中说明；2) 为测试提供 provider override；3) 最后再考虑把初始化收敛到 Riverpod bootstrap。

## 4. 当前设计合理且建议保持不动的点

- UI 未直接调用 `AudioService`：代码搜索 `lib\ui\**\*.dart` 未发现 `audioServiceProvider`、`FmpAudioService`、`JustAudioService`、`MediaKitAudioService` 的实际使用；UI 通过 `audioControllerProvider`、`currentTrackProvider` 等访问播放状态和动作，符合 `CLAUDE.md` 规则。
- `FmpAudioService` 抽象边界清楚：`audio_service.dart:7-61` 定义统一播放、seek、音量、设备、URL/File 入口；`audio_provider.dart:2552-2558` 根据运行平台选择 `JustAudioService` 或 `MediaKitAudioService`。
- 平台拆分值得保持：`audio_runtime_platform.dart:5-26` 统一判断平台；`just_audio_service.dart:134-160` 使用 just_audio/ExoPlayer 并降低移动端缓冲；`media_kit_audio_service.dart:140-166` 使用 media_kit/libmpv 并支持桌面设备切换；`media_kit_audio_service.dart:585-588` 正确转换 0-100 音量范围。
- `QueueManager` 不直接操作播放器，这个边界合理：`queue_manager.dart:15-18` 注释和字段显示其负责队列逻辑与持久化；`queue_manager.dart:448-543` 只做增删插入、getOrCreate、shuffle order 和 persist；实际播放由 `AudioController` / `PlaybackRequestExecutor` 完成。
- 播放请求拆分方向正确：`audio_stream_manager.dart:93-144` 负责选择主/备选播放流；`playback_request_executor.dart:113-181` 负责请求级 superseded 检查、fallback、预取；`audio_provider.dart:1699-1814` 作为状态协调者调用 executor。
- `SourceApiException` 统一错误语义值得保持：`source_exception.dart:5-53` 定义统一 getter 和 Dio 分类；`audio_provider.dart:1770-1788`、`audio_provider.dart:1830-1874` 使用统一错误分支处理不可用、限流、VIP、网络错误。
- Provider + Isar watch 的模式总体合理：`playlist_provider.dart:64-72` 使用 `watchAll()` 驱动列表状态；`playlist_provider.dart:404-433` 对歌单详情做乐观更新；这符合项目文档中的数据加载模式。
- `TrackActionHandler` 是一个好的 UI 行为复用点：`track_action_handler.dart:48-67` 用小接口适配 `AudioController`；`track_action_handler.dart:96-145` 统一 play / play next / add queue / lyrics / remote action。后续可继续把搜索页的分 P 批量动作纳入类似 handler。
- 下载文件扫描用 `FutureProvider` + invalidate 的方向合理：`download_providers.dart:251-263` 通过文件系统扫描返回下载分类/歌曲，UI 删除后在 `downloaded_category_page.dart:1015-1016` invalidate 相关 Provider，符合项目约定。

## 5. 专项优先级建议

1. 应立即修改：暂无 Critical；不建议在没有测试护栏时大改播放/电台核心链路。
2. 第一优先级后续重构：提取 `playlist_detail_page.dart` 中远程歌单移除/同步逻辑，降低页面业务复杂度，并让单曲/批量路径复用同一服务。
3. 第二优先级后续重构：收敛 `YouTubeSource` / Source 实例创建，让 Mix、排行榜、导入走注入入口，减少生命周期和配置分散。
4. 第三优先级后续重构：为 `AudioController` 拆 provider wiring、媒体控制 binder、retry policy；每一步都保持行为不变。
5. 第四优先级后续重构：把 `RadioController` 与 `AudioController` 的互斥/恢复逻辑抽象为共享播放所有权协调器；只有在电台或后台媒体控制继续扩展前再做。
6. 可暂缓：下载路径权限 UI 与服务混合、应用级单例生命周期不统一，目前可接受，等相关功能扩展时再处理。
