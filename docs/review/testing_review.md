# 测试与回归保护审查报告

日期：2026-04-20

## 审查范围

本次审查聚焦 FMP 仓库中“现有测试是否足以为后续改动提供最小回归保护”，重点覆盖以下范围：

- 项目约束与架构说明：`C:\Users\Roxy\Visual Studio Code\FMP\CLAUDE.md`、`C:\Users\Roxy\Visual Studio Code\FMP\docs\development.md`、`C:\Users\Roxy\Visual Studio Code\FMP\docs\comprehensive-analysis.md`
- 当前测试目录结构：`C:\Users\Roxy\Visual Studio Code\FMP\test\**\*.dart`
- 高风险生产代码链路：
  - 音频核心：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`、`audio_stream_manager.dart`、`playback_request_executor.dart`、`queue_manager.dart`、`queue_persistence_manager.dart`、`temporary_play_handler.dart`
  - 下载：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`、`download_path_sync_service.dart`
  - 歌词：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_auto_match_service.dart`
  - 导入：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\import_service.dart`、`playlist_import_service.dart`
  - 音源与账号：`C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\source_provider.dart`、`youtube_source.dart`、`bilibili_source.dart`、`netease_source.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\*.dart`
  - 平台分流与启动：`C:\Users\Roxy\Visual Studio Code\FMP\lib\main.dart`
  - UI 关键规则落点：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\player\player_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\player\mini_player.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\windows_desktop_provider.dart`

本报告只评估“测试与回归保护是否充分”，不评价功能设计取舍本身是否正确。

## 总体结论

当前测试体系并非空白，且在最近几轮 Phase-1 / Phase-2 稳定化工作附近已经形成了一批真正有保护价值的测试：

- 播放请求 superseded / stale async work 的处理已有较强保护。
- 临时播放恢复、Mix 会话 stale load-more 隔离、队列持久化、下载清理竞态、NetEase 迁移默认值、YouTube 播放列表 continuation 解析，已有较明确的回归护栏。

但从“后续还能不能安全重构”的角度看，当前测试仍明显偏向局部修补，缺少跨服务链路的保护。最突出的缺口集中在：

- auth-for-play 从设置到播放/下载/导入的端到端链路
- 重试与恢复播放位置链路
- 歌词自动匹配优先级、并发去重与失败收尾
- 导入与 URL/source dispatch 链路
- Bilibili / NetEase 音源的确定性测试
- 账号服务的登录状态与鉴权头生成
- 平台分流启动逻辑

结论上，这个仓库现在“适合继续做窄改动”，但还“不适合在缺少新增测试的情况下大幅重构上述链路”。如果近期计划继续动音频核心、下载、导入、歌词或账号逻辑，应先补一轮最低保护性测试。

## 发现的问题列表

### 问题 TR-01
- 严重级别: Critical
- 标题: auth-for-play 关键链路缺少端到端回归保护
- 影响模块: 音频播放、下载、导入、账号鉴权
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\models\settings.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_stream_manager.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\import_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\playback_request_executor_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\account\youtube_account_service_test.dart`
- 必要时附关键代码位置:
  - `settings.dart:432-447`
  - `audio_stream_manager.dart:126-141,171-191`
  - `download_service.dart:604-613,741-753`
  - `import_service.dart:172-176`
  - 现有相关测试仅覆盖异步 header 解析被 supersede 的场景：`playback_request_executor_test.dart:99-160,198-260`
- 问题描述: 目前没有测试证明 `useAuthForPlay` 在不同平台音源上会正确控制播放 URL 刷新、下载流获取、下载详情获取、导入刷新时是否携带鉴权头。
- 为什么这是问题: 这条链路跨越 Settings、AudioStreamManager、DownloadService、ImportService 与账号服务，任何一个节点改动都可能让“设置开关存在但不生效”或“本不该带鉴权却错误带上”的问题静默出现。
- 可能造成的影响:
  - 登录态播放开关失效
  - 下载与播放行为不一致
  - 导入刷新和实际播放使用不同鉴权策略
  - 需要登录的 NetEase / 私有内容场景在回归后才暴露
- 推荐修改方向: 先补 service-level 端到端测试矩阵，而不是先继续抽象这条链路。
- 修改风险: 中。需要构建 fake account service / fake source，但对生产代码侵入可控。
- 是否值得立即处理: 是
- 分类: 应立即修改
- 如果要改，建议拆成几步执行:
  1. 为 `AudioStreamManager` 增加参数化测试，覆盖 bilibili / youtube / netease 三种 `useAuthForPlay` 组合。
  2. 为 `DownloadService` 增加测试，分别断言 stream fetch 与 detail fetch 是否取用了 auth headers。
  3. 为 `ImportService` 增加测试，断言 `useAuth` 是否影响 `parsePlaylist(... authHeaders:)` 以及 `Playlist.useAuthForRefresh` 的持久化结果。

