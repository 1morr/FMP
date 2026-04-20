# 一致性与可维护性审查报告

## 审查范围
- 规则文档：`CLAUDE.md`、`docs/development.md`、`docs/comprehensive-analysis.md`、`.serena/memories/ui_coding_patterns.md`、`.serena/memories/architecture.md`、`.serena/memories/audio_system.md`
- 定向审查代码：`lib/ui/`、`lib/providers/`、`lib/services/audio/`、`lib/services/radio/` 的页面、Provider、共享动作处理与播放器边界
- 重点核对规则：FutureProvider 变更后 invalidate、乐观更新失败回滚、列表项 `ValueKey`、统一图片加载、统一播放状态判断、进度条只在 `onChangeEnd`/拖动结束时 seek、菜单动作一致性、页面与服务职责边界

## 总体结论
- 项目当前的视觉层一致性明显好于逻辑层一致性。图片加载、进度条拖动、AppBar 末尾间距、绝大多数播放态判断都已经比较统一。
- 主要问题集中在边界穿透和局部抽象未收口：少数页面仍直接承担数据层/文件层工作，单曲菜单动作已有共享抽象但尚未全面落地，Riverpod 订阅粒度也不完全一致。
- 未发现 `Image.network()` / `Image.file()` 的直接使用；也未发现把 `seekToProgress()` 绑定到 Slider `onChanged` 的违规写法。这两项当前是统一的。
- 本轮最值得优先处理的是“乐观排序更新缺少失败回滚”，因为它直接违反项目既定规则，且已经进入用户可见行为层。

## 发现的问题列表

| ID | 标题 | 严重级别 | 分类 | 是否值得立即处理 |
|---|---|---|---|---|
| C1 | 页面仍承担业务/数据层工作 | Medium | 建议列入后续重构计划 | 否 |
| C2 | 乐观排序更新缺少失败回滚 | High | 应立即修改 | 是 |
| C3 | 单曲菜单动作只做了部分收敛 | Medium | 建议列入后续重构计划 | 否 |
| C4 | Riverpod 播放状态订阅粒度不一致 | Medium | 建议列入后续重构计划 | 否 |
| C5 | 菜单 action 命名风格不统一 | Low | 当前可接受 | 否 |
| C6 | 播放历史分组列表缺少稳定 `ValueKey` | Low | 建议列入后续重构计划 | 视近期是否继续改历史页而定 |

### C1
- 严重级别：Medium
- 标题：页面仍承担业务/数据层工作
- 影响模块：搜索页、已下载页、歌单详情页
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\search\search_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_category_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\playlist_detail_page.dart`
- 必要时附关键代码位置：`search_page.dart:798-819`、`downloaded_category_page.dart:732-752`、`playlist_detail_page.dart:1304-1345`
- 问题描述：页面层直接调用 `BilibiliSource`/`buildAuthHeaders` 拉取分P数据，直接在 Widget 内执行 `compute()` 文件删除和 repository 清理，还在页面内收集批量下载任务并触发调度。
- 为什么这是问题：这类逻辑已经超出页面装配职责，导致 UI 与源站协议、文件系统、副作用调度直接耦合，测试也更难脱离页面进行。
- 可能造成的影响：后续修改鉴权 header、下载规则、分P加载策略时，容易继续在页面里复制补丁，边界越来越难维护。
- 推荐修改方向：把分P加载下沉到 `SearchNotifier`/`SearchService`；把批量删文件与下载调度收敛到 `DownloadService` 或页面对应 notifier；页面只保留对话框、Toast、导航与交互编排。
- 修改风险：Medium。主要风险在于异步交互、Toast 时机、对话框回调链需要一起梳理。
- 是否值得立即处理：否，除非近期正好继续修改这些页面的相关流程。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 先抽出无 UI 依赖的方法；2) 用 provider/notifier 暴露页面需要的结果与错误；3) 最后删掉页面里的 source/repository 直接访问。

### C2
- 严重级别：High
- 标题：乐观排序更新缺少失败回滚
- 影响模块：电台排序、歌单排序
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\radio\radio_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\services\radio\radio_controller.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\library_page.dart`
- 必要时附关键代码位置：`radio_page.dart:215-226`、`radio_controller.dart:675-682`、`library_page.dart:199-217`
- 问题描述：排序时先直接更新 UI，再异步落库；若持久化失败，没有任何回滚或错误恢复逻辑。
- 为什么这是问题：项目规则明确要求“乐观更新必须在失败时回滚”。当前实现违反了这条约定。
- 可能造成的影响：界面顺序与真实持久化顺序短暂或长期不一致；用户退出排序后才发现顺序未保存；问题定位困难。
- 推荐修改方向：在触发排序前保存旧顺序；`await` 落库时用 `try/catch`；失败则恢复旧顺序并给出提示。
- 修改风险：Low 到 Medium。逻辑集中，改动范围明确。
- 是否值得立即处理：是。
- 分类：应立即修改
- 如果要改，建议拆成几步执行：1) 保存旧列表快照；2) 为 `reorder` 流程加 `try/catch`；3) 失败时回滚并补 toast/error 日志。

