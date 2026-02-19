# Flutter VM Service API 调试指南（快速参考）

## 连接方式

用户启动 `flutter run` 后提供 VM Service URI。

### Marionette MCP（UI 交互）
```
mcp__marionette__connect(uri: "ws://127.0.0.1:<PORT>/<TOKEN>=/ws")
```
工具：connect, disconnect, get_interactive_elements, tap, enter_text, scroll_to, get_logs, take_screenshots, hot_reload

### VM Service HTTP API（性能/内存数据）
```bash
BASE="http://127.0.0.1:<PORT>/<TOKEN>="
ISOLATE="isolates/<NUMBER>"  # 从 getVM 获取
```

## 常用 API

### 内存
- `$BASE/getVM` — RSS, currentMemory, isolate 列表
- `$BASE/getMemoryUsage?isolateId=$ISOLATE` — heapUsage, heapCapacity, externalUsage
- `$BASE/_getAllocationProfile?isolateId=$ISOLATE` — 每个类的实例数和内存占用

### 帧性能
- `$BASE/getVMTimeline?timeOriginMicros=0&timeExtentMicros=999999999999` — Timeline 事件
- 关键事件（B/E 配对）：Animator::BeginFrame（UI帧）、GPURasterizer::Draw（光栅化）、VsyncProcessCallback
- Jank: >16.67ms, Severe: >33.34ms
- GC 事件: cat="GC"，关注 ConcurrentMark, CollectOldGeneration, Scavenge

### Flutter 扩展
- `ext.flutter.profileWidgetBuilds` — 启用 Widget build 时间记录
- `ext.flutter.showPerformanceOverlay` — 性能覆盖层
- `ext.flutter.repaintRainbow` — 重绘彩虹
- `ext.flutter.debugDumpApp` — Widget 树 dump（~900KB）
- `ext.flutter.debugDumpRenderTree` — Render 树 dump（~2MB）
- `ext.ui.window.impellerEnabled` — 检查 Impeller 状态

### 网络
- `ext.dart.io.getHttpProfile` — HTTP 请求列表
- `ext.dart.io.getSocketProfile` — Socket 连接
- `ext.dart.io.getOpenFiles` — 打开的文件

### Isar 数据库
- `ext.isar.listInstances` — 数据库实例列表
- `ext.isar.getSchema` — Schema 定义
- `ext.isar.executeQuery` — 执行查询
- `ext.isar.exportJson` — 导出数据

## Windows 注意事项
- 用 `python`（不是 `python3`）
- 文件保存到 `$TEMP`
- 读 JSON 用 `encoding='utf-8'`
- VM Service URI 每次 flutter run 会变

## 详细文档
完整指南见 `docs/debugging-with-vm-service.md`
