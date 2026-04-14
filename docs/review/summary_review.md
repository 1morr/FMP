# FMP 系统级审查总汇总报告

**审查日期**: 2026-04-12  
**审查方式**: 分专项并行审查 + 主线程交叉核验  
**专项文档**:
- `docs/review/architecture_review.md`
- `docs/review/consistency_review.md`
- `docs/review/database_review.md`
- `docs/review/platform_review.md`
- `docs/review/stability_review.md`
- `docs/review/performance_memory_review.md`
- `docs/review/testing_review.md`

---

## 审查范围

本次总汇总整合了以下专项结论：

1. **架构与模块边界** - 分层、职责划分、跨层调用、目录结构
2. **代码一致性** - Riverpod 使用模式、UI 规范、重复逻辑、维护性
3. **数据库与迁移** - Isar 模型、默认值、迁移、持久化一致性
4. **平台特定实现** - Android/Windows、音频后端分离、多窗口、单实例
5. **稳定性与隐藏缺陷** - 临时播放、请求超越、下载调度、异常恢复
6. **性能与内存** - Stream/Timer/Subscription 清理、大列表、缓存、资源释放
7. **测试覆盖与回归风险** - 关键链路测试缺口、最小保护测试集

---

## 总体结论

**整体评价：架构主线正确，功能复杂度高，但当前最大的风险不是“设计完全错误”，而是“关键链路缺乏测试保护 + 少量资源清理/状态边界问题”。**

### 明确的正面结论
- ✅ `AudioController -> AudioService / QueueManager` 的主分层方向是正确的
- ✅ Android `just_audio` / Windows `media_kit` 的平台分离设计合理
- ✅ Windows 单实例、多窗口插件排除、SMTC / 通知栏集成总体方向正确
- ✅ Source / Repository / Provider / UI 的总体组织清晰，可维护性基础较好
- ✅ 临时播放、Mix 模式、URL 过期刷新、队列持久化等复杂能力已经形成稳定设计主线

### 当前最主要的系统性风险
1. **测试覆盖严重不足**：约 115K LOC 仅约 5% 测试覆盖，核心业务流程基本无保护
2. **资源清理不彻底**：StreamController、BehaviorSubject、watchAll 订阅、Timer 等存在泄漏风险
3. **关键边界场景脆弱**：临时播放恢复、下载计数器、后台中断恢复等在异常序列下可能失稳
4. **高复杂模块过大**：`AudioController` 与 `QueueManager` 职责过重，重构前必须先补测试
5. **局部一致性问题**：菜单操作重复、Provider 访问过多、FutureProvider 失效策略不统一、部分列表 `ValueKey` 可能缺失

---

## 统一优先级判断

### P0 - 应先做的事（在任何大重构前）

#### 1. 先建立最小回归测试保护层
这是本次审查最强共识。

**原因**:
- `testing_review.md` 指出临时播放、请求超越、URL 刷新与重试、下载调度、歌词匹配、导入映射、auth-for-play、迁移逻辑几乎都缺少测试
- `architecture_review.md` 和 `consistency_review.md` 同时建议的重构对象都位于高风险核心链路

**最低建议测试集**:
1. `playTemporary()` / `_restoreQueuePlayback()`
2. `_executePlayRequest()` / `_isSuperseded()`
3. `ensureAudioUrl()` + 网络恢复 / 重试链
4. 下载调度 / 取消 / Isolate 清理
5. 数据库迁移与关键默认值

**结论**: 在补齐这批测试前，不建议对 `AudioController` / `QueueManager` 做结构性拆分。

#### 2. 修资源清理与泄漏风险
这是本次审查里最明确、最适合先落地的一批问题。

**优先对象**:
- `DownloadService` 的 `StreamController` 清理
- `PlaylistListNotifier.watchAll()` 订阅取消
- `AudioService` 中多个 `BehaviorSubject` 的关闭与 `_disposed` 防护
- `QueueManager` 的定时器 / 状态流清理
- `RankingCacheService` 订阅重建与释放

**结论**: 这批问题修改面小、收益高，适合作为第一批修复。

#### 3. 修关键稳定性边界
**优先对象**:
- 连续临时播放时原始队列状态覆盖风险
- 下载 `_activeDownloads` 计数器与清理时序不一致
- Android 中断 / duck / 恢复边界处理