### C3
- 严重级别：Medium
- 标题：单曲菜单动作只做了部分收敛
- 影响模块：首页、搜索页、历史页、歌单详情页等单曲菜单入口
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\handlers\track_action_handler.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\search\search_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\history\play_history_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\playlist_detail_page.dart`
- 必要时附关键代码位置：`track_action_handler.dart:87-135`、`search_page.dart:873-932`、`search_page.dart:1447-1499`、`play_history_page.dart:942-998`、`playlist_detail_page.dart:1558-1649`
- 问题描述：项目已经有 `TrackActionHandler` 统一单曲动作，但搜索页仍保留多段局部 switch，历史页仍完全手写，歌单详情页则是“部分前置分支 + 再转 shared handler”的混合模式。
- 为什么这是问题：同一组动作（播放、下一首、加入队列、加入歌单、歌词、远端收藏）分散在多处时，Toast 文案、登录校验、后续新增动作都会变成多点同步修改。
- 可能造成的影响：行为细节逐页漂移，后续 code review 成本上升，菜单扩展速度变慢。
- 推荐修改方向：保留共享 handler 作为唯一单曲入口；多P/批量/下载类分支作为页面扩展点，不要再复制基础单曲动作分支。
- 修改风险：Medium。因为搜索页存在多P与分组特例，不能机械替换。
- 是否值得立即处理：否，但只要再碰这些菜单，就应顺手收敛。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 先定义“单曲基础动作”和“页面特例动作”边界；2) 扩展 shared handler 支持必要回调；3) 逐页替换剩余单曲 switch。

### C4
- 严重级别：Medium
- 标题：Riverpod 播放状态订阅粒度不一致
- 影响模块：播放器页、歌曲详情面板、电台播放器、电台迷你播放器
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\player\player_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\track_detail_panel.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\radio\radio_player_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\widgets\radio\radio_mini_player.dart`
- 必要时附关键代码位置：`player_page.dart:88-145`、`track_detail_panel.dart:729-742`、`radio_player_page.dart:31-53`、`radio_mini_player.dart:37-38`；对照较细粒度用法：`mini_player.dart:139-143`、`import_preview_page.dart:841-848`
- 问题描述：有些页面直接 `ref.watch(audioControllerProvider)` 订阅整个 `PlayerState`，有些地方则已经改成 `.select(...)` 或派生 provider。
- 为什么这是问题：同一个播放域里同时存在“整包 watch”和“按字段 watch”，会让依赖关系越来越不透明，也会放大大型 Widget 的不必要重建。
- 可能造成的影响：播放器相关页面调优成本变高；未来新增字段时，难以判断谁会被连带重建。
- 推荐修改方向：大页面拆成更小的 ConsumerWidget；优先使用 `currentTrackProvider`、`positionProvider`、`.select(...)` 等精细订阅。
- 修改风险：Medium。拆分后需要重新核对交互状态与局部 `setState`。
- 是否值得立即处理：否，更适合作为播放器 UI 的持续整理项。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 先标出真正需要整包状态的区域；2) 其余区域替换为 select/派生 provider；3) 最后再按区域拆 widget。

