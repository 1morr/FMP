# FMP 系统级 Code Review / Technical Audit 总汇总

## 1. 审查来源与总体结论

本汇总整合以下专项报告：

- `docs/review/architecture_review.md`
- `docs/review/consistency_review.md`
- `docs/review/performance_memory_review.md`
- `docs/review/stability_review.md`
- `docs/review/platform_review.md`
- `docs/review/database_review.md`
- `docs/review/testing_review.md`

本次审查结论：项目主架构方向正确，音频平台拆分、UI 只经 `AudioController`、`QueueManager` 不直接操作播放器、Source 异常统一、下载 isolate、歌词窗口隐藏复用、Isar watch/FutureProvider 分工等设计值得保持。当前主要风险不是“架构失败”，而是若干跨模块链路的默认值、过期时间、事务一致性、平台边界和大列表性能问题。这些问题大多可以按阶段小步修复，不建议进行一次性大规模重构。

静态验证依据：本轮审查中执行过 `flutter analyze`，输出为 `No issues found!`。

## 2. 各部门结论摘要

| 专项 | 结论摘要 |
|---|---|
| 架构与目录结构 | 三层音频架构和 UI 边界基本清晰；主要技术债是 `AudioController`、`RadioController`、部分页面和 Source 实例所有权偏厚/分散。 |
| 逻辑一致性与可维护性 | 主干一致性较好；局部存在 build 中触发文件检查、图片尺寸提示遗漏、`ListTile.leading Row`、搜索历史双入口、动作 handler 样板重复。 |
| 性能与内存 | 已有图片统一、下载 isolate、进度内存化等优化；高优先级问题集中在 `PlayerState.queue` 高频传播、播放历史全量快照、热路径日志和大列表/文件扫描。 |
| 稳定性与潜在缺陷 | 播放请求竞态主链路较稳；主要风险是播放 URL expiry、恢复后 seek 取代校验、Windows 更新 ZIP 解压、下载 headers/完成一致性、导入原始 ID 副作用。 |
| 平台与专项功能 | Android/Windows 分层合理；需优先修复 Android 存储权限版本判断、Windows portable 更新安全/鲁棒性、单实例 tray 唤醒和歌词窗口 close fallback。 |
| 数据层与数据库一致性 | Settings/Queue 默认修复基础较好；明确存在 `Track.isAvailable`、`Playlist.notifyOnUpdate` 默认迁移缺口，以及 Playlist/Track、DownloadTask/Track 跨集合事务一致性问题。 |
| 测试与回归风险 | 音频竞态、迁移、下载 race 已有测试；缺口集中在主播放 expiry、过期恢复 superseded、歌词 direct fetch、下载 provider glue 和 UI 规范静态防护。 |

## 3. 跨部门重复发现的核心问题

1. **音频 URL 有效期处理不一致**：稳定性、平台、测试都指出播放侧忽略 `AudioStreamResult.expiry`，下载侧已正确使用。
2. **下载链路播放/下载策略不一致**：平台、稳定性、数据库都指出下载实际请求 headers 与播放侧鉴权不一致，完成阶段 Track/Task 状态也非原子。
3. **大状态 / 大列表导致性能风险**：性能、架构、测试都指向 `PlayerState.queue` 高频耦合、历史列表全量快照、组内一次性构建。
4. **数据默认值与迁移规则需要严格执行**：数据库、测试都指出新增字段必须判断 Isar 默认值是否符合业务默认值。
5. **平台更新与权限边界是高风险小改动**：平台、稳定性均指出 Windows ZIP 路径穿越、Android 权限版本判断属于应立即处理的边界问题。
6. **复杂链路改动前需要测试护栏**：测试、稳定性、架构均建议先补播放/下载/歌词/迁移的最小回归测试，再做结构性拆分。

## 4. 最值得优先处理的前 10 个问题

