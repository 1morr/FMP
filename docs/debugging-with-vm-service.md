# Flutter VM Service API 调试指南（AI Agent 专用）

本文档指导 AI Agent 如何通过 Dart VM Service API 和 Marionette MCP 对 FMP 应用进行运行时调试、性能分析和 UI 交互。

## 目录

1. [前置条件](#1-前置条件)
2. [连接方式](#2-连接方式)
3. [Marionette MCP — UI 交互](#3-marionette-mcp--ui-交互)
4. [VM Service HTTP API — 数据获取](#4-vm-service-http-api--数据获取)
5. [Flutter Extension API](#5-flutter-extension-api)
6. [Isar 数据库调试](#6-isar-数据库调试)
7. [常用调试脚本](#7-常用调试脚本)
8. [注意事项](#8-注意事项)

---

## 1. 前置条件

### 启动应用

用户需要在终端手动运行（AI Agent 不能启动长期进程）：

```bash
# Android
flutter run -d <device_id>

# Windows
flutter run -d windows
```

### 获取 VM Service URI

启动后控制台会输出：

```
A Dart VM Service on <device> is available at: http://127.0.0.1:<PORT>/<TOKEN>/
The Flutter DevTools debugger and profiler is available at:
http://127.0.0.1:<PORT>/<TOKEN>/devtools/?uri=ws://127.0.0.1:<PORT>/<TOKEN>/ws
```

需要提取两个值：
- **BASE URL**: `http://127.0.0.1:<PORT>/<TOKEN>=`（用于 HTTP API）
- **WS URI**: `ws://127.0.0.1:<PORT>/<TOKEN>=/ws`（用于 Marionette 连接）

### 获取 Isolate ID

```bash
curl -s "$BASE/getVM" | python -c "
import json,sys
vm = json.load(sys.stdin)['result']
for iso in vm['isolates']:
    print(f\"{iso['name']}: {iso['id']}\")"
```

通常 main isolate ID 格式为 `isolates/<number>`。

---

## 2. 连接方式

### 变量约定

文档中所有命令使用以下变量：

```bash
BASE="http://127.0.0.1:<PORT>/<TOKEN>="
ISOLATE="isolates/<ISOLATE_NUMBER>"
```

### Python 注意事项（Windows）

- 使用 `python`（不是 `python3`，Windows 上 `python3` 可能不存在）
- 文件保存到 `$TEMP` 目录（不是 `/tmp`）
- 读取 JSON 文件时使用 `encoding='utf-8'`（避免 GBK 编码错误）
- 输出含 Unicode 时可能报 GBK 编码错误，用 `PYTHONIOENCODING=utf-8` 或重定向到文件

---

## 3. Marionette MCP — UI 交互

Marionette MCP 通过 Flutter VM Service Extension 与应用通信，提供 UI 级别的交互能力。

### 连接

```
mcp__marionette__connect(uri: "ws://127.0.0.1:<PORT>/<TOKEN>=/ws")
```

### 可用工具

| 工具 | 用途 | 典型场景 |
|------|------|----------|
| `connect` | 连接到 Flutter 应用 | 开始调试前 |
| `disconnect` | 断开连接 | 结束调试 |
| `get_interactive_elements` | 获取所有可交互元素 | 了解当前页面结构 |
| `tap` | 点击元素（by key/text/type/coordinates） | 导航、按钮点击 |
| `enter_text` | 输入文本（by key） | 搜索、表单填写 |
| `scroll_to` | 滚动到指定元素（by key/text） | 查找不可见元素 |
| `get_logs` | 获取应用日志 | 查看错误、调试输出 |
| `take_screenshots` | 截图 | 视觉验证 |
| `hot_reload` | 热重载 | 代码修改后刷新 |

### 元素匹配优先级

1. **key**（最可靠）— 使用 `ValueKey<String>`
2. **text** — 匹配可见文本内容
3. **type** — 匹配 Widget 类型名
4. **coordinates** — 屏幕坐标点击（最后手段）

### 示例：导航到搜索页并搜索

```
mcp__marionette__tap(text: "Search")
mcp__marionette__enter_text(key: "search_field", input: "周杰伦")
mcp__marionette__take_screenshots()
```

### 限制

- 只能在 debug/profile 模式下工作
- 不能获取内存、性能等系统级数据
- 自定义 Widget 需要在 `MarionetteConfiguration` 中注册才能被识别
- `get_interactive_elements` 返回数据量可能很大（100+ 元素）

---

## 4. VM Service HTTP API — 数据获取

所有 API 通过 HTTP GET 请求调用，返回 JSON。

### 4.1 VM 信息

```bash
curl -s "$BASE/getVM"
```

**返回字段：**

| 字段 | 说明 | 示例 |
|------|------|------|
| `operatingSystem` | 运行平台 | `"android"` / `"windows"` |
| `hostCPU` | 宿主 CPU | `"13th Gen Intel Core i9-13900HX"` |
| `targetCPU` | 目标架构 | `"x64"` / `"arm64"` |
| `version` | Dart 版本 | `"3.11.0 (stable)"` |
| `pid` | 进程 ID | `11792` |
| `_maxRSS` | 峰值 RSS（字节） | `577212416` (550 MB) |
| `_currentRSS` | 当前 RSS（字节） | `507367424` (484 MB) |
| `_currentMemory` | 当前 Dart 内存（字节） | `198184960` (189 MB) |
| `isolates` | 应用 Isolate 列表 | `[{id, name, number}]` |
| `systemIsolates` | 系统 Isolate 列表 | vm-service 等 |

### 4.2 内存使用

#### Isolate 级别

```bash
curl -s "$BASE/getMemoryUsage?isolateId=$ISOLATE"
```

| 字段 | 说明 |
|------|------|
| `heapUsage` | Dart Heap 已用字节 |
| `heapCapacity` | Dart Heap 总容量字节 |
| `externalUsage` | 外部（native）内存字节 |

**健康指标：**
- Heap 利用率 (`heapUsage / heapCapacity`) > 90% 表示 GC 压力大
- `externalUsage` 过高可能是图片/native 资源泄漏

#### Isolate Group 级别

```bash
curl -s "$BASE/getIsolateGroupMemoryUsage?isolateGroupId=$ISOGROUP"
```

返回字段同上，但是整个 Isolate Group 的汇总。

### 4.3 对象分配概况（Allocation Profile）

```bash
curl -s "$BASE/_getAllocationProfile?isolateId=$ISOLATE"
```

**返回结构：**
- `memoryUsage` — 同 getMemoryUsage
- `members[]` — 每个类的分配统计：
  - `classRef.name` — 类名（debug 模式下可见，release 模式显示 `?`）
  - `instancesCurrent` — 当前实例数
  - `bytesCurrent` — 当前占用字节
  - `instancesAccumulated` — 累计分配实例数
  - `bytesAccumulated` — 累计分配字节

**注意：** debug 模式下类名可能显示为 `?`，这是正常的。profile 模式下类名更完整。

**分析脚本：**

```python
members = result['members']
sorted_m = sorted(members, key=lambda m: m.get('bytesCurrent', 0), reverse=True)
for m in sorted_m[:20]:
    cls = m['classRef']['name']
    instances = m['instancesCurrent']
    size_kb = m['bytesCurrent'] / 1024
    print(f"{cls}: {instances} instances, {size_kb:.1f} KB")
```

### 4.4 Timeline（帧性能 + GC + 事件追踪）

#### 获取 Timeline 数据

```bash
curl -s "$BASE/getVMTimeline?timeOriginMicros=0&timeExtentMicros=999999999999" -o timeline.json
```

**返回 `traceEvents[]`，每个事件包含：**

| 字段 | 说明 |
|------|------|
| `name` | 事件名称 |
| `cat` | 分类（`Embedder`, `GC`, `Dart`） |
| `ph` | Phase: `B`=Begin, `E`=End, `X`=Complete, `b`/`e`=async |
| `ts` | 时间戳（微秒） |
| `dur` | 持续时间（微秒，仅 `ph=X`） |
| `tid` | 线程 ID |
| `args` | 附加参数 |

#### 帧性能分析

关键事件（都是 `B`/`E` 配对）：

| 事件名 | 线程 | 含义 |
|--------|------|------|
| `Animator::BeginFrame` | UI Thread | UI 帧处理时间 |
| `GPURasterizer::Draw` | Raster Thread | 光栅化时间 |
| `VsyncProcessCallback` | UI Thread | Vsync 回调总时间 |
| `PipelineProduce` | UI Thread | Pipeline 生产（async b/e） |
| `Frame Request Pending` | UI Thread | 帧请求等待（async b/e） |

**Jank 判定标准：**
- `> 16.67ms` (60fps) — Jank（掉帧）
- `> 33.34ms` (30fps) — Severe Jank（严重掉帧）
- `> 100ms` — 可能是启动/大量数据加载

**帧时间计算（B/E 配对）：**

```python
def calc_frame_durations(events, name):
    begins = sorted([e for e in events if e['name']==name and e['ph']=='B'], key=lambda e: e['ts'])
    ends = sorted([e for e in events if e['name']==name and e['ph']=='E'], key=lambda e: e['ts'])
    return [e['ts'] - b['ts'] for b, e in zip(begins, ends) if e['ts'] - b['ts'] > 0]
```

#### GC 事件分析

GC 事件 `cat` 为 `"GC"`，也是 `B`/`E` 配对。

**关键 GC 阶段：**

| GC 阶段 | 说明 | 关注阈值 |
|---------|------|----------|
| `ConcurrentMark` | 并发标记 | > 10ms 需关注 |
| `CollectOldGeneration` | 老年代回收 | > 10ms 可能造成卡顿 |
| `CollectNewGeneration` | 新生代回收 | > 5ms 需关注 |
| `Scavenge` | 新生代清扫 | > 3ms 需关注 |
| `Sweep` / `ConcurrentSweep` | 清扫 | 通常较快 |
| `FinishIncrementalCompact` | 增量压缩完成 | > 10ms 需关注 |
| `NotifyIdle` | 空闲通知触发 GC | 正常 |

#### Timeline 流控制

```bash
# 查看当前录制的流
curl -s "$BASE/getVMTimelineFlags"

# 可用流: API, Compiler, CompilerVerbose, Dart, Debugger, Embedder, GC, Isolate, Microtask, VM
# 默认录制: Dart, Embedder, GC
```

**注意：** `setVMTimelineFlags` 的 `recordedStreams` 参数需要 JSON 数组格式，通过 HTTP GET 传递时格式复杂，建议保持默认流即可。

### 4.5 HTTP 网络请求

```bash
curl -s "$BASE/ext.dart.io.getHttpProfile?isolateId=$ISOLATE"
```

**返回 `requests[]`：**

| 字段 | 说明 |
|------|------|
| `id` | 请求 ID |
| `uri` | 请求 URL |
| `method` | HTTP 方法 |
| `status` | 状态码 |
| `startTime` | 开始时间（微秒） |
| `endTime` | 结束时间（微秒） |

**注意：** FMP 使用 Dio 库，HTTP profile 可能不会捕获所有请求。如果返回 0 个请求，可能需要启用 `ext.dart.io.httpEnableTimelineLogging`。

```bash
# 启用 HTTP timeline 日志
curl -s "$BASE/ext.dart.io.httpEnableTimelineLogging?isolateId=$ISOLATE&enabled=true"
```

### 4.6 Socket 和文件

```bash
# Socket 连接
curl -s "$BASE/ext.dart.io.getSocketProfile?isolateId=$ISOLATE"

# 打开的文件
curl -s "$BASE/ext.dart.io.getOpenFiles?isolateId=$ISOLATE"

# 单个文件详情
curl -s "$BASE/ext.dart.io.getOpenFileById?isolateId=$ISOLATE&id=<FILE_ID>"
```

## 5. Flutter Extension API

通过 `ext.flutter.*` 扩展可以控制 Flutter 框架的调试功能。

### 5.1 性能分析开关

这些扩展控制是否在 Timeline 中记录额外的性能数据：

```bash
# 查询当前状态（返回 enabled: true/false）
curl -s "$BASE/ext.flutter.profileWidgetBuilds?isolateId=$ISOLATE"

# 启用（在 Timeline 中记录每个 Widget 的 build 时间）
curl -s "$BASE/ext.flutter.profileWidgetBuilds?isolateId=$ISOLATE&enabled=true"
```

| 扩展 | 说明 | 性能影响 |
|------|------|----------|
| `profileWidgetBuilds` | 记录 Widget build 时间 | 中等 |
| `profileUserWidgetBuilds` | 仅记录用户 Widget build | 较低 |
| `profileRenderObjectPaints` | 记录 RenderObject paint 时间 | 中等 |
| `profileRenderObjectLayouts` | 记录 RenderObject layout 时间 | 中等 |
| `profilePlatformChannels` | 记录 Platform Channel 调用 | 低 |

**启用后需要触发 UI 操作（如滚动、切换页面），然后通过 `getVMTimeline` 获取新的 Timeline 数据来分析。**

### 5.2 视觉调试

```bash
# 显示性能覆盖层（帧率图表）
curl -s "$BASE/ext.flutter.showPerformanceOverlay?isolateId=$ISOLATE&enabled=true"

# 显示重绘彩虹（每次重绘变色）
curl -s "$BASE/ext.flutter.repaintRainbow?isolateId=$ISOLATE&enabled=true"

# 显示调试绘制（边框、间距等）
curl -s "$BASE/ext.flutter.debugPaint?isolateId=$ISOLATE&enabled=true"

# 反转过大图片（帮助发现未优化的图片）
curl -s "$BASE/ext.flutter.invertOversizedImages?isolateId=$ISOLATE&enabled=true"

# 时间膨胀（慢动画，值 > 1.0 减慢，< 1.0 加速）
curl -s "$BASE/ext.flutter.timeDilation?isolateId=$ISOLATE&timeDilation=5.0"
```

### 5.3 Widget/Render/Layer Tree Dump

```bash
# Widget 树（完整，可能非常大 ~900KB）
curl -s "$BASE/ext.flutter.debugDumpApp?isolateId=$ISOLATE"

# Render 树（完整，可能非常大 ~2MB）
curl -s "$BASE/ext.flutter.debugDumpRenderTree?isolateId=$ISOLATE"

# Layer 树
curl -s "$BASE/ext.flutter.debugDumpLayerTree?isolateId=$ISOLATE"

# Focus 树
curl -s "$BASE/ext.flutter.debugDumpFocusTree?isolateId=$ISOLATE"

# Semantics 树（无障碍）
curl -s "$BASE/ext.flutter.debugDumpSemanticsTreeInTraversalOrder?isolateId=$ISOLATE"
```

**返回格式：** `result.data` 为纯文本字符串。

**注意：** 这些 dump 数据量很大，建议保存到文件后用 grep 搜索特定 Widget。

### 5.4 Widget Inspector

```bash
# 获取 Widget 树根节点
curl -s "$BASE/ext.flutter.inspector.getRootWidgetSummaryTree?isolateId=$ISOLATE"

# 获取子节点
curl -s "$BASE/ext.flutter.inspector.getChildren?isolateId=$ISOLATE&objectGroup=<GROUP>&arg=<NODE_ID>"

# 获取详细子树
curl -s "$BASE/ext.flutter.inspector.getDetailsSubtree?isolateId=$ISOLATE&objectGroup=<GROUP>&arg=<NODE_ID>"

# 检查 Widget 创建位置是否被追踪
curl -s "$BASE/ext.flutter.inspector.isWidgetCreationTracked?isolateId=$ISOLATE"
# 返回 result: true 表示可以看到 Widget 的源码位置

# 追踪 dirty Widget rebuild
curl -s "$BASE/ext.flutter.inspector.trackRebuildDirtyWidgets?isolateId=$ISOLATE&enabled=true"

# 追踪 repaint Widget
curl -s "$BASE/ext.flutter.inspector.trackRepaintWidgets?isolateId=$ISOLATE&enabled=true"
```

### 5.5 渲染引擎信息

```bash
# 检查是否使用 Impeller 渲染引擎
curl -s "$BASE/ext.ui.window.impellerEnabled?isolateId=$ISOLATE"
# 返回 enabled: true/false
```

### 5.6 应用状态

```bash
# 首帧是否已发送
curl -s "$BASE/ext.flutter.didSendFirstFrameEvent?isolateId=$ISOLATE"

# 首帧是否已光栅化
curl -s "$BASE/ext.flutter.didSendFirstFrameRasterizedEvent?isolateId=$ISOLATE"

# 结构化错误是否启用
curl -s "$BASE/ext.flutter.inspector.structuredErrors?isolateId=$ISOLATE"
```

---

## 6. Isar 数据库调试

FMP 使用 Isar 数据库，debug 模式下暴露了 Isar Inspector 扩展。

```bash
# 列出所有 Isar 实例
curl -s "$BASE/ext.isar.listInstances?isolateId=$ISOLATE"
# 返回: {"result": ["fmp_database"]}

# 获取数据库 Schema（所有 Collection 的字段定义）
curl -s "$BASE/ext.isar.getSchema?isolateId=$ISOLATE"
# 返回完整的 Schema JSON，包含所有 Collection 的 properties

# 执行查询
curl -s "$BASE/ext.isar.executeQuery?isolateId=$ISOLATE&instance=fmp_database&collection=Track&filter=..."

# 导出 JSON
curl -s "$BASE/ext.isar.exportJson?isolateId=$ISOLATE&instance=fmp_database&collection=Track"

# 监听实例变化
curl -s "$BASE/ext.isar.watchInstance?isolateId=$ISOLATE&instance=fmp_database"
```

---

## 7. 常用调试脚本

### 7.1 一键内存快照

```bash
BASE="http://127.0.0.1:<PORT>/<TOKEN>="
ISOLATE="isolates/<NUMBER>"

curl -s "$BASE/getVM" -o "$TEMP/vm.json"
curl -s "$BASE/getMemoryUsage?isolateId=$ISOLATE" -o "$TEMP/mem.json"

python << 'PYEOF'
import json, os
TMP = os.environ.get('TEMP', '/tmp')

with open(os.path.join(TMP, 'vm.json'), encoding='utf-8') as f:
    vm = json.load(f)['result']
with open(os.path.join(TMP, 'mem.json'), encoding='utf-8') as f:
    mem = json.load(f)['result']

print(f"Process RSS:     {vm['_currentRSS']/1024/1024:.1f} MB (peak: {vm['_maxRSS']/1024/1024:.1f} MB)")
print(f"Dart Memory:     {vm['_currentMemory']/1024/1024:.1f} MB")
print(f"Heap Used:       {mem['heapUsage']/1024/1024:.1f} MB")
print(f"Heap Capacity:   {mem['heapCapacity']/1024/1024:.1f} MB")
print(f"Heap Util:       {mem['heapUsage']/mem['heapCapacity']*100:.1f}%")
print(f"External:        {mem['externalUsage']/1024/1024:.1f} MB")
PYEOF
```

### 7.2 一键帧性能分析

```bash
BASE="http://127.0.0.1:<PORT>/<TOKEN>="

curl -s "$BASE/getVMTimeline?timeOriginMicros=0&timeExtentMicros=999999999999" -o "$TEMP/timeline.json"

python << 'PYEOF'
import json, os
TMP = os.environ.get('TEMP', '/tmp')

with open(os.path.join(TMP, 'timeline.json'), encoding='utf-8') as f:
    events = json.load(f)['result']['traceEvents']

def analyze_frames(events, name):
    begins = sorted([e for e in events if e.get('name')==name and e.get('ph')=='B'], key=lambda e: e['ts'])
    ends = sorted([e for e in events if e.get('name')==name and e.get('ph')=='E'], key=lambda e: e['ts'])
    durations = [end['ts']-begin['ts'] for begin, end in zip(begins, ends) if end['ts']-begin['ts'] > 0]
    if not durations:
        return
    s = sorted(durations)
    jank = [d for d in durations if d > 16670]
    severe = [d for d in durations if d > 33340]
    print(f"\n{name} ({len(durations)} frames):")
    print(f"  Avg: {sum(durations)/len(durations)/1000:.2f}ms  P50: {s[len(s)//2]/1000:.2f}ms  P90: {s[int(len(s)*0.9)]/1000:.2f}ms  Max: {max(durations)/1000:.2f}ms")
    print(f"  Jank: {len(jank)} ({len(jank)/len(durations)*100:.1f}%)  Severe: {len(severe)} ({len(severe)/len(durations)*100:.1f}%)")
    if jank:
        print(f"  Worst: {', '.join(f'{d/1000:.1f}ms' for d in sorted(jank, reverse=True)[:5])}")

analyze_frames(events, 'Animator::BeginFrame')
analyze_frames(events, 'GPURasterizer::Draw')
analyze_frames(events, 'VsyncProcessCallback')

# GC 汇总
gc_pairs = {}
for e in events:
    if e.get('cat') != 'GC': continue
    name_gc = e['name']
    if e['ph'] == 'B':
        gc_pairs[name_gc] = e['ts']
    elif e['ph'] == 'E' and name_gc in gc_pairs:
        dur = e['ts'] - gc_pairs[name_gc]
        if dur > 0:
            gc_pairs.setdefault(name_gc + '_durs', []).append(dur)
        del gc_pairs[name_gc]

gc_totals = {}
for k, v in gc_pairs.items():
    if k.endswith('_durs'):
        name_gc = k[:-5]
        gc_totals[name_gc] = (len(v), sum(v), max(v))

if gc_totals:
    total_gc = sum(v[1] for v in gc_totals.values())
    print(f"\nGC Total: {total_gc/1000:.1f}ms across {sum(v[0] for v in gc_totals.values())} events")
    for name_gc, (count, total, mx) in sorted(gc_totals.items(), key=lambda x: -x[1][1])[:10]:
        print(f"  {name_gc}: {count}x, total={total/1000:.1f}ms, max={mx/1000:.1f}ms")
PYEOF
```

### 7.3 内存变化监控（前后对比）

```bash
# 操作前快照
curl -s "$BASE/getMemoryUsage?isolateId=$ISOLATE" -o "$TEMP/mem_before.json"

# ... 执行操作（如切换页面、播放音乐等）...

# 操作后快照
curl -s "$BASE/getMemoryUsage?isolateId=$ISOLATE" -o "$TEMP/mem_after.json"

python << 'PYEOF'
import json, os
TMP = os.environ.get('TEMP', '/tmp')

with open(os.path.join(TMP, 'mem_before.json'), encoding='utf-8') as f:
    before = json.load(f)['result']
with open(os.path.join(TMP, 'mem_after.json'), encoding='utf-8') as f:
    after = json.load(f)['result']

for key in ['heapUsage', 'heapCapacity', 'externalUsage']:
    b = before[key] / 1024 / 1024
    a = after[key] / 1024 / 1024
    diff = a - b
    sign = '+' if diff >= 0 else ''
    print(f"{key}: {b:.1f} MB -> {a:.1f} MB ({sign}{diff:.1f} MB)")
PYEOF
```

---

## 8. 注意事项

### 8.1 Debug vs Profile vs Release

| 能力 | Debug | Profile | Release |
|------|-------|---------|---------|
| VM Service API | ✅ | ✅ | ❌ |
| Marionette MCP | ✅ | ✅ | ❌ |
| 类名可见（Allocation Profile） | 部分 | ✅ | ❌ |
| Widget 创建位置追踪 | ✅ | ❌ | ❌ |
| 性能数据准确性 | 低（有调试开销） | 高 | N/A |
| Isar Inspector | ✅ | ❌ | ❌ |

**建议：** 性能分析用 profile 模式 (`flutter run --profile`)，功能调试用 debug 模式。

### 8.2 模拟器 vs 真机

- 模拟器的帧时间和内存数据不代表真机表现
- 模拟器上的 jank 可能在真机上不存在（反之亦然）
- RSS 在模拟器上通常偏高

### 8.3 VM Service URI 会变

- 每次 `flutter run` 会生成新的 URI
- Hot restart 不会改变 URI，但 hot reload 也不会
- 完全重启应用会生成新 URI
- **如果 API 调用无响应或返回空，先确认 URI 是否仍然有效**

### 8.4 Timeline Ring Buffer

- Timeline 使用环形缓冲区，旧事件会被覆盖
- 如果需要长时间录制，考虑定期导出
- `getVMTimeline` 的 `timeOriginMicros=0&timeExtentMicros=999999999999` 获取所有缓冲区内的事件

### 8.5 API 调用不会阻塞应用

- 所有 VM Service API 调用都是非侵入性的
- 但启用 profiling 扩展（如 `profileWidgetBuilds`）会增加运行时开销
- 调试完成后建议关闭不需要的 profiling 扩展

### 8.6 完整 API 参考

- [Dart VM Service Protocol](https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md)
- [Flutter Engine Service Extensions](https://github.com/flutter/flutter/wiki/Engine-specific-Service-Protocol-extensions)
- [Flutter Framework Service Extensions](https://github.com/flutter/flutter/wiki/Framework-specific-Service-Protocol-extensions)
- [Marionette MCP](https://github.com/leancodepl/marionette_mcp)
