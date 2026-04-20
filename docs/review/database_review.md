# 数据层与数据库一致性审查报告

日期：2026-04-20

## 1) 审查范围

本次审查聚焦 Isar 数据层、迁移覆盖、备份一致性、仓库写入模式与数据变更后的 UI 同步风险，重点覆盖以下内容：

- 项目规则与文档：`CLAUDE.md`、`docs/development.md`、`docs/comprehensive-analysis.md`、`.serena/memories/database_migration.md`、`.serena/memories/architecture.md`
- Isar 模型：`lib/data/models/*.dart`
- 数据仓库：`lib/data/repositories/*.dart`
- 数据库初始化与迁移：`lib/providers/database_provider.dart`
- 备份与恢复：`lib/services/backup/backup_data.dart`、`lib/services/backup/backup_service.dart`
- 相关 Provider / UI 同步路径：`lib/providers/playlist_provider.dart`、`lib/providers/play_history_provider.dart`、`lib/providers/search_provider.dart`、`lib/ui/pages/settings/developer_options_page.dart`、`lib/ui/pages/settings/account_management_page.dart`
- 现有迁移测试：`test/providers/database_migration_test.dart`

## 2) 总体结论

- 当前没有发现会立刻破坏 Isar 基本可用性的 Critical 问题。
- 数据层里已经有几处值得保留的正确模式：`SettingsRepository.update()` 的原子更新、`Track.playlistInfo` 的嵌入对象整表替换、`watchAll()/watchLazy()` 与显式 `invalidate()` 的分工、以及针对 NetEase 迁移的专项测试。
- 但本轮审查确认了 2 个 High、3 个 Medium 问题，核心集中在：
  - 升级迁移仍有真实漏项。
  - 备份结构已经落后于当前 `Settings` 模型，且若干 restore 默认值与业务默认值不一致。
  - 数据初始化存在多个分叉入口，导致“新装默认值 / 重置默认值 / 页面进入后写回值”并不完全一致。
- 按项目规则，“只有 Isar 类型默认值与业务默认值不同的字段才需要迁移”这一原则本身是正确的；问题不在规则，而在少数字段没有按这个规则补齐。

## 3) 发现的问题列表

### 问题 DB-01
- 严重级别：High
- 标题：若干后加字段的业务默认值与 Isar 类型默认值不一致，但迁移未覆盖
- 影响模块：升级路径、播放位置恢复、歌词源配置、队列音量恢复
- 具体文件路径：
  - `lib/data/models/settings.dart`
  - `lib/data/models/play_queue.dart`
  - `lib/providers/database_provider.dart`
  - `test/providers/database_migration_test.dart`
- 必要时附关键代码位置：
  - `lib/data/models/settings.dart:87-94`
  - `lib/data/models/settings.dart:162-165`
  - `lib/data/models/play_queue.dart:40-42`
  - `lib/providers/database_provider.dart:37-114`
  - `test/providers/database_migration_test.dart:30-95`
- 问题描述：
  当前迁移逻辑已覆盖 `maxConcurrentDownloads`、`maxCacheSizeMB`、`downloadImageOptionIndex`、`maxLyricsCacheFiles`、NetEase 三联字段等，但仍遗漏了几个“模型默认值 != Isar 类型默认值”的后加字段：`rememberPlaybackPosition = true`、`tempPlayRewindSeconds = 10`、`disabledLyricsSources = 'lrclib'`、`PlayQueue.lastVolume = 1.0`。
- 为什么这是问题：
  这些字段在旧库升级时会分别落成 `false`、`0`、`''`、`0.0`。按仓库约定，它们都属于需要迁移修正的情况。
- 可能造成的影响：
  - 老用户升级后“记住播放位置”被静默关闭。
  - 临时播放恢复回退秒数变成 `0`。
  - 歌词禁用源集合被清空，行为与新装默认配置不一致。
  - 队列恢复时保存音量可能被还原成 `0.0`，表现为升级后首次恢复近似静音。
- 推荐修改方向：
  在 `_migrateDatabase()` 中按当前业务默认值补齐这些字段，并把现有迁移测试从 NetEase 特例扩展到上述字段。
- 修改风险：Low
- 是否值得立即处理：是
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：应立即修改
- 如果要改，建议拆成几步执行：
  1. 为 `Settings` 补 `rememberPlaybackPosition`、`tempPlayRewindSeconds`、`disabledLyricsSources` 的升级修正。
  2. 为 `PlayQueue` 补 `lastVolume` 的升级修正。
  3. 扩展 `test/providers/database_migration_test.dart`，覆盖这些默认值场景。

### 问题 DB-02
- 严重级别：High
- 标题：备份结构已经落后于当前 Settings 模型，且旧备份恢复默认值有偏差
- 影响模块：备份/恢复、跨版本设置一致性
- 具体文件路径：
  - `lib/data/models/settings.dart`
  - `lib/services/backup/backup_data.dart`
  - `lib/services/backup/backup_service.dart`