### 问题 TR-02
- 严重级别: Critical
- 标题: 重试与恢复播放位置链路缺少直接回归测试
- 影响模块: AudioController、网络重试、恢复播放位置
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_controller_phase1_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\player_state_test.dart`
- 必要时附关键代码位置:
  - `_enterLoadingState()`：`audio_provider.dart:1576-1582`
  - retry / network recovered：`audio_provider.dart:1928-2147`
  - 相关现有测试主要覆盖 stale request：`audio_controller_phase1_test.dart:147-338`
- 问题描述: 现有测试没有直接证明自动重试、手动重试、网络恢复后三条链路都能恢复到原来的播放位置，而不是在进入 loading 时被归零后从 `0:00` 开始。
- 为什么这是问题: 这正是音频播放器最容易“逻辑上看似对，交互上却退化”的点。代码里明确存在把可见 position 置零的步骤，如果没有专门测试，后续很容易又退回旧问题。
- 可能造成的影响:
  - 断网重连后从头播放
  - 用户点击“重试”后丢失进度
  - 回归只在真实播放场景暴露，单看状态字段不易发现
- 推荐修改方向: 基于现有 `FakeAudioService` 和 phase-1 harness 补充三类恢复位置测试。
- 修改风险: 中。测试 harness 已有基础，主要是补时序断言。
- 是否值得立即处理: 是
- 分类: 应立即修改
- 如果要改，建议拆成几步执行:
  1. 增加“自动重试成功后恢复位置”的测试。
  2. 增加 `retryManually()` 成功后恢复位置的测试。
  3. 增加 `_onNetworkRecovered()` 成功后恢复位置的测试。
  4. 增加 max retries 到达后的状态收敛测试，防止无限重试。

### 问题 TR-03
- 严重级别: Critical
- 标题: 歌词自动匹配几乎没有真实回归保护
- 影响模块: 歌词自动匹配、播放触发歌词匹配、缓存与并发去重
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_auto_match_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_service_dispose_test.dart`
- 必要时附关键代码位置:
  - `lyrics_auto_match_service.dart:41-172`
  - `audio_provider.dart:1386-1418,1724`
  - 当前仅能看到构造级覆盖：`audio_service_dispose_test.dart:191-202`
- 问题描述: 目前没有测试覆盖歌词自动匹配的核心分支：已有匹配直接返回、NetEase sourceId 直取、`originalSongId` / `originalSource` 直取、按用户优先级搜索、同一首歌并发去重、失败后 UI loading 状态复位。
- 为什么这是问题: 这条链路混合了异步网络、缓存、数据库和 UI 状态回调，属于典型“稍微重构就会漏一个分支”的区域。
- 可能造成的影响:
  - 自动匹配重复并发执行
  - 导入歌单保存的原平台 ID 不再生效
  - 歌词匹配源优先级改坏后无法及时发现
  - UI 一直停留在“正在自动匹配歌词”状态
- 推荐修改方向: 先单测 `LyricsAutoMatchService`，再补 1 个 `AudioController` 层的状态联动测试。
- 修改风险: 中。需要 fake repo/cache/source，但收益很高。
- 是否值得立即处理: 是
- 分类: 应立即修改
- 如果要改，建议拆成几步执行:
  1. 为 `LyricsAutoMatchService.tryAutoMatch()` 的各优先级分支建立 fake source 测试。
  2. 增加同一 `track.uniqueKey` 并发调用只允许一条执行的测试。
  3. 增加 `AudioController` 中 `_tryAutoMatchLyrics()` 成功/失败都能正确关闭 loading 回调的测试。

