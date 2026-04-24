# 数据库与数据层审查报告

## 1. 审查范围

- 项目指导与补充记忆：`CLAUDE.md`、`.serena/memories/code_style.md`、`download_system.md`、`refactoring_lessons.md`、`ui_coding_patterns.md`、`update_system.md`。
- Isar 模型：`lib/data/models/*.dart`，并按需核对生成文件 `*.g.dart` 的 schema、索引与反序列化行为。
- 迁移与默认值：`lib/providers/database_provider.dart`。
- Repository / Provider / Service 数据访问链路：`lib/data/repositories/*.dart`、`lib/providers/*`、`lib/services/library/playlist_service.dart`、`lib/services/download/*`、`lib/services/radio/*`、`lib/services/backup/*`。

## 2. 总体结论

整体数据层已经形成了较清晰的模式：Settings 单例、Queue 单例、Playlist/Track 反向关联、DownloadTask 按 `savePath` 去重、播放历史和下载列表使用 watch/StreamProvider，主路径没有发现会立即导致数据库不可打开的结构性问题。

但仍有几类值得处理的风险：

- 少数字段的业务默认值与 Isar 升级默认值不一致，当前迁移未覆盖。
- Playlist 与 Track、DownloadTask 与 Track 等跨集合写入仍有多处拆成多个事务，异常或崩溃时可能留下半更新状态。
- Track、DownloadTask、Account、PlayQueue 的“逻辑唯一性”主要靠应用层约定，数据库层缺少唯一索引或重复修复。
- 备份/恢复没有覆盖部分当前模型字段，恢复后会丢失导入歌单认证刷新、所有者、VIP/不可用等信息。

## 3. 发现的问题列表

### 1. 等级：高
- 标题：`Track.isAvailable` 新字段升级默认值与业务默认值不一致
- 影响模块：Track 可用性、未来基于可用性过滤/跳过的逻辑
- 具体文件路径：`lib/data/models/track.dart`、`lib/providers/database_provider.dart`
- 关键代码位置：`lib/data/models/track.dart:87`，`lib/providers/database_provider.dart:158`
- 问题描述：模型声明 `bool isAvailable = true`，但迁移只备注了 `bilibiliAid` 无需迁移，没有修复旧库中新加入非空 bool 字段会落成 `false` 的情况。
- 为什么这是问题：Isar 升级新 bool 字段默认是 `false`，而业务模型默认是“可用”。
- 可能造成的影响：旧数据在升级后可能被视为不可用；目前使用点不多，但后续一旦用该字段过滤播放/显示，会出现历史歌曲被误判。
- 推荐修改方向：在 `_initializeDatabaseDefaultsInTxn()` 中增加一次性或签名式修复；只修复没有 `unavailableReason`、且不像显式标记不可用的旧记录。
- 修改风险：中；需要避免覆盖用户/业务已经标记为不可用的歌曲。
- 是否值得立即处理：是，属于典型默认值迁移缺口。
- 分类：迁移 / 默认值。
- 如果要改建议拆成几步执行：1) 定义旧数据识别条件；2) 添加迁移修复；3) 增加升级路径测试。

### 2. 等级：中
- 标题：`Playlist.notifyOnUpdate` 默认 `true` 但升级默认可能为 `false`
- 影响模块：导入歌单自动刷新通知
- 具体文件路径：`lib/data/models/playlist.dart`、`lib/providers/database_provider.dart`
- 关键代码位置：`lib/data/models/playlist.dart:37`，`lib/providers/database_provider.dart:54-156`
- 问题描述：`notifyOnUpdate` 的业务默认是 `true`，但数据库默认修复逻辑没有覆盖 Playlist。
- 为什么这是问题：旧版本升级后该字段可能为 `false`，与导入/创建路径默认通知的意图不一致。
- 可能造成的影响：旧导入歌单刷新后不提示更新，用户以为刷新没有变化。
- 推荐修改方向：为导入歌单添加默认修复；例如仅在 `sourceUrl != null` 且字段处于旧默认签名时设置为 `true`。
- 修改风险：中；直接全量置 true 会覆盖用户关闭通知的选择。
- 是否值得立即处理：建议处理，但需签名条件谨慎。
- 分类：迁移 / 默认值。
- 如果要改建议拆成几步执行：1) 确认该字段引入版本；2) 设计旧数据签名；3) 添加测试覆盖用户关闭通知不被覆盖。

