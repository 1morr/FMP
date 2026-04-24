# FMP 测试与回归风险审查报告

## 1. 审查范围

- 已阅读项目根目录 `CLAUDE.md` 以及 `.serena/memories/code_style.md`、`download_system.md`、`ui_coding_patterns.md`、`refactoring_lessons.md`、`update_system.md`。
- 静态审查 `test/**/*.dart`、关键音频/下载/歌词/导入/迁移/平台/UI 代码；未运行 `flutter test` 或重型 build。
- 重点覆盖：播放队列/临时播放/记忆位置、superseded request、音频 URL 过期/重试、下载调度/路径/失败恢复、歌词自动匹配/缓存/源映射、导入原平台 ID、auth 播放边界、平台 split、Isar migration/default repair、可测试 UI 规则。

## 2. 总体结论

现有测试数量和近几轮重构保护明显增加，核心播放竞态已有较多回归测试：

- 音频：`test/services/audio/audio_controller_phase1_test.dart` 覆盖 superseded 请求、临时播放恢复、Mix load-more、队列/playingTrack 分离；`playback_request_executor_test.dart` 覆盖播放 handoff、fallback、header 后 superseded；`temporary_play_handler_test.dart` 覆盖链式临时播放；`queue_manager_test.dart`/`queue_persistence_manager_test.dart` 覆盖队列模型与持久化。
- 下载：`download_service_phase1_test.dart` 覆盖 pause/cancel/dispose/setup race、Range 被忽略、下载 auth、下载流有效期；`download_path_maintenance_service_phase2_test.dart` 覆盖多 P 路径清理。
- 数据/迁移：`database_migration_test.dart` 覆盖当前 Settings/PlayQueue 默认修复、重复迁移不覆盖用户设置。
- 歌词/导入：`lyrics_auto_match_service_phase4_test.dart` 仅覆盖源顺序与 in-flight 去重；`import_playlist_provider_phase2_test.dart` 覆盖 provider 生命周期/取消；`import_service_phase4_test.dart` 覆盖 URL dispatch 与 playlist auth。
- UI：有 `TrackThumbnail` widget 测试、少量页面行为测试和若干源代码字符串守卫（selector、ValueKey、重排等）。

主要缺口集中在“跨模块链路”：源返回的 URL 有效期如何进入播放、暂停后过期恢复是否被新请求取代、外部歌单导入 ID 到歌词直取的端到端链路、下载完成事件到 UI provider invalidation、以及 UI 规范的可执行防护。重构前应优先补这些最小测试，而不是扩大慢速集成测试。

## 3. 测试缺口 / 回归风险问题列表

### 问题 1