### 问题 TR-04
- 严重级别: Critical
- 标题: 导入与 source dispatch 链路缺少保护，重构风险高
- 影响模块: SourceManager、ImportService、PlaylistImportService、导入 Provider
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\source_provider.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\import_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\playlist_import_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\playlist_import_provider.dart`
- 必要时附关键代码位置:
  - `source_provider.dart:55-83`
  - `import_service.dart:143-258`
  - `playlist_import_service.dart:68-77,143-176`
  - `playlist_import_provider.dart:134-167`
- 问题描述: 目前几乎没有测试证明 URL 会分发到正确音源、YouTube Mix 走特殊分支、取消导入会正确清理、导入匹配结果会保留 `originalSongId` / `originalSource` 供歌词系统使用。
- 为什么这是问题: 导入链路跨 URL 检测、歌单解析、数据库写入、取消清理、后续歌词功能依赖，是典型的“一个小重构影响多个功能”的区域。
- 可能造成的影响:
  - 支持的链接格式悄悄失效
  - Mix 播放列表被当普通列表导入
  - 取消导入残留半成品歌单
  - 后续歌词直取能力失效
- 推荐修改方向: 先补 service-level dispatch / import / cancellation 测试，再考虑整理导入架构。
- 修改风险: 中。需要 fake source manager 和 fake repository，但无需大改生产代码。
- 是否值得立即处理: 是
- 分类: 应立即修改
- 如果要改，建议拆成几步执行:
  1. 为 `SourceManager.parseUrl()` / `parsePlaylist()` 补 URL 分发测试。
  2. 为 `ImportService.importFromUrl()` 补新建歌单、更新已有歌单、取消清理测试。
  3. 为 `PlaylistImportService` 补 `originalSongId` / `originalSource` 透传测试。

### 问题 TR-05
- 严重级别: High
- 标题: 一部分现有测试会制造“已覆盖”的错觉
- 影响模块: 下载同步、MiniPlayer UI、Bilibili 音源测试
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\download\download_system_requirements_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\ui\widgets\mini_player_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\bilibili_source_test.dart`
- 必要时附关键代码位置:
  - `download_system_requirements_test.dart:18-369`
  - `mini_player_test.dart:4-163`
  - `bilibili_source_test.dart:17-141`
  - 真实落点代码：`download_path_sync_service.dart:27-164`、`mini_player.dart:171-182,581`、`player_page.dart:402-404`
- 问题描述: 这些测试中有相当一部分并没有真正驱动生产代码：有的是纯对象推演，有的是 placeholder UI 结构，有的是依赖真实网络且包含 `expect(true, isTrue)` 形式的占位断言。
- 为什么这是问题: 这类测试容易在报告中显得“已有测试”，但对真实回归几乎不起作用，甚至会误导后续重构者低估风险。
- 可能造成的影响:
  - 关键链路看似有测试，实则改坏后仍能全部通过
  - 代码评审时对测试覆盖率产生错误判断
  - 继续堆同类弱测试，拉低整个套件含金量
- 推荐修改方向: 用真正驱动生产代码的 temp-dir integration test / real widget test / fake adapter test 替换弱测试。
- 修改风险: 中。主要工作量在重写测试，不在生产代码。
- 是否值得立即处理: 是
- 分类: 应立即修改
- 如果要改，建议拆成几步执行:
  1. 用真实 `DownloadPathSyncService.syncLocalFiles()` 的临时目录集成测试替换 requirement-style 测试。
  2. 用真实 `MiniPlayer` / player progress 交互测试替换 placeholder 结构测试。
  3. 用 fake Dio / adapter 的确定性测试替换 live-network `bilibili_source_test.dart`。

### 问题 TR-06
- 严重级别: High
- 标题: QueueManager 的队列变更与 shuffle 行为保护不足
- 影响模块: QueueManager、队列顺序、shuffle 顺序、持久化恢复
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\queue_manager.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\queue_manager_test.dart`
- 必要时附关键代码位置:
  - `queue_manager.dart:240-252`
  - `queue_manager.dart:428-487`
  - `queue_manager.dart:689-818`
  - 当前测试主要是 model/value 语义：`queue_manager_test.dart:71-375`
- 问题描述: 当前测试对 `QueueManager` 的保护更多停留在模型属性和少量 timer cleanup，没有覆盖 shuffle 顺序生成、插入/删除后的索引修正、恢复队列时的顺序与边界行为。
- 为什么这是问题: 队列与 shuffle 是用户最直接感知的状态之一，而且这部分最容易在“看似只是内部重构”的改动里被弄坏。
- 可能造成的影响:
  - shuffle 开启后当前歌曲位置错误
  - 插入/删除队列后后续播放顺序异常
  - 恢复队列后 currentIndex 越界或指向错误歌曲
- 推荐修改方向: 给 `QueueManager` 增加 mutation-heavy 测试，而不是继续只测 PlayQueue 值对象。
- 修改风险: 中。已有 Isar harness 可复用。
- 是否值得立即处理: 是，尤其在计划继续拆分 `QueueManager` 时
- 分类: 建议列入后续重构计划
- 如果要改，建议拆成几步执行:
  1. 增加 shuffle 开启后“当前歌曲必须在首位”的测试。
  2. 增加 add / remove / restoreQueue 过程中的索引修正测试。
  3. 增加持久化后再恢复的顺序一致性测试。

### 问题 TR-07
- 严重级别: High
- 标题: 账号服务的登录与鉴权头生成测试过薄
- 影响模块: YouTube、NetEase、Bilibili 账号服务
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\youtube_account_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\netease_account_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\bilibili_account_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\account\youtube_account_service_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\account\youtube_playlist_service_test.dart`
- 必要时附关键代码位置:
  - `youtube_account_service.dart:60-111,167-180`
  - `netease_account_service.dart:59-111,221-308`
  - `bilibili_account_service.dart:93-180`
  - 当前现有测试仅覆盖少量 YouTube helper：`youtube_account_service_test.dart:6-105`、`youtube_playlist_service_test.dart:5-39`