**结论**: 这些问题比“大文件重构”更应优先，因为它们更接近真实用户故障。

#### 4. 立即做的小修复
- 检查并补齐列表项 `ValueKey(item.id)`
- 清理明显重复的菜单处理入口前，先统一最容易出错的行为分支

---

## P1 - 进入后续重构计划的事项

### 1. `QueueManager` 拆分
**来源**: `architecture_review.md`

建议方向：
- `QueueManager` 保留队列操作与 shuffle/loop
- 抽出 `AudioStreamManager`
- 抽出 `QueuePersistenceManager`

**前提**: 先有 URL 获取、临时播放、队列恢复相关测试。

### 2. `AudioController` 拆分
**来源**: `consistency_review.md`

建议方向：
- `PlaybackStateManager`
- `TemporaryPlayHandler`
- `MixPlaylistHandler`
- `PlaybackRequestExecutor`

**前提**: 先有请求超越、临时播放、网络重试测试。

### 3. 页面层减负
**来源**: `architecture_review.md` + `consistency_review.md`

建议方向：
- 提取统一菜单处理器（如 `TrackMenuHandler`）
- 为大型页面增加聚合 ViewModel Provider
- 统一播放状态判断 helper

### 4. Provider / 失效策略规范化
**来源**: `consistency_review.md`

建议方向：
- 区分 Isar watch 驱动 / 文件扫描驱动 / API 驱动
- 明确哪些 provider 需要 `invalidate`，哪些不需要
- 尽量把失效逻辑收回 notifier/service 层，而不是散落在 UI

### 5. 数据库迁移体系增强
**来源**: `database_review.md`

建议方向：
- 为 Settings 引入 `schemaVersion`
- 明确迁移日志或版本路径
- 收敛 `@embedded` 列表的复制更新逻辑
- 明确 `Mix` 状态所有权

### 6. 平台差异集中管理
**来源**: `platform_review.md`

建议方向：
- 收敛分散的 `Platform.isAndroid / isWindows`
- 为能力差异提供显式接口（如 `supportsAudioDeviceSelection`）
- 补文档说明 `RadioController` 与 `AudioController` 协作边界

---

## 当前可接受 / 应保持不动的设计

以下是多个专项共同认为**方向正确、不建议轻易改动**的设计：

1. **音频后端平台分离**：Android `just_audio`，桌面 `media_kit`
2. **Windows 单实例实现**：native C++ 互斥体 + 激活现有窗口
3. **多窗口插件排除策略**：子窗口排除 `tray_manager`、`hotkey_manager`
4. **临时播放能力本身**：设计复杂但合理，不应删除，只应补测试并稳固边界
5. **Mix 播放列表模式整体思路**：动态加载与限制操作的方向正确
6. **Source 抽象层**：多音源统一异常和接口设计良好
7. **队列持久化与播放位置记忆**：整体设计成立
8. **网络错误自动重试与 URL 过期刷新主思路**：设计正确，主要缺少测试与少量边界兜底

---

## 建议执行顺序

### 第一阶段：建立保护（优先）
1. 为临时播放 / 请求超越 / URL 刷新补测试
2. 为下载调度 / 迁移逻辑补测试
3. 建 3-5 条关键集成 / 端到端链路

### 第二阶段：低风险高收益修复
1. 修 StreamController / BehaviorSubject / Subscription / Timer 清理
2. 修下载计数器与清理时序
3. 修临时播放状态覆盖边界
4. 补齐 `ValueKey`

### 第三阶段：中等规模结构整理
1. 统一菜单处理逻辑
2. 规范 Provider 失效策略
3. 收敛页面层过重的状态组合

### 第四阶段：核心模块重构
1. 拆 `QueueManager`
2. 拆 `AudioController`
3. 增强数据库迁移体系

---

## 结论

FMP **不是一个架构失败的项目**；相反，它已经具备了较清晰的分层、复杂播放能力和跨平台音频设计。当前真正限制后续演进的，不是“缺少架构方向”，而是：

- **测试保护层太薄**
- **少量资源清理问题会在长期运行中累积**
- **核心模块太大，已经接近必须重构，但又暂时缺少安全重构条件**

**最终建议**:
- 短期不要直接做大规模重构
- 先补最小测试集 + 修资源清理 / 稳定性边界
- 然后再推进 `QueueManager` / `AudioController` 的结构性拆分

这会是风险最低、收益最高的路径。
