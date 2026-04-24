# 稳定性与潜在缺陷审查报告

## 1. 审查范围

- 审查对象：FMP Flutter 音乐播放器 Android / Windows 主仓库。
- 审查依据：根目录 `CLAUDE.md`、`.serena/memories/refactoring_lessons.md`、`download_system.md`、`ui_coding_patterns.md`、`update_system.md`，以及真实代码。
- 深挖链路：播放队列、临时播放、恢复队列、remember playback position、播放请求 superseded、音频 URL 过期刷新、下载任务调度/失败恢复、歌词自动匹配、外部歌单原始平台 ID、登录态与鉴权播放、平台多窗口/单实例/更新。
- 未修改业务代码；本报告仅记录缺陷、风险与建议。

## 2. 总体结论

核心播放竞态治理已经比早期实现成熟：`AudioController` 使用 `_PlaybackContext`、`_playRequestId`、`PlaybackRequestExecutor` 与 `_isSuperseded()`，临时播放/恢复队列/初始化恢复均有统一入口；下载系统也已引入 isolate 和 setup-window cancel 防护。没有发现“UI 直接操作 AudioService”或明显会立即破坏播放主链路的 Critical 问题。

稳定性风险主要集中在跨模块边界：播放侧忽略音源真实 URL expiry、过期 URL 恢复后的延迟 seek 缺少取代校验、Windows ZIP 更新缺少路径穿越防御、下载实际媒体请求头与播放鉴权不一致、下载完成阶段跨文件系统/数据库写入不是一个可恢复状态机、外部歌单 selected track 原地写入原始 ID、以及 radio/audio 共享播放器所有权仍依赖回调字段。

## 3. 发现的问题列表

### 问题 1

- 等级：High
- 标题：播放侧忽略 `AudioStreamResult.expiry`，短有效期音源会被错误视为仍有效
- 影响模块：音频播放、Netease/Bilibili URL 刷新、暂停后恢复、队列恢复
- 具体文件路径：`lib/services/audio/internal/audio_stream_delegate.dart`、`lib/services/audio/audio_provider.dart`
- 关键代码位置：`audio_stream_delegate.dart:61-69` 固定 `DateTime.now().add(const Duration(hours: 1))`；`audio_provider.dart:2171-2191` 根据 `track.hasValidAudioUrl` 决定是否刷新。
- 问题描述：下载侧已使用 `streamResult.expiry ?? const Duration(hours: 1)`，但播放侧主路径仍固定 1 小时。
- 为什么这是问题：项目规则明确 Netease URL 约 16 分钟过期，Bilibili/YouTube 也可能短期签名；写长过期时间会让 `hasValidAudioUrl` 误判。
- 可能造成的影响：暂停较久后恢复播放失败、队列恢复使用过期 URL、错误恢复链路被迫处理本应提前刷新解决的问题。
- 推荐修改方向：播放侧与下载侧一致使用 `streamResult.expiry ?? const Duration(hours: 1)`；如果某 source 未返回 expiry，由 source 层给保守默认。
- 修改风险：Low。会增加短有效期源的刷新次数，但符合业务预期。
- 是否值得立即处理：是。
- 分类：应立即修改
- 如果要改，建议拆成几步执行：1) 补主播放 expiry 单测；2) 修改 `audio_stream_delegate.dart`；3) 验证 Netease/Bilibili 暂停恢复。

### 问题 2

- 等级：High
- 标题：过期 URL 恢复后延迟 seek 缺少 request/track 取代校验
- 影响模块：`AudioController.play()` / `togglePlayPause()`、暂停后恢复、快速切歌
- 具体文件路径：`lib/services/audio/audio_provider.dart`
- 关键代码位置：`audio_provider.dart:2171-2191` `_resumeWithFreshUrlIfNeeded()` 在 `_playTrack()` 后 `Future.delayed()` 再 `seekTo(position)`。
- 问题描述：过期 URL 恢复委托 `_playTrack()` 能进入统一请求入口，但恢复位置的延迟 seek 在 `_playTrack()` 返回后执行，没有再确认当前播放请求或当前 track 仍是原 track。
- 为什么这是问题：项目规则要求任何独立 URL 获取/恢复逻辑在每个 await 后检查 superseded；这里的 seek 是播放请求完成后的额外副作用。
- 可能造成的影响：用户恢复过期 URL 后立刻点其他歌曲，旧链路可能把新歌曲 seek 到旧歌曲位置。
- 推荐修改方向：捕获恢复前的 `track.uniqueKey` 与 request generation；延迟后检查 `state.currentTrack` 仍匹配且没有新请求，再执行 seek；或把恢复位置纳入 `_executePlayRequest` 参数由统一入口完成。
- 修改风险：Medium。需覆盖 play/toggle、本地文件排除、快速切歌。
- 是否值得立即处理：是，尤其在修复 expiry 后该路径会更常触发。
- 分类：应立即修改
- 如果要改，建议拆成几步执行：1) 写 superseded seek 回归测试；2) 增加 track/request 校验；3) 回归临时播放与队列播放。