### 3. 等级：高
- 标题：Playlist 与 Track 的双向关系更新不是原子事务
- 影响模块：歌单增删、批量增删、刷新导入歌单、重命名清理下载路径
- 具体文件路径：`lib/services/library/playlist_service.dart`、`lib/services/import/import_service.dart`
- 关键代码位置：`lib/services/library/playlist_service.dart:283-307`、`372-391`、`405-440`，`lib/services/import/import_service.dart:532-571`
- 问题描述：多个路径会先写 Track 再写 Playlist，或先改 Playlist 再改 Track，分别通过 repository 开启独立事务。
- 为什么这是问题：Playlist.trackIds 与 Track.playlistInfo 是双向冗余关系，必须保持一致；拆事务时任一步失败都会留下半更新。
- 可能造成的影响：歌单显示缺歌、Track 保留孤儿 playlistInfo、下载路径归属错误、封面和详情 provider 刷新后状态不一致。
- 推荐修改方向：在 service 层对同一业务操作使用单个 `_isar.writeTxn()` 同时更新 Playlist 和 Track；repository 保留细粒度 CRUD，但跨集合一致性由 service 保证。
- 修改风险：中高；涉及多个调用路径，需要保证现有乐观 UI 回滚逻辑仍然成立。
- 是否值得立即处理：是，属于核心数据一致性问题。
- 分类：事务一致性 / 冗余关系维护。
- 如果要改建议拆成几步执行：1) 先改单首添加/移除；2) 再改批量和刷新；3) 最后补一致性修复工具和测试。

### 4. 等级：中
- 标题：Track 逻辑唯一性缺少数据库约束，且 `cid == null` 查询可能匹配错误记录
- 影响模块：Track 去重、分 P、下载同步、备份恢复
- 具体文件路径：`lib/data/models/track.dart`、`lib/data/repositories/track_repository.dart`
- 关键代码位置：`lib/data/models/track.dart:268-276`、`323-326`，`lib/data/repositories/track_repository.dart:61-80`、`329-419`
- 问题描述：`sourceId/sourceType/cid` 只建立普通索引，没有唯一索引；`getBySourceIdAndCid()` 在 `cid == null` 时退化为 `sourceId + sourceType` 的第一条。
- 为什么这是问题：同一源同一 sourceId 的多条记录一旦因历史数据、并发导入或 pageNum 兜底出现，后续查询会拿到任意第一条。
- 可能造成的影响：添加到歌单的是错误分 P；下载同步把路径写到错误 Track；备份恢复去重不稳定。
- 推荐修改方向：明确 Track 的稳定唯一键，优先使用 `sourceType + sourceId + cid`，无 cid 时再结合 `pageNum`；增加唯一索引或启动时重复修复。
- 修改风险：高；需要先迁移/合并历史重复数据，避免唯一索引构建失败。
- 是否值得立即处理：建议作为独立数据修复任务处理。
- 分类：索引 / 去重 / 查询正确性。
- 如果要改建议拆成几步执行：1) 写只读重复扫描；2) 设计合并规则；3) 加唯一约束或更精确查询；4) 覆盖导入、下载同步、备份恢复测试。

### 5. 等级：中
- 标题：DownloadTask 按 `savePath` 去重但索引非唯一，完成落库也非原子
- 影响模块：下载队列、下载完成状态、已下载标记
- 具体文件路径：`lib/data/models/download_task.dart`、`lib/data/repositories/download_repository.dart`、`lib/services/download/download_service.dart`
- 关键代码位置：`lib/data/models/download_task.dart:38`，`lib/data/models/download_task.g.dart:105-117`，`lib/services/download/download_service.dart:356-374`、`764-773`
- 问题描述：任务去重依赖先查再插，`savePath` 索引不是 unique；下载完成时先写 Track.downloadPath，再单独更新 DownloadTask.completed。
- 为什么这是问题：并发添加同一路径可能产生重复任务；完成阶段崩溃可能留下 Track 已下载但任务仍 paused/downloading 的状态。
- 可能造成的影响：下载管理页出现重复任务、重启后显示已下载歌曲还有未完成任务、用户重复下载同一文件。
- 推荐修改方向：考虑 `savePath` 唯一索引；下载完成后的 Track 路径更新与任务状态更新放入同一 DB 事务。
- 修改风险：中；加唯一索引前需要清理历史重复任务。
- 是否值得立即处理：建议处理，尤其是唯一性和完成状态一致性。
- 分类：索引 / 事务一致性。
- 如果要改建议拆成几步执行：1) 扫描重复 savePath；2) 清理重复未完成任务；3) 添加唯一约束；4) 合并完成阶段 DB 事务。

