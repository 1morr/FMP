# FMP 数据库审查报告

## 审查范围

本审查覆盖以下内容：

1. **Isar 模型定义** (`lib/data/models/`)
   - Track, Playlist, PlayQueue, Settings, Account, DownloadTask, PlayHistory, RadioStation, LyricsMatch, SearchHistory

2. **数据库迁移逻辑** (`lib/providers/database_provider.dart`)
   - `_migrateDatabase()` 函数中的升级处理

3. **数据访问层** (`lib/data/repositories/`)
   - CRUD 操作、watch/query 模式、事务处理

4. **数据一致性风险**
   - 模型默认值与业务期望的对齐
   - 嵌入式对象 (@embedded) 的变更检测
   - 列表字段的可变性处理
   - 多写入场景下的竞态条件

5. **备份/恢复相关逻辑**
   - 数据持久化策略

---

## 总体结论

**整体评估：良好，但存在中等风险的设计缺陷**

### 优点
- 迁移逻辑完整，覆盖了大多数字段默认值不匹配的情况
- 使用 `SettingsRepository.update()` 原子操作解决了多 Notifier 竞态问题
- 列表字段操作正确使用 `List.from()` 创建可变副本
- @embedded 对象变更通过创建新对象确保 Isar 检测

### 风险
- **Settings 模型中存在多个新字段未在迁移中处理**（neteaseStreamPriority 等）
- **Track.bilibiliAid 的 nullable 设计可能导致业务逻辑混乱**
- **PlaylistDownloadInfo 嵌入式对象的复杂性增加了维护成本**
- **缺少对 Playlist.isMix 等新字段的迁移处理**
- **没有版本号机制，难以追踪迁移历史**

---

## 发现的问题列表

### 问题 1: Settings 新字段缺少迁移处理

**标题**: Settings 模型中 neteaseStreamPriority 等新字段未在迁移中初始化

**等级**: Medium

**影响模块**: 
- `lib/providers/database_provider.dart` (_migrateDatabase)
- `lib/data/models/settings.dart` (Settings 模型)

**具体文件路径**: 
- `lib/providers/database_provider.dart:114-117`
- `lib/data/models/settings.dart:140`

**问题描述**:
Settings 模型中的 `neteaseStreamPriority` 字段（第 140 行）在迁移逻辑中有处理（第 114-117 行），但其他新增的流优先级字段如果在未来添加，可能会被遗漏。当前迁移只处理了：
- audioFormatPriority
- youtubeStreamPriority
- bilibiliStreamPriority
- neteaseStreamPriority
- lyricsSourcePriority
- enabledSources

但如果添加新的流类型（如 "spotifyStreamPriority"），迁移逻辑需要同步更新。

**为什么这是问题**:
- 新字段添加时容易遗漏迁移处理
- 旧版本升级时新字段会是空字符串，业务逻辑需要处理空值
- 没有集中的字段初始化清单

**可能造成的影响**:
- 新增流优先级字段在升级后为空，导致流选择失败
- 用户体验下降（使用默认值而非预期值）
- 难以调试（字段值为空 vs 未初始化）

**推荐修改方向**:
1. 在 Settings 模型中添加一个 `_initializeDefaults()` 方法，集中管理所有字段的默认值
2. 在迁移逻辑中调用此方法，而不是逐个检查字段
3. 为 Settings 添加一个版本号字段，记录最后一次迁移的版本

**修改风险**: 低 - 只是重构迁移逻辑，不改变行为

**是否值得立即处理**: 建议列入后续重构计划

**分类**: 建议列入后续重构计划

**建议拆分步骤**:
1. 第一步：添加 Settings 版本号字段 (schemaVersion: int = 0)
2. 第二步：提取 Settings 默认值到常量或方法
3. 第三步：重构迁移逻辑使用版本号驱动的升级路径

---

### 问题 2: Track.bilibiliAid 的 nullable 设计导致业务逻辑复杂

**标题**: Track.bilibiliAid 为 nullable，但业务逻辑中的使用模式不清晰

**等级**: Medium

**影响模块**:
- `lib/data/models/track.dart` (Track 模型)
- `lib/services/` (使用 bilibiliAid 的服务)

**具体文件路径**:
- `lib/data/models/track.dart:245-246`
- `lib/providers/database_provider.dart:124-125` (迁移注释)

**问题描述**:
Track 模型中的 `bilibiliAid` 字段（第 245-246 行）是 nullable (`int?`)，注释说明它是"首次使用時從 view API 獲取並緩存"。但：
1. 没有明确的业务规则说明何时应该填充此字段
2. 没有检查此字段是否已被填充的方法
3. 迁移逻辑中明确说"No migration needed"，但没有说明旧数据如何处理

