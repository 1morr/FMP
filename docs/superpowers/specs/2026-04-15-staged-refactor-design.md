# FMP 分阶段稳定化重构设计

**日期**: 2026-04-15  
**类型**: 设计 / 重构路线图  
**范围**: 基于 `docs/review/` 系列审查文档，为 FMP 制定低风险、可分批提交的重构方案

## 参考输入

- `docs/review/summary_review.md`
- `docs/review/architecture_review.md`
- `docs/review/consistency_review.md`
- `docs/review/stability_review.md`
- `docs/review/performance_memory_review.md`
- `docs/review/testing_review.md`
- `docs/review/database_review.md`
- `docs/review/platform_review.md`

## 设计目标

1. 在不破坏现有主架构方向的前提下，降低核心播放链路的重构风险。
2. 先建立安全重构条件，再推进 `QueueManager` / `AudioController` 的结构收敛。
3. 把重构拆成可独立验证、可独立提交的阶段，避免一次性大改。
4. 优先解决真实用户故障风险、资源泄漏风险和缺失测试保护的问题。

## 非目标

1. 不在第一阶段直接拆分 `QueueManager` 或 `AudioController`。
2. 不改变 UI 必须通过 `AudioController` 访问播放能力这一项目硬约束。
3. 不顺手做与当前审查结论无关的大范围清理或风格统一。
4. 不把“代码变小”当作第一优先级，高于稳定性和测试保护。

## 现状结论

审查文档的共同结论是：FMP 的架构主线正确，当前最大问题不是方向错误，而是缺少安全重构条件。

主要前置风险如下：
- 关键播放链路测试覆盖严重不足。
- `DownloadService`、`QueueManager`、`AudioService`、`PlaylistListNotifier`、`RankingCacheService` 存在资源清理风险。
- 临时播放恢复、下载计数器、Mix 状态、网络恢复等边界场景脆弱。
- `QueueManager` 与 `AudioController` 已经过大，但当前不具备直接大拆分的安全条件。

## 总体策略

本次工作定义为 **分阶段稳定化重构**，而不是立即进行核心模块重写。

整体顺序固定为：
1. 建立保护层
2. 修复高风险边界与资源管理问题
3. 收敛高频维护痛点
4. 提纯职责边界
5. 最后再拆核心模块

该顺序的核心原则是：**先建立安全重构条件，再改变结构。**

## 阶段划分

### 阶段一：建立保护层

**目标**: 在不改变核心结构的前提下，为后续重构建立最小回归保护网。  
**范围仅限于以下三类工作**:

#### 1. 最小测试集
- `playTemporary()` / `_restoreQueuePlayback()`
- `_executePlayRequest()` / `_isSuperseded()`
- `ensureAudioUrl()` 与 URL 刷新 / 重试链
- 下载调度、取消、清理链路
- `_migrateDatabase()` 与关键默认值修正

#### 2. 资源清理修复
- `DownloadService` 的 `StreamController`
- `PlaylistListNotifier.watchAll()` 订阅
- `AudioService` 中的 `BehaviorSubject`
- `QueueManager` 的定时器与状态流
- `RankingCacheService` 的订阅生命周期

#### 3. 关键稳定性边界修复
- 连续 temporary play 时原始返回点被覆盖
- `_activeDownloads` 计数与清理时序不一致
- Mix 状态清理不彻底
- 必要的播放恢复 / 中断边界问题

**进入条件**: 无，可立即开始。  
**退出条件**:
- 最小测试集稳定通过
- 已消除明确的资源清理缺口
- 高风险边界问题具备测试或显式验证手段
- 该阶段提交中不包含结构拆分

### 阶段二：收敛高频维护痛点

**目标**: 在不动核心播放结构的前提下，减少重复逻辑和一致性噪音。  
**范围**:
- FutureProvider 失效策略规范化
- `ValueKey` 补齐
- 菜单处理入口收敛
- 页面层 Provider 访问聚合减负

**进入条件**: 阶段一完成，基础保护已建立。  
**退出条件**:
- 同类页面遵循统一模式
- 低风险重复逻辑明显减少
- 不改动核心播放结构

### 阶段三：提纯职责边界

**目标**: 为核心模块重构建立清晰边界，但不直接进行最终拆分。  
**范围**:
- 从 `QueueManager` 提纯流获取与持久化边界
- 从 `AudioController` 提纯请求执行、temporary play、Mix 会话边界
- 先通过委托与私有提取验证边界合理性

**进入条件**:
- 阶段一保护网已经覆盖核心链路
- 阶段二已减少外围维护噪音

**退出条件**:
- 各职责边界可独立描述和测试
- 主类已能通过委托调用这些边界
- 每次提纯都能单独提交和验证

### 阶段四：核心模块结构重构

**目标**: 正式收窄 `QueueManager` 与 `AudioController`。  
**范围**:
- `QueueManager` 只保留队列领域逻辑
- `AudioController` 收敛为 UI 门面与编排协调器
- 将已提纯的职责正式外移并稳定落地