### 6. 等级：中
- 标题：备份/恢复未覆盖部分当前模型字段
- 影响模块：备份恢复、导入歌单、Track 元数据
- 具体文件路径：`lib/services/backup/backup_service.dart`、`lib/services/backup/backup_data.dart`
- 关键代码位置：`lib/services/backup/backup_service.dart:102-117`、`120-139`、`388-405`、`335-351`
- 问题描述：Playlist 备份缺少 `ownerName`、`ownerUserId`、`useAuthForRefresh`；Track 备份缺少 `isVip`、`isAvailable`、`unavailableReason`、`bilibiliAid` 等当前字段。
- 为什么这是问题：备份恢复应保留用户可见或业务相关的数据；当前恢复后部分语义会回到模型默认值。
- 可能造成的影响：恢复后的导入歌单丢失所有者展示和认证刷新设置；网易云 VIP 标记、不可用状态、Bilibili aid 缓存丢失。
- 推荐修改方向：扩展 backup schema，读取旧备份时提供兼容默认值；导入时写回对应模型字段。
- 修改风险：低中；JSON schema 向后兼容即可。
- 是否值得立即处理：值得，修复成本较低。
- 分类：备份一致性 / 字段覆盖。
- 如果要改建议拆成几步执行：1) 扩展 Backup DTO；2) 导出新字段；3) 导入兼容旧字段缺失；4) 增加恢复测试。

### 7. 等级：中
- 标题：Settings 已有原子 update，但下载路径仍使用 get+save 全量覆盖
- 影响模块：设置页、下载路径维护
- 具体文件路径：`lib/data/repositories/settings_repository.dart`、`lib/services/download/download_path_manager.dart`
- 关键代码位置：`lib/data/repositories/settings_repository.dart:25-38`，`lib/services/download/download_path_manager.dart:65-83`
- 问题描述：大多数设置更新已使用 `SettingsRepository.update()`，但 `DownloadPathManager.saveDownloadPath()` / `clearDownloadPath()` 仍读取整个 Settings 后全量保存。
- 为什么这是问题：多个 Notifier/服务持有 Settings 副本时，全量保存可能覆盖其他刚更新的字段；项目已经在 repository 注释中承认此竞态。
- 可能造成的影响：用户同时修改下载目录和音频/歌词/桌面设置时，后保存的一方覆盖先保存的一方。
- 推荐修改方向：将下载路径保存改为 `settingsRepo.update((s) => s.customDownloadDir = path/null)`。
- 修改风险：低。
- 是否值得立即处理：是，改动小且与现有模式一致。
- 分类：并发更新 / 设置一致性。
- 如果要改建议拆成几步执行：1) 替换两处 save；2) 回归下载路径修改和设置页保存。

### 8. 等级：低
- 标题：Account / PlayQueue 单例或平台唯一性只靠应用层约定
- 影响模块：账号状态、播放队列恢复
- 具体文件路径：`lib/data/models/account.dart`、`lib/services/account/*_account_service.dart`、`lib/data/repositories/queue_repository.dart`
- 关键代码位置：`lib/data/models/account.dart:14-16`，`lib/services/account/bilibili_account_service.dart:567-583`，`lib/data/repositories/queue_repository.dart:11-23`
- 问题描述：Account.platform 没有唯一索引，PlayQueue 也允许多行；服务通常取第一条。
- 为什么这是问题：正常路径不容易产生重复，但恢复、历史 bug 或并发写入后，读取“第一条”会变得不确定。
- 可能造成的影响：账号 UI 与实际服务读取的账号不一致；队列恢复到旧行。
- 推荐修改方向：添加启动修复去重；后续可考虑 Account.platform unique index、PlayQueue 固定 id 或清理多余行。
- 修改风险：中；需要定义保留哪条记录。
- 是否值得立即处理：不紧急，但适合放入数据修复任务。
- 分类：唯一性 / 数据修复。
- 如果要改建议拆成几步执行：1) 扫描重复；2) 保留最新登录/最新更新记录；3) 删除或合并重复；4) 再考虑唯一约束。

### 9. 等级：低
- 标题：部分计算型 getter 被生成进 Isar schema，存在冗余或陈旧查询风险
- 影响模块：Track、Playlist、RadioStation schema
- 具体文件路径：`lib/data/models/track.dart`、`lib/data/models/playlist.dart`、`lib/data/models/radio_station.dart` 及生成文件
- 关键代码位置：`lib/data/models/track.g.dart:59-72`、`130-164`，`lib/data/models/playlist.g.dart:45-79`、`110-114`，`lib/data/models/radio_station.g.dart:80-84`
- 问题描述：`formattedDuration`、`hasValidAudioUrl`、`isImported`、`needsRefresh`、`trackCount`、`uniqueKey` 等 getter 没有全部标注 `@ignore`，因此被序列化为属性。
- 为什么这是问题：部分 getter 依赖当前时间或其他字段，持久化值可能陈旧；未使用的计算属性也增加 schema 噪音。
- 可能造成的影响：如果未来直接查询这些属性，可能得到写入时快照而不是实时计算结果。
- 推荐修改方向：只保留刻意用于索引的计算字段；其他纯展示/动态 getter 标注 `@ignore` 并重新生成。
- 修改风险：中；改 schema 需确认没有外部查询依赖。
- 是否值得立即处理：不急，建议作为 schema 清理。
- 分类：schema 清理 / 生成代码。
- 如果要改建议拆成几步执行：1) 搜索生成查询调用；2) 标注 @ignore；3) build_runner；4) analyzer/test。

