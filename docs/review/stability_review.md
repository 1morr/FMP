# 稳定性审查报告

## 审查范围
- 文档：`CLAUDE.md`、`docs/development.md`、`docs/comprehensive-analysis.md`、`.serena/memories/audio_system.md`、`.serena/memories/database_migration.md`、`.serena/memories/download_system.md`、`.serena/memories/lyrics_matching_exploration.md`、`.serena/memories/architecture.md`
- 核心代码：
  - 播放与队列：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\playback_request_executor.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\queue_manager.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_stream_manager.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart`
  - 下载：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_path_sync_service.dart`
  - 歌词/导入/账号：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\lyrics\lyrics_auto_match_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\import\playlist_import_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\bilibili_account_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\youtube_account_service.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\netease_account_service.dart`
  - 数据层：`C:\Users\Roxy\Visual Studio Code\FMP\lib\data\models\track.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\data\repositories\track_repository.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\data\repositories\download_repository.dart`
- 回归测试：`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_controller_phase1_test.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\playback_request_executor_test.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\temporary_play_handler_test.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\audio_stream_manager_test.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\test\services\download\download_service_phase1_test.dart`

## 总体结论
- 本次稳定性审查确认了 6 个实质性问题，其中 High 2 个、Medium 4 个，没有确认到需要标为 Critical 的已知缺陷。
- 风险最高的三个问题都是真实运行链路问题，而不是理论优化项：
  1. 网易云音频 URL 在播放/下载链路里被错误视为 1 小时有效；
  2. 下载断点续传在收到 `200 OK` 全量响应时可能静默生成损坏文件；
  3. Shuffle 模式下队列拖拽不会同步 `_shuffleOrder`，会让可见队列和实际导航顺序分叉。
- 播放请求 superseded 控制、临时播放恢复建模、下载清理生命周期以及电台/音乐共享播放器所有权模型整体是稳的，建议保持现有设计方向。

## 发现的问题列表

说明：以下每条 finding 都显式包含 `必要时附关键代码位置` 与 `如果要改，建议拆成几步执行` 两个必填字段。

### 问题 1
- 严重级别：High
- 标题：网易云音频 URL 在播放/下载路径中被错误标记为 1 小时有效
- 影响模块：暂停后恢复播放、URL 过期刷新、下载后的 URL 元数据一致性、auth-for-play 边界
- 具体文件路径：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\netease_source.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
- 必要时附关键代码位置：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\internal\audio_stream_delegate.dart:65-73`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart:611-617`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\sources\netease_source.dart:28,85-87,352-355`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart:2200-2219`
- 问题描述：网易云源自身把音频 URL 定义为 16 分钟有效，但播放首次取流和下载取流都统一写成了 `DateTime.now().add(const Duration(hours: 1))`。
- 为什么这是问题：`Track.hasValidAudioUrl`、`_resumeWithFreshUrlIfNeeded()` 以及任何依赖 `audioUrlExpiry` 的刷新判断都会被误导，特别是“暂停较久后继续播放”这条链路会把已失效 URL 当成仍可用。
- 可能造成的影响：用户暂停网易云歌曲 20-50 分钟后点击继续播放，播放器可能直接拿过期 URL 恢复，表现为解码失败、无声或错误 toast，而不是先刷新 URL。
- 推荐修改方向：把 URL 过期时间统一收敛到 source 层返回值，或至少让 `AudioStreamResult` 带上过期时长；不要在 delegate / download service 中再硬编码 1 小时。
- 修改风险：中
- 是否值得立即处理：是
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：应立即修改
- 如果要改，建议拆成几步执行：
  1. 先把网易云播放取流和下载取流的过期时间来源统一到 `NeteaseSource`。
  2. 再检查 `Track.hasValidAudioUrl` 与 `_resumeWithFreshUrlIfNeeded()` 的行为是否与 16 分钟过期语义一致。
  3. 最后补覆盖“暂停较久后恢复播放”的回归测试。

### 问题 2
- 严重级别：High
- 标题：断点续传在服务端忽略 Range 并返回 `200 OK` 时会把整文件追加到临时文件尾部
- 影响模块：下载恢复、文件完整性、失败恢复
- 具体文件路径：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart`
- 必要时附关键代码位置：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart:1175-1191`
- 问题描述：存在续传位置时，isolate 总是发送 `Range`，并始终以 `FileMode.append` 打开文件；但代码只把 `>= 400` 视为错误，没有校验续传场景必须是 `206 Partial Content`。
- 为什么这是问题：如果 CDN/源站忽略 `Range` 返回完整文件的 `200 OK`，当前实现会把完整内容追加到残留的部分文件之后，最终生成损坏音频，但任务仍会进入成功路径。
- 可能造成的影响：下载完成但文件损坏、播放器无法播放、元数据/下载路径已写库导致 UI 误判为成功。
- 推荐修改方向：当 `resumePosition > 0` 时显式要求 `206`；若收到 `200`，应删除旧临时文件并从头重下，而不是 append。
- 修改风险：低到中
- 是否值得立即处理：是
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：应立即修改
- 如果要改，建议拆成几步执行：
  1. 在 isolate 下载函数中区分首次下载和续传下载的期望状态码。
  2. 续传收到 `200` 时删除旧临时文件并重新走全量下载，而不是继续追加。
  3. 补一个“服务端忽略 Range”的回归测试，验证不会再产出损坏文件。

### 问题 3
- 严重级别：Medium
- 标题：Shuffle 模式下允许拖拽重排，但 `move()` 不维护 `_shuffleOrder`
- 影响模块：队列导航、upcomingTracks、用户可见顺序一致性
- 具体文件路径：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\queue\queue_page.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\queue_manager.dart`
- 必要时附关键代码位置：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\queue\queue_page.dart:199-220,607-621`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart:1093-1098`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\queue_manager.dart:593-612,756-818`
- 问题描述：队列页始终允许长按拖拽；`AudioController.moveInQueue()` 直接调用 `QueueManager.move()`。但 `move()` 只改 `_tracks` 和 `_currentIndex`，完全不更新 `_shuffleOrder` / `_shuffleIndex`。
- 为什么这是问题：Shuffle 状态保存的是“索引顺序”，拖拽改变 `_tracks` 后，这些索引就不再代表同一批歌曲，接下来播放和“即将播放”列表会偏离用户刚刚看到的队列。
- 可能造成的影响：下一首错误、`upcomingTracks` 显示与真实导航不一致、重排后行为看起来随机失真。
- 推荐修改方向：二选一即可：
  1. Shuffle 开启时禁用拖拽重排；或
  2. 为 `move()` 增加 `_shuffleOrder` 的同步重映射逻辑并补测试。
- 修改风险：中
- 是否值得立即处理：是
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：应立即修改
- 如果要改，建议拆成几步执行：
  1. 先确认产品预期：Shuffle 时是否允许用户手动重排。
  2. 如果不允许，直接在队列页禁用拖拽；如果允许，就在 `QueueManager.move()` 中同步维护 `_shuffleOrder`。
  3. 补覆盖“Shuffle + drag-reorder + next/upcomingTracks”的回归测试。

### 问题 4
- 严重级别：Medium
- 标题：临时播放/电台返回的恢复链在异步 headers 获取后缺少 superseded 检查
- 影响模块：临时播放恢复、`returnFromRadio`、请求取代控制
- 具体文件路径：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_stream_manager.dart`
- 必要时附关键代码位置：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_provider.dart:664-673`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\audio_stream_manager.dart:171-191`
- 问题描述：`_restoreQueuePlayback()` 在 `await _audioStreamManager.getPlaybackHeaders(trackWithUrl)` 之后，会直接执行 `await _audioService.setUrl(...)`，直到之后才检查 `_isSuperseded(requestId)`。
- 为什么这是问题：如果恢复的是需要异步鉴权头的流，而这段等待期间用户又点了别的歌，旧恢复请求仍可能把 URL 交给播放器，再由新请求重新覆盖，形成短暂的错误 handoff。
- 可能造成的影响：快速切歌时偶发跳回旧歌、播放器状态闪动、恢复链干扰新请求。
- 推荐修改方向：像 `PlaybackRequestExecutor.execute()` 一样，在 headers await 之后、`setUrl()` 之前再做一次 superseded 检查。
- 修改风险：低
- 是否值得立即处理：否
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 在 `_restoreQueuePlayback()` 的 header await 之后补一次 `_isSuperseded(requestId)` 检查。
  2. 复用与主播放请求一致的中断日志与清理逻辑，避免恢复链成为例外路径。
  3. 补一个“恢复流程被新播放请求取代”的回归测试。