- 必要时附关键代码位置：
  - `lib/data/models/settings.dart:137-183`
  - `lib/services/backup/backup_data.dart:410-557`
  - `lib/services/backup/backup_service.dart:178-210`
  - `lib/services/backup/backup_service.dart:554-603`
- 问题描述：
  `SettingsBackup` 目前没有覆盖多个仍在使用的设置字段，包括 `neteaseStreamPriority`、`useBilibiliAuthForPlay`、`useYoutubeAuthForPlay`、`useNeteaseAuthForPlay`、`rankingRefreshIntervalMinutes`、`radioRefreshIntervalMinutes`。同时，`fromJson()` 对若干缺失字段使用的回退默认值与 `Settings` 模型不一致，例如 `minimizeToTrayOnClose`、`enableGlobalHotkeys`、`autoMatchLyrics`、`disabledLyricsSources`。
- 为什么这是问题：
  这会同时带来两类不一致：
  1. 新字段根本不会随备份导出/导入。
  2. 旧备份缺字段时，恢复结果不是当前模型默认值，而是另一组“备份层默认值”。
- 可能造成的影响：
  - 用户恢复备份后，播放鉴权开关与刷新间隔丢失。
  - 老备份导入后，Windows 设置、歌词自动匹配、禁用歌词源等状态被静默改写。
  - 备份 JSON 看似成功恢复，实际运行配置与导出前不一致。
- 推荐修改方向：
  让 `SettingsBackup` 与当前 `Settings` 模型重新对齐；对确实应跨设备保留当前值的字段继续显式保留，但不要遗漏非设备相关设置。
- 修改风险：Medium
- 是否值得立即处理：是
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：应立即修改
- 如果要改，建议拆成几步执行：
  1. 先补齐缺失的非设备相关字段到 `SettingsBackup` 与导入/导出逻辑。
  2. 将 `fromJson()` 的回退默认值校准到 `Settings` 当前业务默认值。
  3. 为“旧备份缺字段”的恢复路径补测试。

### 问题 DB-03
- 严重级别：Medium
- 标题：重置全部数据的初始化路径绕过了统一数据库 bootstrap 逻辑
- 影响模块：开发者重置、默认值一致性
- 具体文件路径：
  - `lib/providers/database_provider.dart`
  - `lib/ui/pages/settings/developer_options_page.dart`
- 必要时附关键代码位置：
  - `lib/providers/database_provider.dart:24-33`
  - `lib/providers/database_provider.dart:124-128`
  - `lib/ui/pages/settings/developer_options_page.dart:560-573`
- 问题描述：
  `databaseProvider` 初始化数据库时，会走 `_migrateDatabase()`，其中包含“首次安装按平台设置默认值”和“确保存在默认队列”的统一入口；但开发者页面的“重置全部数据”直接 `isar.clear()` 后写入 `Settings()` 与 `PlayQueue()`，没有复用同一 bootstrap 逻辑。
- 为什么这是问题：
  这让“新装默认值”和“重置后默认值”变成两套实现。当前最明显的差异是移动端新装会把 `maxCacheSizeMB` 调整为 `16`，而重置后会回到模型里的 `32`。
- 可能造成的影响：
  - 重置后的数据库状态与同平台新装状态不一致。
  - 将来 `_migrateDatabase()` 若继续追加 bootstrap 修正，开发者重置路径会再次漏掉。
- 推荐修改方向：
  把“重置后重新建默认数据”收口为复用 `_migrateDatabase()` 或等价的共享 bootstrap 方法，而不是手写第二套默认值。
- 修改风险：Low
- 是否值得立即处理：否
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 提取共享 bootstrap 入口。
  2. 让 reset 路径复用它。
  3. 补一个最小测试，确认 reset 后默认值与新装一致。

### 问题 DB-04
- 严重级别：Medium
- 标题：账号管理页会在进入时重写播放鉴权设置，数据库状态不是纯数据源事实
- 影响模块：设置持久化、备份恢复后的状态一致性、页面副作用
- 具体文件路径：
  - `lib/data/models/settings.dart`
  - `lib/ui/pages/settings/account_management_page.dart`
- 必要时附关键代码位置：
  - `lib/data/models/settings.dart:168-176`
  - `lib/ui/pages/settings/account_management_page.dart:29-41`
  - `lib/ui/pages/settings/account_management_page.dart:122-137`
- 问题描述：
  `AccountManagementPage` 在 `initState()` 里直接调用 `settingsRepository.update()`，把三个平台的 `useAuthForPlay` 强制写成固定值。页面展示本身也把这三个值写死为不可交互按钮状态。
- 为什么这是问题：
  一旦页面进入就写库，数据库里的值就不再只反映“迁移结果 / 恢复结果 / 用户操作结果”，而变成“某个页面最近是否被打开过”。
- 可能造成的影响：
  - 即使后续补齐备份字段，恢复后的 auth-for-play 状态也会被页面打开动作覆盖。
  - 设置来源变得不可追踪，难以判断问题来自迁移、恢复还是 UI 生命周期。
- 推荐修改方向：
  若这些开关本就不打算允许修改，应把默认值稳定地放在模型/迁移/bootstrap 层；不要由页面进入事件来兜底写回。