### 问题 3

- 等级：High
- 标题：Windows 便携版更新 ZIP 解压缺少路径穿越校验
- 影响模块：应用内更新、Windows portable update
- 具体文件路径：`lib/services/update/update_service.dart`
- 关键代码位置：`update_service.dart:413-424` 使用 `'$extractDir/${file.name}'` 直接写文件。
- 问题描述：ZIP entry 名称没有规范化，也未确认目标路径仍在 `extractDir` 下。
- 为什么这是问题：更新包虽来自 GitHub Release，但仍是外部输入；包含 `../`、绝对路径或盘符路径时可能写出临时目录。
- 可能造成的影响：覆盖临时目录外文件，破坏更新安全边界。
- 推荐修改方向：对每个 entry 做 normalize/canonicalize；拒绝绝对路径、盘符路径和逃逸 `extractDir` 的路径；非法 entry 终止更新并报错。
- 修改风险：Low-Medium。正常 ZIP 不受影响，但需测试 Windows 路径分隔符。
- 是否值得立即处理：是。
- 分类：应立即修改
- 如果要改，建议拆成几步执行：1) 提取安全解压路径函数；2) 增加正常/恶意 ZIP 单测；3) 验证便携版更新。

### 问题 4

- 等级：Medium
- 标题：下载实际媒体请求头未复用播放侧鉴权 headers
- 影响模块：下载系统、Netease 登录歌曲、Bilibili/YouTube 鉴权内容
- 具体文件路径：`lib/services/download/download_service.dart`、`lib/services/audio/audio_stream_manager.dart`
- 关键代码位置：`download_service.dart:604-611` 获取 stream 时使用 authHeaders；`download_service.dart:656-677` isolate 下载只传固定 UA/Referer；`audio_stream_manager.dart:159-180` 播放侧按 source 构造 playback headers。
- 问题描述：source API 获取 URL 时可能使用 Cookie/auth headers，但真正下载 CDN URL 时没有携带这些 headers。
- 为什么这是问题：部分内容要求媒体请求也带 Cookie、Origin 或特定 UA；播放侧和下载侧行为会分裂。
- 可能造成的影响：能播放但下载 401/403，尤其是 Netease 登录/VIP或 Bilibili 登录态内容。
- 推荐修改方向：提取“媒体请求 headers”构造 helper，让下载 isolate 合并必要 auth headers 与固定 Referer/UA；逐平台明确哪些 headers 可传给 CDN。
- 修改风险：Medium。不同 CDN 对 Cookie/Origin 有差异，需逐源验证。
- 是否值得立即处理：建议近期处理。
- 分类：应立即修改
- 如果要改，建议拆成几步执行：1) 抽 headers helper；2) Netease 登录样例验证；3) Bilibili/YouTube 回归；4) 更新下载文档。

### 问题 5

- 等级：Medium
- 标题：下载完成阶段跨文件系统与数据库写入不是可恢复的一致状态机
- 影响模块：下载完成、已下载标记、下载任务状态、失败恢复
- 具体文件路径：`lib/services/download/download_service.dart`
- 关键代码位置：`download_service.dart:734-773` rename temp file、保存 metadata、`TrackRepository.addDownloadPath()`、`DownloadRepository.updateTaskStatus(completed)` 分步执行。
- 问题描述：文件已重命名后，Track 路径写入和任务 completed 写入分属多个操作；任一步异常或进程退出都会留下半完成状态。
- 为什么这是问题：文件系统与数据库不能真正同一事务，但应有明确的可恢复状态机和启动修复。
- 可能造成的影响：磁盘已有文件但任务仍 failed/downloading；或 Track 已标记下载但任务未完成，下载管理页与库页状态不一致。
- 推荐修改方向：DB 部分至少在一个 `writeTxn` 中写 Track 路径和任务状态；启动/进入下载页时扫描 `.downloading` 与正式文件，修复半完成状态。
- 修改风险：Medium。需兼顾 pause/resume/cancel 语义。
- 是否值得立即处理：建议列入近期修复。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 合并 DB 完成事务；2) 增加半完成恢复扫描；3) 补下载完成崩溃恢复测试。

### 问题 6