### C5
- 严重级别：Low
- 标题：菜单 action 命名风格不统一
- 影响模块：共享菜单 action 字符串与对应解析逻辑
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\handlers\track_action_handler.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\explore\explore_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\home\home_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\search\search_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\playlist_detail_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\library\downloaded_category_page.dart`、`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\history\play_history_page.dart`
- 必要时附关键代码位置：`track_action_handler.dart:4-33`，以及各页面中使用 `value: 'matchLyrics'` 的菜单定义
- 问题描述：绝大多数 action key 使用 snake_case（如 `play_next`、`add_to_queue`），只有歌词动作仍是 camelCase 的 `matchLyrics`。
- 为什么这是问题：这不是功能 bug，但会让 grep、映射、统一封装和批量替换都变得更别扭。
- 可能造成的影响：后续新增动作时继续混用命名风格，进一步放大维护噪音。
- 推荐修改方向：统一 action key 风格，建议全部采用 snake_case，并通过 shared constant 暴露。
- 修改风险：Low。
- 是否值得立即处理：否。
- 分类：当前可接受
- 如果要改，建议拆成几步执行：1) 先在 shared handler 中定义唯一常量；2) 再统一替换各页面的字符串字面量。

### C6
- 严重级别：Low
- 标题：播放历史分组列表缺少稳定 `ValueKey`
- 影响模块：播放历史页
- 具体文件路径：`C:\Users\Roxy\Visual Studio Code\FMP\lib\ui\pages\history\play_history_page.dart`
- 必要时附关键代码位置：`play_history_page.dart:525-534`、`play_history_page.dart:568-665`
- 问题描述：日期分组下的历史项通过 `...histories.map(...)` 直接展开为 Widget 列表，没有给每条记录附加稳定 key；而仓库规范要求动态列表项尽量带 `ValueKey(item.id)`。
- 为什么这是问题：当前历史项虽然大多是无状态渲染，但这个页面同时有多选、删除、分组折叠，缺 key 会降低 Flutter diff 的可预期性。
- 可能造成的影响：后续若给行项目增加局部状态、动画或更复杂的选择态，出现错位或错误复用的概率会更高。
- 推荐修改方向：把历史项包装成带 `key: ValueKey(history.id)` 的独立 Widget，或在生成列表时显式传 key。
- 修改风险：Low。
- 是否值得立即处理：视近期是否继续改历史页；单独为它起一次变更优先级不高。
- 分类：建议列入后续重构计划
- 如果要改，建议拆成几步执行：1) 给历史项组件补 key；2) 顺手复查同页多选、删除后的渲染稳定性。

## 当前设计可接受 / 建议保持不动
- 图片加载统一性已经很好：本次在 `lib/` 下未查到 `Image.network()` / `Image.file()` 直用，`TrackThumbnail` / `ImageLoadingService` 方案应继续保持。
- 进度条 seek 规则已经统一：`player_page.dart:392-405` 与 `mini_player.dart:156-183` 都只在拖动结束或点击完成后 seek，不要回退到 `onChanged` 直接 seek。
- FutureProvider 失效刷新规则总体落地良好，`allPlaylistsProvider` 与 `downloadedCategoriesProvider` 相关变更点都能看到显式 `invalidate()`。
- AppBar 尾部 `const SizedBox(width: 8)` 在抽样页面里执行得比较稳定，当前不要再引入 `Padding(right: 8)` 之类替代写法。
- 播放状态判断整体上已形成统一模式：大多数页面使用 `currentTrack.sourceId + pageNum`；历史页使用 `cid` 是有明确注释的例外，搜索页多P整组高亮也是刻意行为，不建议现在强行统一。
- 电台的“保留上下文”与“实际占有共享播放器”两套状态区分是正确的，不建议为了表面简化把它们重新合并。
- `TrackActionHandler` 这条收敛方向本身是对的，建议继续扩展它，而不是再回到各页各写一套。