**进入条件**:
- 前三阶段完成
- 核心链路测试稳定
- 边界提纯已证明可行

**退出条件**:
- 主类职责显著收窄
- 现有行为保持不变
- 文档与测试同步更新

## 目标边界设计

### `AudioController`
保留为 UI 的唯一入口，但最终仅负责：
- 对 UI 暴露状态与动作
- 编排下层协作者
- 统一处理用户可见的错误、重试状态和后续副作用

### `QueueManager`
最终仅负责队列领域逻辑：
- 队列增删改查
- 当前索引、上一首、下一首、upcoming tracks
- shuffle / loop 状态
- 队列级状态通知

### `AudioStreamManager`
负责“把 Track 解析成可播放流”：
- URL 获取与刷新
- 本地文件优先与无效路径清理
- 备用流与流元信息处理
- 结合 source / settings / auth-for-play 选择正确流

### `QueuePersistenceManager`
负责：
- 队列快照持久化
- 播放位置保存与恢复
- 启动恢复
- Mix 相关持久状态恢复与必要清理

### `PlaybackRequestExecutor`
负责：
- request id / superseding 检查
- 单次播放请求生命周期
- 在关键 `await` 点执行 supersede 判断
- 协调 `AudioStreamManager` 与 `AudioService`

### `TemporaryPlayHandler`
负责：
- 保存原始返回点
- 进入 temporary 模式
- 播放完成 / 失败 / 取消后的恢复
- 避免连续 temporary play 覆盖原始会话状态

### `MixPlaylistHandler`
负责：
- Mix 会话进入与退出
- 自动续载更多 track
- 集中管理 Mix 下禁止的操作
- Mix 状态清理与一致性维护

## 关键数据流设计

### 普通播放
`UI -> AudioController -> PlaybackRequestExecutor -> AudioStreamManager -> AudioService`

规则：
- 请求执行与 UI 状态提交分离。
- superseded 的旧请求属于流程控制，不应对用户报错。
- `AudioController` 统一处理历史记录、歌词触发、错误提示与重试状态。

### Temporary Play
- 首次进入 temporary 模式时保存原始返回点。
- temporary 会话中再次 temporary play 不覆盖原始返回点。
- 恢复流程必须先验证索引与上下文有效，再提交恢复。
- 恢复成功后再清除保存状态，避免半恢复状态。

### URL 失效与重试
- `AudioStreamManager` 负责单次取流是否成功。
- `AudioController` 负责是否自动重试、是否等待网络恢复、如何向 UI 暴露状态。
- 单次取流逻辑与跨请求恢复策略必须分层。

### Mix 模式
- Mix 特例不应继续散落在全局 `if (isMix)` 中。
- `MixPlaylistHandler` 作为 Mix 会话的唯一所有者。
- 普通队列逻辑继续由 `QueueManager` 维护。

## 测试策略

测试不是附属产物，而是阶段切换条件。

### 阶段一必须建立的保护
1. 播放会话测试
   - temporary play 进入 / 恢复
   - 连续 temporary play 不覆盖原始返回点
   - superseded 请求不会提交旧状态
2. 流获取与恢复测试
   - `ensureAudioUrl()` 正常获取、刷新、失败与恢复
   - auth-for-play 切换后正确取流
3. 下载稳定性测试
   - 开始 / 取消 / 清理
   - `_activeDownloads` 不泄漏
4. 迁移与持久化测试
   - `_migrateDatabase()` 修正关键默认值
   - 队列 / 位置 / Mix 状态恢复正确

### 验证规则
1. 没有测试或显式人工验证，不算完成。
2. 每个阶段结束前，必须验证上一阶段的保护网仍然有效。
3. 任何核心重构提交，都必须能指出其依赖的前置测试。

## 交付与提交原则

每个阶段都必须支持分批提交，且单个提交只改变一个风险轴：
- 只补测试
- 或只修资源清理
- 或只修单个稳定性边界
- 或只提纯一个职责边界

禁止把“测试 + 泄漏修复 + 边界提取 + 重命名”混在同一提交中。

## 风险控制规则

1. 阶段一完成前，不做核心结构拆分。
2. UI -> `AudioController` 的统一入口不能被破坏。
3. 先修真实故障风险，再追求文件变小。
4. 新边界只有在具备独立状态、独立测试价值、独立变化原因时才提取。
5. 先私有提取验证边界，再决定是否正式外移为独立文件。

## 建议执行顺序

1. 最小测试保护
2. 资源清理修复
3. 关键稳定性边界修复
4. 低风险一致性整理
5. 职责边界提纯
6. 核心模块正式拆分

## 设计结论

本次工作应被定义为 **稳定化优先的分阶段重构计划**。其核心路径为：

1. 先补保护层
2. 再清理高风险边界
3. 再提纯职责边界
4. 最后才拆核心模块

这样做既符合 `docs/review/` 的审查共识，也符合当前代码库最小风险、最高可验证性的推进方式。