- 问题描述: 目前没有覆盖 NetEase / Bilibili 登录解析、QR 轮询边界、logout 清理、auth headers 输出格式等关键行为的确定性测试。
- 为什么这是问题: 账号系统本身不常改，但一旦改坏，影响范围会立刻扩散到播放、下载、导入和账户管理页面。
- 可能造成的影响:
  - 已登录状态误判
  - Cookie/Authorization 头格式变化后下游功能整体失效
  - QR 登录边界状态回归
- 推荐修改方向: 按平台补 service-level 测试，优先覆盖 auth headers 与登录状态判定。
- 修改风险: 中。需要对 secure storage / Dio 交互做 fake。
- 是否值得立即处理: 视近期是否继续改账号或 auth-for-play 而定；若要继续动，应立即处理
- 分类: 建议列入后续重构计划
- 如果要改，建议拆成几步执行:
  1. 先补 `getAuthHeaders()` / `getAuthCookieString()` 的输出测试。
  2. 再补 NetEase / Bilibili QR 登录状态机测试。
  3. 最后补 logout 与登录状态持久化相关测试。

### 问题 TR-08
- 严重级别: High
- 标题: 平台分流与启动初始化几乎没有测试护栏
- 影响模块: 启动流程、音频后端选择、桌面平台初始化
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\main.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\just_audio_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\media_kit_audio_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_service_dispose_test.dart`
- 必要时附关键代码位置:
  - `main.dart:124-127`
  - `audio_provider.dart:2583-2587`
  - `just_audio_service.dart:133-149`
  - `media_kit_audio_service.dart:138-159`
  - 当前仅有 dispose 安全性测试：`audio_service_dispose_test.dart:149-163`
- 问题描述: 现在没有测试证明 Android/iOS 与桌面平台会稳定选择正确后端，也没有测试保护桌面平台 `MediaKit.ensureInitialized()` 的启动门控逻辑。
- 为什么这是问题: 这类平台差异常常在本机“看着正常”，但在跨平台重构、条件抽取、启动优化时很容易引入静默回归。
- 可能造成的影响:
  - 桌面平台未初始化 media_kit
  - 移动端错误走桌面音频实现
  - 启动时序调整后平台依赖初始化顺序错乱
- 推荐修改方向: 抽一个极小的可测试 seam 来验证平台分流与初始化门控，而不是等问题出现在运行环境再修。
- 修改风险: 低到中。可能需要很小的 seam 抽取，但收益明显。
- 是否值得立即处理: 如果近期要动启动或后端选择逻辑，值得立即处理；否则可排后
- 分类: 建议列入后续重构计划
- 如果要改，建议拆成几步执行:
  1. 抽出后端选择函数或 provider seam。
  2. 为 desktop-only `MediaKit.ensureInitialized()` 门控建立测试。
  3. 为两个后端各补一个最小 smoke test，验证初始化关键默认值。

### 问题 TR-09
- 严重级别: High
- 标题: Bilibili / NetEase 音源缺少与 YouTube 同等级的确定性测试
- 影响模块: 音源解析、播放列表解析、URL 刷新、异常分类
- 具体文件路径:
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\bilibili_source.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\netease_source.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\youtube_source.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\data\sources\youtube_source_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\data\sources\source_exception_test.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\test\bilibili_source_test.dart`
- 必要时附关键代码位置:
  - `youtube_source.dart:1171`
  - `bilibili_source.dart:437`
  - `netease_source.dart:257`
  - `source_provider.dart:55-83`
  - YouTube 现有覆盖较强：`youtube_source_test.dart:9-581`
  - 统一异常语义覆盖较强：`source_exception_test.dart:9-220`
