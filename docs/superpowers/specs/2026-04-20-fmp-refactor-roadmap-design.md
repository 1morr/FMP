# FMP 重构路线图设计文档

日期：2026-04-20
路径：`docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md`

## 1. 背景

本设计基于以下审查文档形成：
- `docs/review/summary_review.md`
- `docs/review/architecture_review.md`
- `docs/review/consistency_review.md`
- `docs/review/performance_memory_review.md`
- `docs/review/stability_review.md`
- `docs/review/platform_review.md`
- `docs/review/database_review.md`
- `docs/review/testing_review.md`

这些文档已经把当前项目的主要问题分成了几类：
- 运行时真实缺陷
- 数据一致性与迁移/备份问题
- 页面层越界与逻辑不统一
- 性能与订阅粒度问题
- 测试保护不足

本设计的目标不是“重做架构”，而是把这些审查结论整理成一个**分阶段、可执行、可暂停**的重构路线图。

## 2. 目标

本路线图的核心目标是：
1. 先建立稳定基线，优先消除真实运行缺陷与数据一致性问题。
2. 再统一页面/服务/数据层边界，降低维护成本。
3. 最后在系统已稳定的前提下，再处理结构性整理、性能优化和长期测试保护。

本路线图必须满足两个条件：
- **Phase 1 可以单独执行并交付稳定收益**。
- **Phase 2 之后的工作必须等待 Phase 1 完成并复核后再继续计划**。

## 3. 范围与非目标

### 3.1 范围
本路线图覆盖以下四个阶段：
- Phase 1：稳定基线
- Phase 2：逻辑统一与边界收口
- Phase 3：结构性重构
- Phase 4：长期优化与保护增强

### 3.2 非目标
本路线图明确不做以下事情：
- 不为了“更高级的架构”而做脱离当前项目实际的大重写。
- 不在 Phase 1 中顺手塞入性能优化、UI 大整理或目录重组。
- 不把后续阶段提前变成实施任务清单。
- 不把审查中“建议保持不动”的设计再次纳入重构目标。

## 4. 总体策略

### 4.1 总原则
重构顺序遵循：
1. **先修真实缺陷**
2. **再统一逻辑与边界**
3. **再做必要的结构调整**
4. **最后做长期优化**

### 4.2 Phase 之间的关系
- Phase 1 完成前，不启动 Phase 2 的实施 planning。
- Phase 2~4 在本设计中只保留路线图和进入条件，不提前展开为实施步骤。
- 如果 Phase 1 完成后发现问题分布变化，可以重排后续阶段，但不能反向扩张 Phase 1。

## 5. 四阶段路线图

### 5.1 Phase 1：稳定基线
**目标**
- 清除当前最真实、最危险、最容易影响用户体验或数据正确性的缺陷。
- 统一数据默认值与初始化真相来源。
- 为修复项补最小回归护栏。

**纳入范围**
- 播放/恢复/平台控制权缺陷
- 下载正确性缺陷
- 队列与顺序一致性缺陷
- 数据迁移、备份恢复、默认值初始化一致性问题
- 与上述修复直接相关的最小测试补强

**明确排除**
- 性能与订阅粒度优化
- 页面层全面收口
- 单曲菜单全面统一
- 目录重组
- 长期平台兼容性整理

**完成标准**
- 审查文档中的“必须改”项全部关闭或被明确降级。
- 所有修复项具备最小回归测试或验证路径。
- 不引入新的大层级或大规模文件搬迁。

### 5.2 Phase 2：逻辑统一与边界收口
**目标**
- 收口页面层越界逻辑。
- 减少重复实现和局部各写各的行为。
- 统一共享动作、Provider 入口和副作用边界。

**纳入范围**
- 页面直接组装 service / 直连 repository / 直连 source 的收口
- `TrackActionHandler` 的进一步落地
- 页面进入即写库等副作用清理
- 局部 provider 入口重复与命名不一致清理

**完成标准**
- 页面层主要负责编排与交互，而非承担协议、仓储、文件系统工作。
- 共享动作和数据写入责任边界更清晰。

### 5.3 Phase 3：结构性重构
**目标**
- 处理前两个阶段暴露出的真正结构性问题。
- 统一运行时真实来源，减少“字段存在但不生效”之类设计偏差。

**纳入范围**
- `enabledSources` 这类运行时真相来源问题
- 经过验证确有必要的边界纯化
- 需要通过结构调整才能降低未来维护成本的链路

**完成标准**
- 结构调整服务于真实问题，而不是为了形式上的“更干净”。
- 调整后的边界能减少未来 Phase 4 的重复修补。

### 5.4 Phase 4：长期优化与保护增强
**目标**
- 在系统稳定后，处理性能和长期保护问题。