| 优先级 | 问题 | 等级 | 主要文件 | 建议 |
|---|---|---|---|---|
| 1 | 播放侧忽略 `AudioStreamResult.expiry` | High | `lib/services/audio/internal/audio_stream_delegate.dart` | 先补测试，再改为使用 source expiry。 |
| 2 | 过期 URL 恢复后延迟 seek 缺少 superseded/track 校验 | High | `lib/services/audio/audio_provider.dart` | 补快速切歌回归测试后修复。 |
| 3 | Windows portable ZIP 解压缺少路径穿越防御 | High | `lib/services/update/update_service.dart` | 增加规范化路径校验和恶意 ZIP 测试。 |
| 4 | Android 11+ 存储权限判断可能误判旧系统 | High | `lib/services/storage_permission_service.dart` | 改用可靠 SDK 版本判断。 |
| 5 | `Track.isAvailable = true` 迁移缺口 | High | `lib/data/models/track.dart`, `lib/providers/database_provider.dart` | 增加签名式迁移和测试。 |
| 6 | Playlist 与 Track 双向关系更新非原子 | High | `lib/services/library/playlist_service.dart` | 跨集合操作合并为同一 Isar 事务。 |
| 7 | `PlayerState.queue` 与 position 高频更新耦合 | High | `lib/services/audio/player_state.dart`, `audio_provider.dart` | 队列结构拆为低频 provider 或 queue state。 |
| 8 | 播放历史全量 1000 条快照 + 日内记录一次性构建 | High | `play_history_provider.dart`, `play_history_page.dart` | 分用途分页查询，flatten sliver rows。 |
| 9 | 下载媒体请求 headers 未复用播放鉴权策略 | Medium | `lib/services/download/download_service.dart` | 抽媒体 headers helper，逐源验证。 |
| 10 | `TrackRepository.save()` 热路径构造 StackTrace/大量 debug 字符串 | High | `lib/data/repositories/track_repository.dart` | 删除或 feature-flag 诊断日志。 |

## 5. 必须改 / 可以延期优化 / 建议保持不动

### 必须改

- `AudioStreamDelegate.ensureAudioStream()` 使用 `streamResult.expiry`。
- `_resumeWithFreshUrlIfNeeded()` 延迟 seek 前增加当前请求/当前 track 校验。
- Windows ZIP 解压加入路径穿越校验。
- Android 存储权限版本判断改为可靠 SDK 判断。
- `Track.isAvailable` 与 `Playlist.notifyOnUpdate` 迁移缺口评估并补修复。
- Playlist/Track 双向关系和下载完成 Track/Task 写入尽量合并事务。
- 下载实际媒体请求 headers 与播放侧策略对齐。
- 删除或 gate `TrackRepository.save()` 中的 StackTrace 热路径日志。

### 可以延期优化

- `PlayerState.queue` 拆分为低频 queue provider。
- 播放历史查询分页化与 UI 扁平懒加载。
- `FileExistsCache` 增加 negative cache。
- 下载管理页改为 header/item flatten builder。
- 已下载分类详情扫描迁移到 isolate。
- Source 实例所有权收敛到 `SourceManager` / Provider。
- `TrackActionHandler` 页面样板进一步收拢。
- 搜索结果混排 getter memoize 或 build 内复用。
- `RadioController` / `AudioController` 提取共享播放所有权协调器。

### 建议保持不动

- Android 使用 `JustAudioService`、桌面使用 `MediaKitAudioService` 的平台拆分。
- UI 通过 `AudioController`，不直接调用 `AudioService`。
- `QueueManager` 只管队列、shuffle、loop、持久化，不直接操作播放器。
- `_PlaybackContext` + `_playRequestId` + `PlaybackRequestExecutor` 的播放竞态治理方向。
- `SourceApiException` 统一错误语义。
- Windows 下载 isolate + 下载进度内存化。
- 歌词窗口 hide-instead-of-destroy 生命周期。
- Windows 子窗口选择性插件注册，继续排除有全局 channel 风险的插件。
- 歌单重命名不自动移动文件夹。
- Isar watch / FutureProvider / 乐观更新按数据来源分工的模式。

## 6. 可立即落地的修复清单

1. 为主播放 expiry 写测试并修复 `audio_stream_delegate.dart`。
2. 为过期 URL 恢复写 superseded seek 测试并修复 `_resumeWithFreshUrlIfNeeded()`。
3. 为 Windows ZIP 解压添加安全路径函数与测试。
4. Android 存储权限逻辑改为 SDK int 判断。
5. 删除 `TrackRepository.save()` 默认 StackTrace 日志。
6. 将 `DownloadPathManager.saveDownloadPath()/clearDownloadPath()` 改为 `SettingsRepository.update()`。
7. 为缺尺寸的 `ImageLoadingService.loadImage()` 调用补 `width/height/targetDisplaySize`。
8. 删除或合并未使用的 `searchHistoryProvider`。
9. 给 `CoverPickerDialog` 和导入预览展开项补稳定 `ValueKey`。
10. 为 `AudioStreamResult.expiry`、歌词 direct fetch、下载 provider completion/failure glue 补最小测试。