- 修改风险：Low
- 是否值得立即处理：否，但应尽快收口
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 把默认值逻辑移回数据初始化路径。
  2. 删除页面 `initState()` 中的写库副作用。
  3. 视需要再决定是否真的把这些字段保留为持久化设置。

### 问题 DB-05
- 严重级别：Medium
- 标题：`enabledSources` 已持久化、已迁移、已备份，但当前运行期并未把它当真实 source-of-truth
- 影响模块：设置模型、迁移、备份、搜索/音源启用逻辑
- 具体文件路径：
  - `lib/data/models/settings.dart`
  - `lib/providers/database_provider.dart`
  - `lib/services/backup/backup_service.dart`
  - `lib/data/sources/source_provider.dart`
  - `lib/providers/search_provider.dart`
- 必要时附关键代码位置：
  - `lib/data/models/settings.dart:80-82`
  - `lib/providers/database_provider.dart:90-111`
  - `lib/services/backup/backup_service.dart:186-188`
  - `lib/services/backup/backup_service.dart:564-566`
  - `lib/data/sources/source_provider.dart:13-24`
  - `lib/providers/search_provider.dart:63-65`
- 问题描述：
  `Settings.enabledSources` 被模型、迁移、备份完整保留，但运行时音源集合仍由 `SourceManager` 的注册列表和 `SearchState` 的硬编码三源集合决定，没有读取这个字段。
- 为什么这是问题：
  持久化字段看起来像是功能开关，但实际上不是运行期权威来源；这会让迁移、备份和数据库查看器中的该字段产生“有值但不生效”的误导。
- 可能造成的影响：
  - 维护者误以为迁移 `enabledSources` 会改变实际启用音源。
  - 备份恢复后该字段有值，但应用行为没有对应变化。
- 推荐修改方向：
  二选一：要么把它接回真实的 source enablement 逻辑；要么明确降级/移除这类不生效的持久化字段。
- 修改风险：Medium
- 是否值得立即处理：否
- 分类（应立即修改 / 建议列入后续重构计划 / 当前可接受 / 建议保持不动）：建议列入后续重构计划
- 如果要改，建议拆成几步执行：
  1. 先确认产品上是否仍需要“启用/禁用音源”这一持久化能力。
  2. 若需要，则让 `SourceManager` / 搜索逻辑读取它。
  3. 若不需要，则连同迁移/备份一起收缩掉该字段。

## 4) 当前设计可接受 / 建议保持不动

### 设计项 1：只对“Isar 默认值 != 业务默认值”的字段做迁移，这个原则是对的
- 相关文件：`CLAUDE.md`、`.serena/memories/database_migration.md`
- 结论：建议保持不动。
- 原因：这能避免把所有新字段都机械地堆进迁移逻辑。当前像 `Track.isVip = false`、`Playlist.useAuthForRefresh = false`、`Account.isVip = false`、以及多个 nullable 字段，都不需要额外迁移，这个判断方向是正确的。

### 设计项 2：`SettingsRepository.update()` 的原子 read-modify-write 很重要
- 相关文件：`lib/data/repositories/settings_repository.dart:25-38`
- 结论：建议保持不动。
- 原因：多个 settings notifiers 并行存在时，这个入口能避免旧副本全量覆盖新字段，是当前最关键的数据一致性护栏之一。

### 设计项 3：`Track.playlistInfo` 使用“重建嵌入对象列表”来触发 Isar 变更检测
- 相关文件：`lib/data/models/track.dart:117-149`、`lib/data/models/track.dart:186-208`
- 结论：建议保持不动。
- 原因：这里显式避免了原地修改 `@embedded` 对象不被 Isar 检测到的问题，是正确且必要的实现细节。

### 设计项 4：watch-driven 与 snapshot-driven Provider 的分工总体清楚
- 相关文件：`lib/data/repositories/playlist_repository.dart:147-153`、`lib/providers/playlist_provider.dart:63-68`、`lib/providers/play_history_provider.dart:9-20`
- 结论：建议保持不动。
- 原因：歌单列表、播放历史等多写者集合走 `watchAll()/watchLazy()`；详情/封面这类快照则显式 `invalidate()`。这类分工目前是清楚且可维护的。

### 设计项 5：备份恢复时保留设备相关设置的当前值是合理的
- 相关文件：`lib/services/backup/backup_service.dart:551-603`
- 结论：建议保持不动。
- 原因：`customDownloadDir`、`preferredAudioDeviceId`、`preferredAudioDeviceName` 这类明显依赖当前机器环境的字段，在 restore 时保留本机值是合理做法；问题在于其它非设备相关字段缺失，而不是这部分策略本身。

### 设计项 6：现有数据库迁移测试应继续保留并扩展，而不是推倒重来
- 相关文件：`test/providers/database_migration_test.dart:13-95`
- 结论：建议保持不动。
- 原因：现有测试已经准确覆盖了 NetEase 默认值修正与队列 bootstrap；最合适的方向是在此基础上扩展缺失字段，而不是更换测试框架或重写整套迁移验证。