**纳入范围**
- 播放页 / 下载页订阅粒度优化
- 大歌单缓存与 I/O 扇出控制
- 历史页重复查询/统计优化
- 更完整的高风险链路测试补强
- Windows 关闭链路与无障碍收尾问题

**完成标准**
- 只处理已经被证明值得投入的长期优化项。
- 不为了“追求完美”而无限拉长重构周期。

## 6. Phase 1 详细设计

### 6.1 Phase 1 的工作流划分
Phase 1 采用“按故障面分批”而不是“按模块分治”。

#### 工作流 A：播放 / 恢复 / 平台控制权正确性
纳入问题：
- 电台接管全局媒体控制后未恢复音乐侧回调所有权
- 网易云 URL 过期时间语义错误
- 恢复链在异步 header 获取后缺少 superseded 检查

代表文件：
- `lib/services/audio/audio_provider.dart`
- `lib/services/audio/internal/audio_stream_delegate.dart`
- `lib/services/radio/radio_controller.dart`
- `lib/services/audio/audio_handler.dart`
- `lib/services/audio/windows_smtc_handler.dart`

#### 工作流 B：下载正确性与下载语义
纳入问题：
- 断点续传在 `200 OK` 全量响应下误追加
- 无效下载路径清理丢失 `playlistName`

代表文件：
- `lib/services/download/download_service.dart`
- `lib/services/download/download_path_sync_service.dart`
- `lib/data/repositories/track_repository.dart`
- `lib/data/models/track.dart`

#### 工作流 C：队列与顺序一致性
纳入问题：
- Shuffle 模式下 drag reorder 不维护 `_shuffleOrder`
- 乐观排序更新缺少失败回滚

代表文件：
- `lib/services/audio/queue_manager.dart`
- `lib/services/audio/audio_provider.dart`
- `lib/ui/pages/queue/queue_page.dart`
- `lib/ui/pages/radio/radio_page.dart`
- `lib/ui/pages/library/library_page.dart`
- `lib/services/radio/radio_controller.dart`

#### 工作流 D：数据库真相来源统一
纳入问题：
- 迁移漏项
- 备份/恢复字段与默认值漂移
- bootstrap / reset / page-entry writeback 多套默认值来源
- `AccountManagementPage` 页面进入即写库副作用

代表文件：
- `lib/providers/database_provider.dart`
- `lib/services/backup/backup_data.dart`
- `lib/services/backup/backup_service.dart`
- `lib/ui/pages/settings/account_management_page.dart`
- `lib/ui/pages/settings/developer_options_page.dart`
- `lib/data/models/settings.dart`
- `lib/data/models/play_queue.dart`

#### 工作流 E：最小测试护栏
只补和 Phase 1 修复直接绑定的测试，不做全面补测。

优先补的测试类型：
- 播放恢复与 URL 过期链路测试
- 下载恢复 `200 OK` 边界测试
- Queue shuffle + drag reorder 一致性测试
- 数据迁移新增字段测试
- 备份/恢复字段与 fallback 一致性测试
- 页面进入即写库移除后的默认值一致性验证

### 6.2 Phase 1 的实施约束
- 不新增大抽象，除非不这么做就无法正确修复。
- 不在 Phase 1 里顺手处理性能优化。
- 不做页面层大面积重构。
- 不做目录重组。
- 每个修复项都要附最小验证。
- 一旦某个问题需要大规模边界调整，直接移交到 Phase 2/3，而不是在 Phase 1 扩张范围。

### 6.3 Phase 1 的优先顺序
建议优先顺序：
1. 下载文件正确性与播放恢复问题
2. 平台控制权与回调归还问题
3. 数据迁移与备份恢复一致性
4. 队列顺序与乐观更新一致性
5. 与以上修复直接相关的最小测试补强

## 7. Phase 1 与后续 plan 的衔接方式

这份文档是**完整路线图版 spec**，但后续只会基于其中的 **Phase 1** 写 implementation plan。

明确规则如下：
- 现在只为 Phase 1 创建 plan。
- Phase 2~4 暂不创建实施清单。
- 等 Phase 1 的 plan 完成、执行并复核后，再决定是否启动下一阶段的 planning。
- 如果 Phase 1 执行后暴露出新的真实优先级，再回到这份 spec 上进行局部修订，而不是直接跳到 Phase 2 开工。

## 8. 成功标准

这份路线图设计成功的标准不是“覆盖了所有审查问题”，而是：
- 明确区分了现在该做什么、之后再做什么。
- 为 Phase 1 提供了足够清晰的范围和边界，能直接进入实施 planning。
- 避免把后续阶段提前扩张到当前执行窗口。

## 9. 当前推荐

推荐采纳本 spec，并立即进入下一步：
- 基于本 spec **只为 Phase 1** 编写 implementation plan。
- Phase 2~4 保持为路线图，不提前展开为实施清单。