### 问题 5
- 严重级别：Medium
- 标题：无效下载路径清理会丢失 `playlistName`，破坏后续按名称匹配的下载语义
- 影响模块：下载路径同步、歌单重命名后的重新关联、每歌单下载状态判断
- 具体文件路径：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\repositories\track_repository.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_path_sync_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\models\track.dart`
- 必要时附关键代码位置：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\repositories\track_repository.dart:491-507`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_path_sync_service.dart:258-263`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\data\models\track.dart:98-115,173-185`
- 问题描述：`cleanupInvalidDownloadPaths()` 重建 `PlaylistDownloadInfo` 时只保留了 `playlistId` 与 `downloadPath`，没有复制 `playlistName`。
- 为什么这是问题：项目当前明确把 `playlistName` 作为下载路径匹配和同步的重要字段；清理一次无效路径后，后续 `getDownloadPath()` / `isDownloadedForPlaylist()` 的“按名称优先匹配”语义就被破坏。
- 可能造成的影响：某些歌单下明明有本地文件却不再显示已下载、同步后被错误归为未分类、歌单重命名后的人工迁移提示链条失真。
- 推荐修改方向：重建 embedded 对象时完整复制 `playlistId + playlistName + downloadPath`，并补一个 repository 级回归测试。
- 修改风险：低
- 是否值得立即处理：是
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：应立即修改
- 如果要改，建议拆成几步执行：
  1. 修正 `cleanupInvalidDownloadPaths()` 中 embedded 对象的重建逻辑，保留 `playlistName`。
  2. 检查同类路径清理代码是否也存在字段遗漏。
  3. 补一个 repository 级测试，验证清理后名称匹配语义仍然成立。