**为什么这是问题**:
- 调用方需要判断 `bilibiliAid != null` 来决定是否需要重新获取
- 如果字段为 null，不清楚是"未获取"还是"不存在"
- 可能导致重复的 API 调用或缺失的功能

**可能造成的影响**:
- 收藏夹导入功能可能因缺少 aid 而失败
- 不必要的 API 调用（每次都检查 null）
- 难以追踪数据完整性

**推荐修改方向**:
1. 添加一个 getter `bool get hasAid => bilibiliAid != null`
2. 添加一个方法 `Future<void> ensureAid()` 来按需获取
3. 在迁移中明确处理：对于 Bilibili 的 Track，如果 aid 为 null，标记为需要刷新

**修改风险**: 中等 - 需要检查所有使用 bilibiliAid 的地方

**是否值得立即处理**: 建议列入后续重构计划

**分类**: 建议列入后续重构计划

**建议拆分步骤**:
1. 第一步：添加 `hasAid` getter 和 `ensureAid()` 方法
2. 第二步：审计所有使用 bilibiliAid 的代码，替换为新方法
3. 第三步：在迁移中添加 Bilibili Track 的 aid 初始化逻辑

---

### 问题 3: PlaylistDownloadInfo 嵌入式对象的复杂性

**标题**: Track.playlistInfo 列表中的 PlaylistDownloadInfo 对象变更检测复杂且易出错

**等级**: Medium

**影响模块**:
- `lib/data/models/track.dart` (Track 和 PlaylistDownloadInfo)
- `lib/data/repositories/track_repository.dart` (Track 保存)

**具体文件路径**:
- `lib/data/models/track.dart:22-42` (PlaylistDownloadInfo 定义)
- `lib/data/models/track.dart:117-150` (setDownloadPath 等方法)
- `lib/data/models/track.dart:187-209` (clearDownloadPaths 等方法)

**问题描述**:
Track 模型中的 `playlistInfo` 是一个 `List<PlaylistDownloadInfo>` 嵌入式对象列表。为了让 Isar 检测到变更，代码中每个修改操作都需要：
1. 创建新的列表副本
2. 创建新的 PlaylistDownloadInfo 对象副本
3. 重新赋值给 `playlistInfo`

这导致：
- 代码重复（见第 117-150 行和 187-209 行）
- 易于遗漏（如果忘记创建新对象，Isar 不会检测到变更）
- 性能开销（每次修改都要复制整个列表）

**为什么这是问题**:
- Isar 的 @embedded 对象变更检测要求对象引用改变
- 当前实现在多个地方重复了相同的复制逻辑
- 如果添加新的修改方法，容易遗漏这个要求

**可能造成的影响**:
- 下载路径更新不被持久化（如果忘记创建新对象）
- 数据不一致（UI 显示已更新，但数据库未保存）
- 难以维护（每个修改方法都需要相同的样板代码）

**推荐修改方向**:
1. 提取一个 `_copyPlaylistInfo()` 辅助方法
2. 提取一个 `_updatePlaylistInfo()` 方法来统一处理修改逻辑
3. 考虑将 playlistInfo 的管理逻辑移到一个专门的类中

**修改风险**: 低 - 重构内部逻辑，不改变外部 API

**是否值得立即处理**: 建议列入后续重构计划

**分类**: 建议列入后续重构计划

**建议拆分步骤**:
1. 第一步：提取 `_copyPlaylistInfo()` 辅助方法
2. 第二步：重构所有修改方法使用新的辅助方法
3. 第三步：添加单元测试验证变更检测

---

### 问题 4: Playlist.isMix 等新字段缺少迁移处理

**标题**: Playlist 模型中的 isMix、mixPlaylistId 等新字段未在迁移中处理

**等级**: Low

**影响模块**:
- `lib/data/models/playlist.dart` (Playlist 模型)
- `lib/providers/database_provider.dart` (_migrateDatabase)

**具体文件路径**:
- `lib/data/models/playlist.dart:49-56` (Mix 相关字段)
- `lib/providers/database_provider.dart:22-133` (迁移逻辑中未处理 Playlist)

**问题描述**:
Playlist 模型中添加了 Mix 播放列表相关的字段：
- `isMix: bool = false`
- `mixPlaylistId: String?`
- `mixSeedVideoId: String?`

但迁移逻辑中没有对 Playlist 的任何处理。当旧版本升级时，这些字段会使用 Isar 的类型默认值（bool → false, String? → null），这恰好符合业务期望。

**为什么这是问题**:
- 虽然当前默认值符合期望，但这是巧合而非设计
- 如果未来修改这些字段的默认值，容易遗漏迁移处理
- 没有明确的文档说明"这些字段不需要迁移"

**可能造成的影响**:
- 低风险 - 当前默认值正确
- 但如果未来修改默认值，可能导致数据不一致