## 7. 可延后处理的技术债清单

- `AudioController` 继续小步拆分 provider wiring、retry policy、media control binder，而不是一次性重写。
- 远程歌单移除/同步逻辑从 `playlist_detail_page.dart` 提取到应用服务。
- `YouTubeSource` / Source 实例创建收敛，避免 Mix/排行榜/导入直接 new Source。
- 播放历史 repository 查询层增加索引/分页/日期范围查询。
- 下载本地同步从逐条 save 改为批量 `putAll`。
- `FileExistsCache` 引入有 TTL 的 missing-path cache。
- `ListTile.leading Row` 残留页面改为扁平行布局。
- `currentTrack` 兼容命名逐步迁移为显式 `playingTrackProvider` / `queueTrackProvider`。
- Account/PlayQueue/DownloadTask/Track 唯一性增加扫描修复和索引策略。
- 备份/恢复覆盖 `ownerName`、`ownerUserId`、`useAuthForRefresh`、`isVip`、`isAvailable`、`bilibiliAid` 等当前字段。

## 8. 建议保持不动的设计清单

- 平台音频后端拆分和 `MediaKit.ensureInitialized()` 仅桌面调用。
- just_audio 的 `unawaited(_player.play())` 时序折中。
- 下载进度不高频写 Isar。
- 关闭歌词窗口时隐藏而不是销毁。
- Windows 全局快捷键串行同步 `_syncHotkeys()`。
- 电台 retained context 与 active ownership 的语义拆分。
- 下载路径重命名不自动移动文件的安全策略。
- 迁移规则继续遵循“Isar 默认值与业务默认值不一致才修复”。

## 9. 整体重构路线图

### Phase 1：低风险高收益修复

- 目标：先消除明确缺陷和安全/平台边界问题。
- 涉及模块：音频 URL、更新系统、Android 权限、TrackRepository 日志、Settings 更新、图片尺寸、ValueKey。
- 前置依赖：为主播放 expiry、过期恢复 seek、ZIP 解压、迁移默认值补最小测试。
- 推荐顺序：expiry → seek guard → ZIP path traversal → Android 权限 → 热路径日志 → UI 小一致性。
- 预期收益：降低播放恢复失败、更新安全风险、Android 下载目录失败和批量操作卡顿。
- 风险说明：多数是小改动；播放恢复和权限流程需真实设备/场景验证。

### Phase 2：逻辑统一与重复代码清理

- 目标：统一同类逻辑入口，减少页面层和服务层重复。
- 涉及模块：下载 headers、远程歌单动作、TrackActionHandler、search history、FileExistsCache、备份字段。
- 前置依赖：下载 provider completion/failure、歌词 direct fetch、导入 selectedTracks 测试。
- 推荐顺序：下载 headers helper → search history 单入口 → selectedTracks copy → remote playlist action service → FileExistsCache negative cache。
- 预期收益：降低“能播放不能下载”、歌词映射污染、状态入口混乱和重复样板。
- 风险说明：需逐源验证 headers，避免把 API Cookie 无脑传给不需要的 CDN。

### Phase 3：结构性重构

- 目标：处理大状态/大页面/跨集合一致性等结构性技术债。
- 涉及模块：`PlayerState.queue`、播放历史、Playlist/Track 事务、DownloadTask/Track 完成事务、SourceManager ownership、`AudioController` 局部拆分。
- 前置依赖：播放、下载、迁移和历史页测试护栏。
- 推荐顺序：Playlist/Track 事务 → Download 完成事务 → 播放历史分页/flatten → queue state 拆分 → Source 注入收敛 → AudioController provider wiring/retry 小拆分。
- 预期收益：提升大队列、大历史、大下载场景稳定性和维护性。
- 风险说明：跨模块影响较大，不建议与功能开发混在同一批提交。

### Phase 4：长期优化项

- 目标：进一步降低内存、I/O 和平台边界维护成本。
- 涉及模块：歌词 line index provider、已下载详情 isolate 扫描、下载管理页 builder、日志策略、Account/PlayQueue 唯一性、Radio/Audio ownership coordinator。
- 前置依赖：稳定的 benchmark / smoke 测试与真实设备验证。
- 推荐顺序：下载/历史大列表优化 → 歌词 rebuild 优化 → 唯一性扫描修复 → ownership coordinator。
- 预期收益：长期运行更稳、低端设备更流畅、平台扩展更安全。
- 风险说明：收益依赖用户数据规模和使用场景；避免为了“架构更漂亮”过早重构。