# FMP 当前重构坑点索引

此记忆只保留仍会影响当前开发的非显而易见坑点。它不是完整重构历史，也不保证覆盖所有近期改动；完整历史流水已归档到 `docs/history/refactoring-log.md`，但归档里有多轮修正和过时方案，不要把它当作当前实现规范。

使用优先级：
1. 当前代码和测试。
2. 根目录 `AGENTS.md`。
3. 此文件中的当前坑点索引。
4. `docs/history/refactoring-log.md` 只作为追溯背景。

## AudioController / 播放状态

- UI 只调用 `AudioController`。不要绕过它直接调用 `AudioService`。
- 有独立 URL 获取逻辑且不走 `_executePlayRequest()` 的方法，必须递增 `_playRequestId`，并在每个 `await` 后检查 `_isSuperseded(requestId)`。
- 加载态以 `_PlaybackContext.activeRequestId > 0` 为准。播放器 stream 事件不能覆盖仍在进行的手动加载请求。
- 临时播放、detached 播放、队列播放要通过 `PlayMode` / `_PlaybackContext` 区分，不要重新引入 `_isTemporaryPlay` 或 `_manualLoading` 之类的并行状态字段。
- `next()` / `previous()` / completion handler 需要判断完整的 out-of-queue 状态，而不是只看是否 temporary。
- `JustAudioService.playUrl()` / `playFile()` 不应等待 `just_audio.play()` 长时间阻塞；上层状态依赖 stream 更新和快速退出加载态。

## Riverpod / UI 状态

- 不要在 `build()` 期间修改 provider/state；把副作用放到事件回调，或必要时延后到 microtask。
- StateNotifier 页面使用 `isLoading` 时，UI 守卫应为 `isLoading && data.isEmpty`，避免刷新时闪屏。
- DB 集合且多处可写时优先用 Isar watch；DB join/特殊加载用 StateNotifier + 乐观更新；文件系统扫描用 FutureProvider + invalidate。
- FutureProvider 数据源被修改后必须 `ref.invalidate()` 对应 provider。
- StreamProvider 依赖用户可切换的筛选/排序状态时，`.when()` 要加 `skipLoadingOnReload: true`。
- 列表/网格项要使用稳定 `ValueKey(item.id)`。
- 涉及 playlist/detail/cover/download 的联动刷新，应优先通过 `libraryInvalidationCoordinatorProvider`。UI 不要手动猜要 invalidate 哪些 provider family。
- 排行榜 UI 要 watch 不可变的 `RankingCacheState`；刷新和 timer 操作通过 `rankingCacheServiceProvider.notifier`，不要读取 mutable service 快照列表。
- 歌词设置不要让 `audioControllerProvider` 重建。歌词相关 provider 应只 watch 自己需要的 setting/selectors。

## Source / Network

- 三个直接音源异常都应走 `SourceApiException` / `SourceErrorKind` 语义，不要在 `AudioController` 为单一 source 写孤立 catch 分支。
- 新增 source 错误语义时，要同步考虑 retry、skip、login、rate-limit、VIP、geo/network/timeout 行为。
- Source API/media header 默认值集中在 `SourceHttpPolicy`。源特有反限流、加密或账号细节留在 source/account service 内，不要把 header 拼接逻辑复制到下载或音频模块。

## Library / Download

- 下载任务按 `savePath` 去重，不按 trackId 去重。
- 下载完成并验证文件存在后，才写入 `Track.playlistInfo[].downloadPath`。
- `addTrackToPlaylist` 必须先从数据库拿最新 Track（如 `getOrCreate`），避免缓存旧对象覆盖最新 `playlistInfo`。
- 刷新导入歌单时，必须清理远端已移除歌曲在本地 Track 上的歌单关联。
- 歌单重命名不自动移动本地文件夹；清除关联后由用户手动移动并重新同步。
- Windows 下载进度优先保存在内存，完成/暂停/失败时再落 DB，避免 Isar watch 高频重建。
- Fire-and-forget 的 imported playlist refresh 要走命名 remote sync 路径，并用 `AppLogger` 记录后台失败。
- 远程歌单增删统一走 `RemotePlaylistEditController` / planner / result 类型。调用方要处理 partial success 和 local removal failure，不要只用 bool success/fail。

## Images / Local Files

- 图片加载走 `TrackThumbnail` / `TrackCover` / `ImageLoadingService`，不要直接用 `Image.network()` / `Image.file()`。
- `ImageLoadingService.loadImage()` 必须传 `width`/`height` 或 `targetDisplaySize`；否则 YouTube 小图可能被优化到不存在的 `maxresdefault.jpg`。
- 使用 FileExistsCache 时，Widget 要 `ref.watch(fileExistsCacheProvider)` 触发重建，再 `ref.read(fileExistsCacheProvider.notifier)` 查询缓存。
- 本地封面优先级：本地 `cover.jpg` -> `track.thumbnailUrl` -> placeholder。

## Windows Desktop

- `desktop_multi_window` 子窗口不能注册带全局 static channel 的插件。当前子窗口注册排除 `tray_manager` 和 `hotkey_manager`；新增插件时检查 Windows C++ 实现。
- 歌词子窗口关闭应 hide，不要 destroy，除非 app 退出。
- 全局快捷键注册/取消注册必须走统一串行同步管线，避免多个 provider 启动时互相覆盖 OS 状态。
- C++ 文件尽量保持 ASCII 注释，避免 MSVC/codepage 编码问题。

## Gesture / Layout

- 不要在 `ListTile.leading` 内放复合 `Row`，尤其是排名 + 缩略图；用扁平 `InkWell` + `Padding` + `Row` 自定义列表项。
- 扩大透明点击区域时，`SizedBox` 变大不等于 hit test 变大；对应 `GestureDetector` 常需要 `behavior: HitTestBehavior.opaque`。
- AppBar actions 如果最后一个是 `IconButton`，末尾加 `const SizedBox(width: 8)`；`PopupMenuButton` 结尾不需要。