- 等级：Medium
- 标题：外部歌单匹配结果在 `selectedTracks` 中原地写入 original ID，可能污染复用对象
- 影响模块：外部歌单导入、歌词自动匹配、搜索结果对象复用
- 具体文件路径：`lib/services/import/playlist_import_service.dart`、`lib/services/lyrics/lyrics_auto_match_service.dart`
- 关键代码位置：`playlist_import_service.dart:68-77` 对 `t.selectedTrack!` 直接写 `originalSongId/originalSource`；`lyrics_auto_match_service.dart:82-90` 依赖这些字段直接取歌词。
- 问题描述：`selectedTrack` 来自匹配搜索结果，getter 中直接修改该对象后返回；如果同一对象仍被 UI 或缓存复用，原平台 ID 会被附加到原对象。
- 为什么这是问题：getter 按语义应像只读派生结果，但实际有副作用；字段污染会让后续歌词匹配或展示误认为这首 Track 原本来自某外部平台。
- 可能造成的影响：歌词 direct fetch 映射错误、搜索结果对象状态不可预测、导入预览选择切换后旧对象保留 originalSource。
- 推荐修改方向：在 `selectedTracks` 中复制 `Track` 后再写入原平台 ID，或在创建 matched result 时构造独立导入 Track。
- 修改风险：Low-Medium。需确认 copy 是否保留必要字段。
- 是否值得立即处理：建议处理，改动小且降低隐式副作用。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 补 `selectedTracks` 不污染原对象测试；2) 改为 copy 后写字段；3) 回归导入歌单与歌词 direct fetch。

### 问题 7

- 等级：Medium
- 标题：Radio 与 AudioController 的共享播放器所有权仍依赖可变回调字段
- 影响模块：电台/音乐互斥、SMTC/通知栏控制权、返回队列
- 具体文件路径：`lib/services/radio/radio_controller.dart`、`lib/services/audio/audio_provider.dart`
- 关键代码位置：`radio_controller.dart:391-402` 写入 `audioController.onPlaybackStarting` 与 `isRadioPlaying`；`audio_provider.dart:1723-1724` 播放前回调停止电台；`radio_controller.dart:383-388` 反向恢复音乐媒体控制。
- 问题描述：电台和音乐共享底层播放器，目前通过互相读取 provider 和写回调字段实现互斥/忽略事件。
- 为什么这是问题：这是可工作的折中，但所有权协议不显式；初始化顺序、dispose、未来多模式播放都会扩大隐式依赖。
- 可能造成的影响：快速电台/歌曲切换时媒体控制权残留，或 AudioController 错误忽略/接收共享播放器事件。
- 推荐修改方向：保留当前 retained context / active ownership 语义，但提取小型 `PlaybackOwnershipCoordinator`，统一声明谁拥有共享播放器和媒体控制。
- 修改风险：High。涉及播放主链路，必须先补切换测试。
- 是否值得立即处理：不建议立刻大改；在扩展电台/后台媒体控制前处理。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 只抽接口不改行为；2) 覆盖电台到音乐/音乐到电台测试；3) 迁移回调字段；4) 清理旧互相依赖。

## 4. 复杂链路专项结论

- 播放队列/临时播放：`_PlaybackContext`、`TemporaryPlayHandler`、`_restoreQueuePlayback()` 的方向正确，建议保持；风险点主要是额外副作用（如恢复后 seek）是否也纳入 requestId 校验。
- Superseded request：`PlaybackRequestExecutor` 在 URL、headers、handoff、seek、resume 后都有检查，主链路较稳；新增任何独立 await 副作用都应遵守同一规则。
- URL 获取与失败恢复：统一 `SourceApiException` 是正确方向；立即修复 expiry 使用不一致。
- 下载：isolate 和 setup-window cancel 设计合理；后续重点是完成阶段可恢复一致性与媒体 headers。
- 歌词/导入：原始平台 ID 直取歌词是高价值设计；需要避免 selectedTrack 原地污染并补测试。
- 登录态/鉴权播放：播放侧 headers 比下载侧更完整，下载需追平。
- 多窗口/单实例/更新：选择性插件注册和歌词窗口隐藏复用值得保持；更新 ZIP 解压需补安全边界。

## 5. 当前合理折中 / 建议保持不动的点

- 不建议重写 `AudioController` 播放请求机制；现有 requestId + executor + context 是稳定性基础。
- Windows 下载使用 isolate、进度走内存而不是高频写 Isar，是正确折中。
- 歌词窗口 hide-instead-of-destroy 生命周期符合项目已知插件问题，不应改回频繁销毁。
- 歌单重命名不自动移动文件夹，保持用户主导，稳定性优先。
- `SourceApiException` 统一错误语义值得保持，新增 source 应继续接入。