- 问题描述: YouTube 的 playlist continuation / Mix helper 已有较强确定性测试，但 Bilibili 与 NetEase 还缺少同等级的 fake adapter / fake Dio 测试，导致三源能力保护明显不均衡。
- 为什么这是问题: 仓库是多音源播放器，若只有 YouTube 链路有较强保护，后续做统一抽象或共享逻辑时，更容易把另两个源改坏而不自知。
- 可能造成的影响:
  - Bilibili / NetEase 歌单导入、短链解析、URL 刷新回归
  - 多音源统一重构后只有 YouTube 继续稳定
  - 回归发现时间推迟到手工验证阶段
- 推荐修改方向: 参考 `youtube_source_test.dart` 的做法，为另两个源建立确定性解析测试，而不是继续依赖 live-network 测试。
- 修改风险: 中。需要构建 fake adapter，但模式清晰。
- 是否值得立即处理: 在打算继续重构多音源抽象前，值得立即处理
- 分类: 建议列入后续重构计划
- 如果要改，建议拆成几步执行:
  1. 先补 Bilibili playlist / multipage / refreshAudioUrl 测试。
  2. 再补 NetEase playlist / short-link / login-required stream 测试。
  3. 补 `SourceManager` 跨源 dispatch 测试，确保 URL 路由不被重构破坏。

## 当前覆盖已相对充分的区域

以下区域从“回归保护是否足够支撑当前窄改动”角度看，现状已基本可接受，除非要主动改变行为，否则建议不要为了“看起来更整齐”而先动它们：

1. 播放请求 superseded / stale async work
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_controller_phase1_test.dart:147-449`
   - 结论：对最近的 Phase-1 竞态修复已有较实用的护栏，适合继续做窄范围维护。

2. 临时播放恢复语义
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\temporary_play_handler_test.dart:102-187`
   - 结论：链式 temporary play 恢复原队列目标的关键行为已有明确保护。

3. Mix stale session 清理
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\mix_session_handler_test.dart:31-215`
   - 结论：对“旧 load-more 不得污染新 session”的风险已有较直接覆盖。

4. 队列持久化与 NetEase 迁移默认值
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\queue_persistence_manager_test.dart:61-175`、`C:\Users\Roxy\Visual Studio Code\FMP\test\providers\database_migration_test.dart:31-96`
   - 结论：当前迁移项与持久化字段已有基本保障，但后续新增“非类型默认值即业务默认值”的字段仍需逐个补迁移测试。

5. 下载 cleanup 竞态
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\download\download_service_phase1_test.dart:63-451`
   - 结论：Phase-1 修复过的 setup-window / cancel / dispose 竞态已有较好保护。

6. YouTube 播放列表 continuation 解析
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\data\sources\youtube_source_test.dart:9-581`
   - 结论：这一块相对成熟，除非要主动改变解析策略，否则不建议无测试前提下重写。

7. Ranking cache 生命周期
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\cache\ranking_cache_service_test.dart:15-103`
   - 结论：Provider teardown / rebind 相关修复已有足够的回归护栏。

8. Phase-2 动态行 `ValueKey` 规则
   - 相关测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\ui\pages\search\search_page_phase2_test.dart:6-74`
   - 结论：这部分虽不是重型测试，但对既定 key 规则已有针对性约束，可继续保持。

## 最低限度测试补强计划

### 第一优先级
1. auth-for-play 测试矩阵
   - 覆盖播放、下载、导入三条链路。
2. 重试与恢复播放位置测试
   - 覆盖自动重试、手动重试、网络恢复三条路径。
3. 歌词自动匹配测试
   - 覆盖优先级、并发去重、失败收尾。
4. 导入与 source dispatch 测试
   - 覆盖 URL 分发、Mix 特判、取消清理、原平台 ID 透传。

### 第二优先级
5. 用真实 `DownloadPathSyncService.syncLocalFiles()` 测试替换弱 requirement-style 测试。
6. 为 `QueueManager` 增加队列变更 / shuffle / restoreQueue 行为测试。
7. 为 NetEase / Bilibili 账号服务补 `getAuthHeaders()` 与登录状态测试。
8. 为平台分流与启动门控建立极小 seam 的测试。

### 第三优先级
9. 为 Bilibili / NetEase 音源补齐与 YouTube 同级别的确定性解析测试。
10. 若近期会继续改播放器 UI，再补真实 widget 测试，覆盖：
   - `C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\player\player_page.dart:402-404`
   - `C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\player\mini_player.dart:171-182,581`
   - `C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\windows_desktop_provider.dart:32-40`

总体建议是：先补 service-boundary 测试，再做更大的结构整理。对这个仓库来说，新增 10 个真正打中风险链路的测试，价值明显高于新增 40 个只验证静态结构或重复业务常识的测试。
