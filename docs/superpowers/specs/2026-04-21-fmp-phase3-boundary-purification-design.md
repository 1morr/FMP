# FMP Phase 3 Boundary Purification Design

**Date:** 2026-04-21  
**Status:** Draft approved in conversation, written for review

---

## 1. 背景

Phase 1 和 Phase 2 已分别完成稳定性修复与页面层逻辑回收，但 `AudioController` 与 `QueueManager` 仍然承担了过多混合责任。当前真正暴露出来的问题，不是“界面还不够干净”，而是运行时会话编排、queue 真相、持久化协作、以及若干 helper 行为仍然交错在一起，导致后续修改时很难快速判断某段逻辑到底属于谁。

Phase 3 的任务不是做新的 public API 设计，也不是为了形式上的分层去重构，而是把这些已经被证明会持续增加维护成本的内部责任边界纯化，为后续 Phase 4 的性能与保护增强提供更稳定的结构基础。

---

## 2. 目标

Phase 3 的目标是：

- 在 **不改变 `AudioController` 与 `QueueManager` 对外角色** 的前提下，纯化它们的内部责任边界。
- 让播放会话编排、queue 真相变更、持久化协作、以及派生 helper 行为之间的归属更清晰。
- 只吸收那些**直接帮助边界纯化**的 Phase 2 follow-up，不把阶段目标扩张成通用 cleanup。
- 让未来进入 Phase 4 时，不必再先做一轮“到底谁负责这段”的结构性修补。

---

## 3. 推荐方案

本阶段采用：**双边并行设计、分段落地**。

含义是：

- 设计上同时规划 `AudioController` 与 `QueueManager` 的内部 seam；
- 实施上拆成小任务，按安全顺序逐段落地；
- 每段结构调整都绑定最小测试与验证；
- 不允许把内部纯化演变成 public API reshaping 或目录级重组。

这是当前最适合 FMP 的方式，因为它既能完整定义双边边界，又能把执行风险控制在可验证的小步范围内。

---

## 4. 纳入范围

### 4.1 `AudioController` 内部边界纯化

`AudioController` 继续保留 **UI 唯一播放入口** 的角色，但内部责任要更接近 orchestration shell，而不是继续累积细节实现。

本阶段纳入：

- playback request lifecycle / supersession / loading state 相关 seam
- temporary play 的上下文保存与恢复 seam
- Mix session 的高层协调 seam
- 与 queue / persistence / stream 交互时的内部责任收口

### 4.2 `QueueManager` 内部边界纯化

`QueueManager` 继续保留 **queue-facing public API** 的角色，但内部责任必须更清楚。

本阶段纳入：

- queue mutation / ordering / current index / shuffle / loop 的核心真相 seam
- queue 持久化与 snapshot / position / mix 持久化相关 seam
- queue-derived helper / notification / derived view 相关 seam

### 4.3 直接帮助边界纯化的 Phase 2 leftovers

只吸收以下类型的尾项：

- 会妨碍 `AudioController` / `QueueManager` 判责的 helper 挂载错误
- 会影响运行时真实责任归属判断的最小 truth-source 问题
- 与新 seam 直接相关的最小测试补强

---

## 5. 明确不做的事

Phase 3 明确不做：

- 不改变 **UI 只能经由 `AudioController`** 的规则
- 不改变 **`QueueManager` 仍是 queue-facing API** 的既有定位
- 不做 public API reshaping
- 不做目录级重组
- 不把性能优化作为本阶段主轴
- 不把零散的 Phase 2 review follow-up 全部打包进来
- 不做和 boundary purification 无直接关系的顺手 cleanup

---

## 6. 责任模型

### 6.1 `AudioController` 的角色

`AudioController` 应该负责：

- 向 UI 暴露播放相关 public entry
- 管理播放请求的生命周期与 supersession
- 管理 temporary play 的会话切换
- 管理 Mix session 的高层协调
- 决定何时向 queue / persistence / stream 相关 seam 发出请求