- 等级：高
- 标题：主播放流 URL 有效期未按音源返回值固化，且测试只保护下载/备用流
- 影响模块：音频播放、URL 过期检测、Netease 播放
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart:60-68`；相关测试 `C:\Users\Roxy\Visual Studio Code\FMP\test\services\download\download_service_phase1_test.dart:587-660`、`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_stream_manager_test.dart:244-266`
- 关键代码位置：`track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));`
- 问题描述：主播放 `AudioStreamDelegate.ensureAudioStream()` 忽略 `AudioStreamResult.expiry`，始终写 1 小时；现有测试只验证下载路径使用源有效期、fallback selection 使用源有效期。
- 为什么这是问题：`CLAUDE.md` 明确 Netease 音频 URL 约 16 分钟过期，播放路径错写为 1 小时会让 `Track.hasValidAudioUrl` 在真实 URL 失效后仍返回 true。
- 可能造成的影响：暂停/后台恢复时不刷新 URL，出现解码失败、错误重试链路被误触发，或用户需要手动重新播放。
- 推荐修改方向：先在 `audio_stream_manager_test.dart` 增加主路径 `ensureAudioStream/selectPlayback` 使用 `streamResult.expiry` 的失败测试，再把主路径改为 `streamResult.expiry ?? const Duration(hours: 1)`。
- 修改风险：低到中；改动小，但会影响所有源的过期时间，需要保留无 expiry 时的一小时 fallback。
- 是否值得立即处理：是。
- 分类：缺失测试 + 潜在功能缺陷。
- 如果要改建议拆成几步执行：1) 给 fake source 增加可配置 expiry；2) 写主播放 expiry 测试；3) 修复 delegate；4) 跑音频相关测试。

### 问题 2

- 等级：高
- 标题：暂停后 URL 过期恢复链路缺少端到端和取代竞态测试
- 影响模块：AudioController、暂停/恢复、快速切歌竞态
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart:427-468`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart:2171-2191`
- 关键代码位置：`_resumeWithFreshUrlIfNeeded()` 调用 `_playTrack(requestTrack)` 后延迟 `seekTo(position)`。
- 问题描述：现有测试覆盖网络恢复重试，但没有覆盖 `play()`/`togglePlayPause()` 在当前 track URL 过期时刷新并恢复位置，也没有覆盖刷新完成到延迟 seek 之间被新播放请求取代的场景。
- 为什么这是问题：项目规则要求 URL 获取/恢复链路必须遵守 `_playRequestId` superseded 语义；该方法虽然委托 `_playTrack()`，但后续 `Future.delayed` 和 `seekTo()` 没有显式校验当前请求/track 是否仍然有效。
- 可能造成的影响：用户暂停过夜后恢复时播放失败；快速点击其他歌曲时，旧恢复链路可能把新歌曲 seek 到旧位置。
- 推荐修改方向：新增 AudioController 测试：1) 过期远程 URL 调用 `togglePlayPause()` 会重新取流并恢复原位置；2) 本地下载文件存在时不刷新；3) 刷新后 seek 前新请求取代时不 seek 新 track。
- 修改风险：中；测试需要 FakeAudioService pending gate 控制时序。
- 是否值得立即处理：是，尤其在继续改播放控制前。
- 分类：缺失测试 + 竞态风险。
- 如果要改建议拆成几步执行：1) 写 happy-path 过期恢复测试；2) 写 local-file 排除测试；3) 写 superseded seek 测试；4) 根据失败点补 requestId/track 校验。

### 问题 3

- 等级：高
- 标题：外部歌单原平台 ID 到歌词直取链路缺少测试
- 影响模块：外部歌单导入、歌词自动匹配、歌词缓存/匹配表
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\playlist_import_service.dart:67-78`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_auto_match_service.dart:59-90`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_auto_match_service.dart:151-172`
- 关键代码位置：`selectedTracks` 写入 `Track.originalSongId/originalSource`，`tryAutoMatch()` 再按 `originalSource` 直取 Netease/QQMusic 歌词。
- 问题描述：现有 `lyrics_auto_match_service_phase4_test.dart:70-140` 只覆盖源顺序和 in-flight 去重；没有测试已有匹配短路、Netease track sourceId 直取、`originalSongId/originalSource` 直取、Spotify 原 ID fallback 到搜索、cache 与 `LyricsMatch` 写入是否一致。
- 为什么这是问题：这是外部歌单导入后“直接拿原平台歌词”的核心价值链路，任何字段名、source 字符串或缓存保存改动都可能静默失效。
- 可能造成的影响：导入歌单歌曲只能走模糊搜索，匹配错误率上升，已有缓存/匹配表被重复请求或覆盖。
- 推荐修改方向：增加纯单元测试：`PlaylistImportResult.selectedTracks` source 映射；`tryAutoMatch()` 对 netease sourceId、qqmusic original ID、spotify original ID、已有 match 的行为；断言 cache key 与 `LyricsMatch.lyricsSource/externalId`。
- 修改风险：低；Fake lyrics source 已存在，扩展成本小。
- 是否值得立即处理：是。
- 分类：缺失测试。
- 如果要改建议拆成几步执行：1) 补 selectedTracks 映射测试；2) 补 direct fetch 测试；3) 补已有 match/cache 测试；4) 再做歌词/导入重构。

### 问题 4