### 问题 6
- 严重级别：Medium
- 标题：网易云登录成功判定只要求 `MUSIC_U` 非空，页面成功回调并不等待实际鉴权通过
- 影响模块：登录边界、token/cookie 状态一致性、auth-for-play
- 具体文件路径：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\netease_account_service.dart`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\settings\netease_login_page.dart`
- 必要时附关键代码位置：
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\services\account\netease_account_service.dart:60-89,331-356`
  - `C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\settings\netease_login_page.dart:155-159,257-265`
- 问题描述：`loginWithCookies()` 只校验 `MUSIC_U` 非空就把账号写成 `isLoggedIn=true`；后续 `fetchAndUpdateUserInfo()` 如果鉴权失败只会内部记录日志，不会让登录页回滚“登录成功”。
- 为什么这是问题：这会把“拿到一个 cookie 字符串”和“该 cookie 真能通过网易云账号接口校验”混成一件事，登录态会先乐观落库。
- 可能造成的影响：用户被带回成功页，但播放时拿不到真正有效的鉴权头；直到后续状态检查或播放失败才暴露问题。
- 推荐修改方向：把登录成功判定提升为“cookie 保存 + `checkAccountStatus()` 验证通过”；登录页只在验证通过后触发成功回调。
- 修改风险：中
- 是否值得立即处理：否
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 让 `loginWithCookies()` 或登录页流程在持久化后立即执行一次账号有效性验证。
  2. 验证失败时回滚 `isLoggedIn` 状态并向页面返回失败，而不是只记录日志。
  3. 补一个“无效 MUSIC_U 不能被视为登录成功”的登录边界测试。

## 当前设计可接受 / 建议保持不动
- 主播放请求链的 supersession 设计是稳的：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\playback_request_executor.dart:37-97` 已在 URL 获取、headers 获取、handoff 后都做了 superseded 检查；`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\playback_request_executor_test.dart:99-160,198-264` 也覆盖了关键回归。
- 临时播放恢复目标的建模是稳的：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\audio\temporary_play_handler.dart:31-76` 保留原始队列目标，不会被二次临时播放覆盖；`C:\Users\Roxy\Visual Studio Code\FMP\test\services\audio\temporary_play_handler_test.dart:102-186` 已验证这点。
- 下载生命周期清理做得扎实：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\download\download_service.dart:806-838` 对 setup window、外部清理和 finally 清理有明确区分；`C:\Users\Roxy\Visual Studio Code\FMP\test\services\download\download_service_phase1_test.dart:128-159,262-335,337-451` 对这些竞态已有回归覆盖。
- Radio 与音乐共享播放器所有权模型建议保持：`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\radio\radio_controller.dart:344-355,377-439` 使用 `onPlaybackStarting` 与 `hasActivePlaybackOwnership` 的组合边界是合理的，不建议退回单一布尔状态。