**推荐修改方向**:
1. 在迁移逻辑中添加对 Playlist 的显式处理（即使只是验证）
2. 添加注释说明为什么这些字段不需要迁移
3. 考虑在 Playlist 模型中添加一个 `schemaVersion` 字段

**修改风险**: 低 - 只是添加验证和注释

**是否值得立即处理**: 当前可接受

**分类**: 当前可接受

**建议拆分步骤**:
1. 第一步：在迁移逻辑中添加 Playlist 验证（可选）
2. 第二步：添加注释说明 Mix 字段的默认值处理

---

### 问题 5: 缺少数据库版本号机制

**标题**: 没有版本号字段，难以追踪迁移历史和调试升级问题

**等级**: Low

**影响模块**:
- `lib/data/models/settings.dart` (Settings 模型)
- `lib/providers/database_provider.dart` (迁移逻辑)

**具体文件路径**:
- `lib/providers/database_provider.dart:22-133` (迁移函数)

**问题描述**:
当前迁移逻辑通过检查字段值是否为默认值来判断是否需要升级。这种方法：
1. 无法区分"从版本 1 升级"和"从版本 2 升级"
2. 难以调试升级问题（不知道用户来自哪个版本）
3. 如果字段值恰好等于默认值，可能误判

**为什么这是问题**:
- 无法实现版本特定的迁移逻辑
- 难以支持跨多个版本的升级路径
- 无法生成升级日志或统计

**可能造成的影响**:
- 低风险 - 当前迁移逻辑相对简单
- 但随着功能增加，会变得难以维护

**推荐修改方向**:
1. 在 Settings 中添加 `schemaVersion: int = 0` 字段
2. 在迁移逻辑中根据版本号执行不同的升级路径
3. 每次迁移后更新版本号

**修改风险**: 低 - 只是添加新字段和版本检查

**是否值得立即处理**: 建议列入后续重构计划

**分类**: 建议列入后续重构计划

**建议拆分步骤**:
1. 第一步：添加 Settings.schemaVersion 字段
2. 第二步：重构迁移逻辑使用版本号驱动
3. 第三步：添加迁移日志记录

---

### 问题 6: SettingsRepository.update() 的原子性依赖于事务

**标题**: SettingsRepository.update() 虽然使用事务，但如果 mutate 函数抛异常，可能导致部分更新

**等级**: Low

**影响模块**:
- `lib/data/repositories/settings_repository.dart` (SettingsRepository)

**具体文件路径**:
- `lib/data/repositories/settings_repository.dart:26-39`

**问题描述**:
`update()` 方法使用 `writeTxn()` 确保原子性，但如果 `mutate()` 函数在修改过程中抛异常，事务会回滚。这是正确的行为，但：
1. 调用方可能不知道更新失败了
2. 没有重试机制
3. 异常会直接传播给调用方

**为什么这是问题**:
- 虽然事务保证了数据一致性，但调用方需要处理异常
- 如果调用方忽略异常，可能导致 UI 状态与数据库不同步

**可能造成的影响**:
- 低风险 - 这是正确的设计
- 但需要确保所有调用方都正确处理异常

**推荐修改方向**:
1. 添加文档说明 update() 可能抛异常
2. 在调用方添加异常处理
3. 考虑添加一个 `updateSafe()` 方法，返回 Result 类型

**修改风险**: 低 - 只是添加文档和异常处理

**是否值得立即处理**: 当前可接受

**分类**: 当前可接受

---

### 问题 7: PlayQueue 的 Mix 模式状态与 Playlist 的 isMix 不同步风险

**标题**: PlayQueue.isMixMode 与 Playlist.isMix 可能不同步，导致状态混乱

**等级**: Low

**影响模块**:
- `lib/data/models/play_queue.dart` (PlayQueue 模型)
- `lib/data/models/playlist.dart` (Playlist 模型)
- `lib/services/audio/queue_manager.dart` (队列管理)

**具体文件路径**:
- `lib/data/models/play_queue.dart:49-56` (PlayQueue Mix 字段)
- `lib/data/models/playlist.dart:49-56` (Playlist Mix 字段)

**问题描述**:
PlayQueue 和 Playlist 都有 Mix 模式相关的字段：
- PlayQueue: `isMixMode`, `mixPlaylistId`, `mixSeedVideoId`, `mixTitle`
- Playlist: `isMix`, `mixPlaylistId`, `mixSeedVideoId`

这两个模型中的 Mix 状态可能不同步，导致：
1. 队列认为是 Mix 模式，但 Playlist 不是
2. 反之亦然

**为什么这是问题**:
- 状态重复存储在两个地方
- 没有明确的同步机制
- 如果一个更新而另一个没有，会导致不一致