### 10. 等级：低
- 标题：Radio 后台刷新保存未 await，watch 更新和错误处理不确定
- 影响模块：电台列表、后台刷新、Isar watch 同步
- 具体文件路径：`lib/services/radio/radio_refresh_service.dart`
- 关键代码位置：`lib/services/radio/radio_refresh_service.dart:88-119`
- 问题描述：刷新电台信息时调用 `repository.save(station)` 但没有 `await`。
- 为什么这是问题：保存失败不会进入当前 try/catch；`_notifyStateChange()` 可能早于数据库 watch 更新，调用者看到缓存和 DB 状态短暂不一致。
- 可能造成的影响：刷新后的封面/标题偶发不落库，或 UI 状态顺序不稳定。
- 推荐修改方向：改为 `await repository.save(station)`；必要时批量收集后 `saveAll`。
- 修改风险：低。
- 是否值得立即处理：建议顺手处理。
- 分类：异步写入 / watch 同步。
- 如果要改建议拆成几步执行：1) await 单条保存；2) 观察刷新耗时；3) 如有性能问题再改批量保存。

## 4. 迁移与默认值专项结论

- Settings 的大部分非 Isar 默认字段已有修复：并发下载数、缓存大小、音质/图片/歌词索引、源优先级、刷新间隔、`useNeteaseAuthForPlay`、`lastVolume` 等逻辑基本合理。
- 不需要迁移的字段示例：`Track.isVip = false`、`Playlist.hasCustomCover = false`、`useBilibiliAuthForPlay = false`、`useYoutubeAuthForPlay = false`、nullable 字段默认 `null`，这些与 Isar 默认一致。
- 当前明确缺口：`Track.isAvailable = true`、`Playlist.notifyOnUpdate = true`。这两个字段的业务默认值与 Isar bool 默认 `false` 不一致，应补迁移或签名式修复。
- `DateTime createdAt/playedAt/timestamp/matchedAt` 多为创建时赋值；若这些字段历史上是新增字段，也需要单独确认旧库升级表现，但本次未找到当前迁移对它们的专门修复。
- 迁移函数集中在 `initializeDatabaseDefaults()` / `_initializeDatabaseDefaultsInTxn()`，方向正确；建议继续保持“仅当 Isar 默认与业务默认不一致才迁移”的规则。

## 5. watch/query/update 模式专项结论

- Playlist 列表、Radio 列表、DownloadTask、PlayHistory 快照等使用 watch/StreamProvider 的方向合理；UI 层的 `invalidate` 与静默刷新也基本遵循项目记忆中的模式。
- PlaylistDetail 采用 StateNotifier + 乐观更新是合理折中，因为它是 Playlist + Tracks 的联合查询；但底层 service 需要用事务保证乐观更新背后的双向关系一致。
- SettingsRepository 的 `update()` 是正确模式，能避免多 Notifier 全量覆盖；应把剩余 `get()+save()` 设置写入迁移到该模式。
- Query 风险主要集中在 Track identity：已有索引能加速查询，但缺少唯一约束和 `cid == null` 的精确匹配策略。
- Download 进度保存在内存、完成/失败/暂停再落库的模式合理，避免 Isar watch 高频重建；但完成阶段的多集合 DB 更新仍应合并事务。

## 6. 当前合理折中 / 建议保持不动的点

- `Track.isVip = false` 无需迁移，符合 Isar 默认和业务默认。
- `bilibiliAid` 为 nullable 且按需填充，无需迁移。
- `useNeteaseAuthForPlay`、`neteaseStreamPriority`、`enabledSources` 的旧数据签名修复比全量覆盖更安全，建议保持这种写法。
- 下载进度不写数据库、只通过内存 provider 推送 UI，是避免 Windows PostMessage 与 Isar watch 抖动的合理折中。
- 歌单详情页不强行改成 watch 全量联表，而采用分页 + 乐观更新，符合当前性能和 UI 需求。
- 歌单重命名时不自动移动文件，只清理下载路径并提示用户手动迁移，符合项目已记录的安全策略。