- 等级：中高
- 标题：下载完成/失败事件到 UI provider 刷新的链路缺少真实 provider 测试
- 影响模块：下载服务、下载页面、FileExistsCache、播放列表详情刷新
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart:764-783`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\download\download_providers.dart:64-101`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\providers\download\download_providers.dart:115-121`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_category_page.dart:736-742`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_category_page.dart:1005-1016`
- 关键代码位置：completion listener 标记 `fileExistsCacheProvider`、清内存进度、debounce 后 invalidate `downloadedCategoriesProvider/downloadedCategoryTracksProvider`。
- 问题描述：`download_service_phase1_test.dart` 保护服务内部 race；`download_system_requirements_test.dart:222-270` 使用 mock list/set 验证“概念”，没有启动 `downloadServiceProvider` 或验证真实 invalidation/Toast/playlist refresh。
- 为什么这是问题：下载完成后 UI 是否显示已下载、分类是否刷新、失败是否提示都依赖 provider glue，重构 provider 时很容易漏掉。
- 可能造成的影响：文件已下载但 UI 不更新、分类页仍显示旧数据、失败无提示、内存进度残留。
- 推荐修改方向：将 completion/failure 处理提取为可测试 helper 或为 provider 注入 fake service；用 `ProviderContainer` 断言 completion 后 `markAsExisting`、task progress 移除、分类 provider 被刷新、失败 event 触发 toast。
- 修改风险：中；可能需要轻微抽象以避免真实 isolate 下载。
- 是否值得立即处理：是，若要继续改下载 provider 或下载页面。
- 分类：缺失测试 + provider glue 回归风险。
- 如果要改建议拆成几步执行：1) 提取/注入事件处理边界；2) 写 completion provider 测试；3) 写 failure toast 测试；4) 保留现有下载服务 race 测试。

### 问题 5

- 等级：中
- 标题：本地下载文件优先播放只测到 stream manager，未测播放 handoff
- 影响模块：离线播放、PlaybackRequestExecutor、AudioController
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart:34-47`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\playback_request_executor.dart:211-219`、相关测试 `C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_stream_manager_test.dart:128-175`、概念测试 `C:\Users\Roxy\Visual Studio Code\FMP\test\services\download\download_system_requirements_test.dart:305-360`
- 关键代码位置：`localPath != null` 时 executor 应调用 `playFile()`，否则调用 `playUrl()`。
- 问题描述：已有测试验证 `ensureAudioUrl()` 能返回本地路径并清理缺失路径，但没有断言 executor/controller 真的使用 `playFile()` 且不附加网络 headers、不触发 URL fallback。
- 为什么这是问题：音频 handoff 层与 stream manager 分离后，重构 executor 时可能把本地路径当 URL 处理。
- 可能造成的影响：离线歌曲仍走网络、Referer/header 错误、已下载文件播放失败。
- 推荐修改方向：在 `playback_request_executor_test.dart` 增加 local selection fake，断言 `FakeAudioService.playFileCalls`、`playUrlCalls.isEmpty`；再加一个 controller 层 smoke 覆盖队列状态。
- 修改风险：低。
- 是否值得立即处理：是，但优先级低于问题 1-4。
- 分类：缺失测试。
- 如果要改建议拆成几步执行：1) executor 单测；2) controller smoke；3) 删除/降级概念性 pseudo-test 依赖。

### 问题 6

- 等级：中
- 标题：UI 规范只有局部字符串守卫，当前 ListTile.leading Row 违规未被测试暴露
- 影响模块：列表性能、导入预览、歌词源设置、UI 规范回归
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\import_preview_page.dart:478-514`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\settings\lyrics_source_settings_page.dart:180-200`、相关测试 `C:\Users\Roxy\Visual Studio Code\FMP\test\ui\pages\search\search_page_phase2_test.dart:39-78`
- 关键代码位置：`ListTile(leading: Row(...))` 与项目 UI 规范“避免 Row inside ListTile.leading”冲突。
- 问题描述：测试覆盖了部分页面的 `ValueKey` 和 selector 字符串，但没有全局防护 `Image.network/Image.file`、`Slider.onChanged` seek、`ListTile.leading Row`、`AppBar.actions` 尾部间距等规范；现有违规未被测试发现。
- 为什么这是问题：这些规范来自真实性能/交互 bug，属于适合静态测试或 lint 的低成本回归点。
- 可能造成的影响：列表滚动抖动、进度条拖动误 seek、图片 404 fallback、AppBar 间距不一致。
- 推荐修改方向：增加轻量静态规范测试或自定义 lint；对确需例外的页面建立 allowlist，并为导入预览/歌词源设置补行为或布局测试后再改。
- 修改风险：低到中；静态规则可能需要少量 allowlist 避免误报。
- 是否值得立即处理：若近期改 UI，值得立即处理。
- 分类：缺失测试 + 已存在规范违规。
- 如果要改建议拆成几步执行：1) 写只读静态测试并记录 allowlist；2) 修复当前违规；3) 给关键进度条补 widget 行为测试。

## 4. 最低限度测试补齐清单

1. `audio_stream_manager_test.dart`：主播放 `ensureAudioStream/selectPlayback` 使用 `AudioStreamResult.expiry`，覆盖 Netease 16 分钟场景。
2. `audio_controller_*_test.dart`：`togglePlayPause()`/`play()` 遇到过期 URL 刷新并恢复位置；本地文件不刷新；刷新后被新请求取代不 seek 新 track。
3. `lyrics_auto_match_service_phase4_test.dart` + 新的 playlist import result 单测：覆盖 `originalSongId/originalSource` 映射、Netease/QQMusic direct fetch、Spotify fallback、已有 match 短路、cache + `LyricsMatch` 写入。
4. `download_providers` provider 级测试：completion event 后 FileExistsCache、内存进度、分类/分类详情 invalidation、playlist detail refresh；failure event 后 toast。
5. `playback_request_executor_test.dart`：localPath 走 `playFile()`，不走 `playUrl()`/fallback/header。
6. UI 静态规范测试：禁止新 `Image.network/Image.file`，禁止 `Slider.onChanged` 调 `seekToProgress()`，禁止非 allowlist 的 `ListTile.leading Row`，必要时检查 AppBar trailing spacing。
7. 新增 Isar model 字段时强制同步新增 migration/default 测试；当前 `database_migration_test.dart` 可作为模板。

## 5. 重构前必须先保护的链路

- 播放请求锁：`_executePlayRequest()`、`PlaybackRequestExecutor`、`_restoreQueuePlayback()`、`_resumeWithFreshUrlIfNeeded()` 的 superseded 行为。
- 临时播放恢复：链式临时播放、`rememberPlaybackPosition=false`、rewind 秒数、暂停状态恢复、队列被改动后的 index clamp。
- 音频流选择：auth headers、源返回 expiry、fallback stream、local file 优先、prefetch 不污染队列对象。
- 下载：savePath 去重、setup-window cancel、dispose mid-flight、Range resume、完成事件 provider glue、失败事件 UI 提示。
- 歌词：导入原平台 ID → direct lyrics fetch → cache/`LyricsMatch` → `currentLyricsContentProvider` 按源加载。
- Isar migration：Settings/PlayQueue 非类型默认值、重复迁移不覆盖用户意图。
- 平台 split：`audioServiceProvider` mobile/desktop 选择、`main.dart` 中 `MediaKit.ensureInitialized()` 仅桌面执行、Windows 多窗口插件注册策略。

## 6. 当前可接受 / 不建议过度测试的点

- `database_migration_test.dart` 对当前已知默认修复覆盖较好；不需要为每个 Isar getter/setter 写重复测试，但新增字段必须补迁移测试。
- `audio_runtime_platform_phase4_test.dart` 已覆盖 provider 选择；主函数平台初始化可用轻量静态 smoke，不必做复杂平台模拟。
- 第三方站点真实 API、登录二维码/WebView、Bilibili/YouTube/Netease 在线解析不宜作为默认单元测试，可保留 demo/manual 测试或用 fake HTTP。
- 性能 benchmark 测试可作为人工参考，不应承担功能回归职责。
- 源代码字符串测试适合保护边界/规范，但关键业务链路（播放、下载、歌词）应优先用 fake service 的行为测试。