**可能造成的影响**:
- 低风险 - 当前代码可能有同步逻辑
- 但如果维护不当，可能导致 UI 显示错误

**推荐修改方向**:
1. 明确定义 Mix 模式的所有者（PlayQueue 还是 Playlist）
2. 添加一个 getter 来检查两者是否同步
3. 在修改时确保两者同时更新

**修改风险**: 中等 - 需要检查所有修改 Mix 状态的地方

**是否值得立即处理**: 建议列入后续重构计划

**分类**: 建议列入后续重构计划

---

### 问题 8: DownloadTask.savePath 的唯一性约束缺失

**标题**: DownloadTask.savePath 用于去重，但没有唯一性约束

**等级**: Low

**影响模块**:
- `lib/data/models/download_task.dart` (DownloadTask 模型)
- `lib/data/repositories/download_repository.dart` (下载仓库)

**具体文件路径**:
- `lib/data/models/download_task.dart:38-40` (savePath 字段)
- `lib/data/repositories/download_repository.dart:41-47` (getTaskBySavePath)

**问题描述**:
DownloadTask 模型中的 `savePath` 字段（第 38-40 行）有 `@Index()` 但没有 `unique: true`。这意味着：
1. 可能存在多个任务有相同的 savePath
2. `getTaskBySavePath()` 只返回第一个匹配的任务
3. 去重逻辑可能失效

**为什么这是问题**:
- 注释说"用于任务去重"，但没有强制唯一性
- 如果并发创建两个任务，都有相同的 savePath，去重会失败

**可能造成的影响**:
- 低风险 - 当前代码可能有其他去重机制
- 但如果没有，可能导致重复下载

**推荐修改方向**:
1. 添加 `unique: true` 到 savePath 索引
2. 或者在创建任务前检查是否已存在

**修改风险**: 中等 - 需要处理唯一性冲突

**是否值得立即处理**: 建议列入后续重构计划

**分类**: 建议列入后续重构计划

---

## 当前设计可接受的项目

### 1. Track 的多个索引设计

**项目**: Track 模型中的复合索引和多个 @Index() 字段

**为什么可接受**:
- 索引设计合理，支持多种查询模式
- 复合索引 `sourceKey` 和 `sourcePageKey` 正确处理了分P逻辑
- 性能优化合理

**建议**: 保持不动

---

### 2. Settings 的原子更新机制

**项目**: SettingsRepository.update() 使用事务解决竞态问题

**为什么可接受**:
- 设计正确，解决了多 Notifier 竞态问题
- 使用 writeTxn() 确保原子性
- 调用方可以正确处理异常

**建议**: 保持不动

---

### 3. 列表字段的 List.from() 处理

**项目**: 所有列表字段修改都使用 `List.from()` 创建可变副本

**为什么可接受**:
- 正确处理了 Isar 的 fixed-length list 问题
- 一致的模式应用于所有列表字段
- 代码清晰易懂

**建议**: 保持不动

---

### 4. @embedded 对象的变更检测

**项目**: PlaylistDownloadInfo 通过创建新对象确保 Isar 检测

**为什么可接受**:
- 虽然代码重复，但这是 Isar @embedded 的正确用法
- 确保了数据持久化的可靠性

**建议**: 保持不动（但可在后续重构中优化）

---

### 5. 迁移逻辑的字段值检查

**项目**: 通过检查字段值是否为默认值来判断是否需要升级

**为什么可接受**:
- 对于当前的迁移场景足够
- 逻辑清晰，易于理解
- 覆盖了大多数字段

**建议**: 保持不动（但建议添加版本号机制以支持未来的复杂迁移）

---

### 6. PlayHistory 的独立存储

**项目**: PlayHistory 独立于 Track 存储，不依赖外键

**为什么可接受**:
- 允许历史记录独立显示
- 即使 Track 被删除，历史记录仍然存在
- 设计合理

**建议**: 保持不动

---

### 7. LyricsMatch 的唯一性约束

**项目**: LyricsMatch.trackUniqueKey 有 `unique: true, replace: true`

**为什么可接受**:
- 正确处理了歌词匹配的唯一性
- `replace: true` 允许更新现有匹配
- 设计合理

**建议**: 保持不动

---

## 总结

FMP 的数据库设计总体上是健全的，迁移逻辑覆盖了大多数关键字段。主要的改进机会在于：

1. **立即处理**: 无 - 当前设计没有严重缺陷
2. **后续重构**: 
   - 添加数据库版本号机制
   - 重构 Settings 迁移逻辑
   - 优化 PlaylistDownloadInfo 的复制逻辑
   - 明确 Mix 模式的状态管理
3. **保持现状**: 大多数核心设计都是合理的

建议按照优先级逐步处理后续重构项目，不需要紧急修改。