它不应该继续承担这些责任的内部细节实现本体。

### 6.2 `QueueManager` 的角色

`QueueManager` 应该负责：

- queue canonical state 的变更
- ordering / current index / shuffle / loop 的真相维护
- queue-facing mutation 规则
- queue 相关通知与持久化协调

它不应该继续把 queue 真相、持久化细节、以及派生 helper 行为混写成同一段逻辑。

### 6.3 两者之间的边界规则

目标数据流应收敛为：

**UI → AudioController → QueueManager core → persistence / derived helpers**

也就是说：

- `AudioController` 拥有播放会话与模式切换的 orchestration 责任；
- `QueueManager` 拥有 queue 真相与 queue mutation 规则；
- persistence 与 derived helper 必须建立在 queue 真相之后，而不是反过来塑造 queue 真相；
- `AudioController` 不重写 queue semantics；
- `QueueManager` 不接手 UI / session orchestration。

---

## 7. 设计单元

### 7.1 `AudioController` 内部设计单元

#### A. Playback request seam
负责：
- play request lifecycle
- request id / supersession
- loading state 进出
- request 执行完成与失败回收

#### B. Temporary play seam
负责：
- temporary play 前的上下文保存
- temporary play 结束后的上下文恢复
- saved queue index / position / playback state 的一致管理

#### C. Mix coordination seam
负责：
- start mix
- load more mix tracks
- exit mix
- Mix session 与 queue / persistence 的高层协调

### 7.2 `QueueManager` 内部设计单元

#### A. Queue core seam
负责：
- add / remove / move / clear
- current index 变化
- ordering / shuffle / loop canonical state

#### B. Queue persistence seam
负责：
- queue snapshot save / restore
- playback position persistence
- mix 相关持久化交接

#### C. Queue-derived helper seam
负责：
- upcoming / derived queue views
- queue notifications
- add-next placement 等规则性 helper
- 其他建立在 queue 真相之上的导出逻辑

---

## 8. 执行顺序策略

### 8.1 `AudioController` 顺序
1. 先收口 playback request seam
2. 再收口 temporary play seam
3. 最后整理 mix coordination seam

原因是 request execution 是最核心的共同链路；temporary play 与 Mix 都应建立在更清晰的 request lifecycle 之上。

### 8.2 `QueueManager` 顺序
1. 先界定 queue core mutation
2. 再拆 persistence 路径
3. 最后整理 helper / derived logic

原因是先定义 queue 真相，才能稳定地决定哪些是附带动作、哪些只是派生结果。

### 8.3 双边实施策略
- spec 同时规划两边
- implementation plan 按小任务拆开
- 每个任务只处理一个 seam 或一个直接相连的 leftover
- 每个任务都绑定最小回归验证

---

## 9. 测试与验证策略

Phase 3 不追求全面补测，而是保护新的 seam。

重点测试类型：

- playback request lifecycle / supersession 回归
- temporary play state transition 回归
- Mix session coordination 回归
- queue mutation / ordering canonical behavior 回归
- persistence 与 queue core 责任分界回归

测试目标不是证明“抽得更漂亮”，而是证明结构纯化后，高风险链路仍然正确，并且边界更可预测。

---

## 10. 成功标准

Phase 3 完成时，应满足：

- `AudioController` 仍然是 UI 唯一入口，但内部 orchestration 责任更明确
- `QueueManager` 仍然是 queue-facing API，但内部 queue / persistence / helper 边界更清楚
- 与边界纯化直接相关的 runtime truth-source 错位减少
- Phase 4 不需要再先做一轮结构性判责修补
- 调整后的结构服务于真实维护问题，而不是形式上的“更干净”

---

## 11. 下一步

在这份 design 获得书面 review 确认后，下一步应进入 **Phase 3 implementation plan**，把本设计拆成可验证、可提交、带最小测试护栏的任务序列。
