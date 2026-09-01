# Flutter VM Service API 除錯指南（AI Agent 專用）

本文件指導 AI Agent 如何透過 Dart VM Service API 對 FMP 應用進行執行時除錯與效能分析。

## 目錄

1. [前置條件](#1-前置條件)
2. [連線方式](#2-連線方式)
3. [VM Service HTTP API — 資料獲取](#3-vm-service-http-api-資料獲取)
4. [Flutter Extension API](#4-flutter-extension-api)
5. [Isar 資料庫除錯](#5-isar-資料庫除錯)
6. [常用除錯指令碼](#6-常用除錯指令碼)
7. [注意事項](#7-注意事項)

---

## 1. 前置條件

### 啟動應用

先啟動應用。若當前 agent/session 不適合託管長期程序，可讓使用者在終端手動執行；如果可以啟動並保持程序，則直接執行對應命令。

```bash
# Android
flutter run -d <device_id>

# Windows
flutter run -d windows
```

### 獲取 VM Service URI

啟動後主控台會輸出：

```
A Dart VM Service on <device> is available at: http://127.0.0.1:<PORT>/<TOKEN>/
The Flutter DevTools debugger and profiler is available at:
http://127.0.0.1:<PORT>/<TOKEN>/devtools/?uri=ws://127.0.0.1:<PORT>/<TOKEN>/ws
```

需要提取兩個值：
- **BASE URL**: `http://127.0.0.1:<PORT>/<TOKEN>=`（用於 HTTP API）
- **WS URI**: `ws://127.0.0.1:<PORT>/<TOKEN>=/ws`（DevTools 與其他 WebSocket 客戶端使用；本文件的命令只需要 BASE URL）

> VM Service URL 中的 token 等同於本機除錯訪問憑證。不要把完整 URL、token、DevTools 連結或 websocket URI 貼到 issue、日誌、截圖、agent 報告或聊天記錄中。需要分享時只保留埠和用途，刪掉 token 路徑；除錯結束後關閉 app 或重新啟動以失效舊 URI。

### 獲取 Isolate ID

```bash
curl -s "$BASE/getVM" | python -c "
import json,sys
vm = json.load(sys.stdin)['result']
for iso in vm['isolates']:
    print(f\"{iso['name']}: {iso['id']}\")"
```

通常 main isolate ID 格式為 `isolates/<number>`。

---

## 2. 連線方式

### 變數約定

文件中所有命令使用以下變數：

```bash
BASE="http://127.0.0.1:<PORT>/<TOKEN>="
ISOLATE="isolates/<ISOLATE_NUMBER>"
```

### Python 注意事項（Windows）

- 使用 `python`（不是 `python3`，Windows 上 `python3` 可能不存在）
- PowerShell 臨時目錄變數是 `$env:TEMP`；Bash/CMD 示例裡的 `$TEMP` / `%TEMP%` 不可直接混用
- 讀取 JSON 檔案時使用 `encoding='utf-8'`（避免 GBK 編碼錯誤）
- 輸出含 Unicode 時可能報 GBK 編碼錯誤，用 `PYTHONIOENCODING=utf-8` 或重定向到檔案
- PowerShell 中 `curl` 可能是 alias；需要原生命令時用 `curl.exe`，或改用 `Invoke-RestMethod`
- Bash here-doc（`python << 'PYEOF'`）不能直接在 PowerShell 中執行；PowerShell 用 here-string：`@' ... '@ | python -`

### PowerShell HTTP 示例

```powershell
$BASE = "http://127.0.0.1:<PORT>/<TOKEN>="
$ISOLATE = "isolates/<ISOLATE_NUMBER>"

# JSON object
$vm = Invoke-RestMethod "$BASE/getVM"
$vm.result.isolates | ForEach-Object { "$($_.name): $($_.id)" }

# Raw response saved to file
curl.exe -s "$BASE/getMemoryUsage?isolateId=$ISOLATE" -o "$env:TEMP\mem.json"
```

後續命令如果寫成 `curl -s "$BASE/..."`，在 PowerShell 中優先替換為 `curl.exe -s "$BASE/..."`。

---

## 3. VM Service HTTP API — 資料獲取

所有 API 透過 HTTP GET 請求呼叫，返回 JSON。

### 3.1 VM 資訊

```bash
curl -s "$BASE/getVM"
```

**返回欄位：**

| 欄位 | 說明 | 示例 |
|------|------|------|
| `operatingSystem` | 執行平臺 | `"android"` / `"windows"` |
| `hostCPU` | 宿主 CPU | `"13th Gen Intel Core i9-13900HX"` |
| `targetCPU` | 目標架構 | `"x64"` / `"arm64"` |
| `version` | Dart 版本 | `"3.11.0 (stable)"` |
| `pid` | 程序 ID | `11792` |
| `_maxRSS` | 峰值 RSS（位元組） | `577212416` (550 MB) |
| `_currentRSS` | 當前 RSS（位元組） | `507367424` (484 MB) |
| `_currentMemory` | 當前 Dart 記憶體（位元組） | `198184960` (189 MB) |
| `isolates` | 應用 Isolate 列表 | `[{id, name, number}]` |
| `systemIsolates` | 系統 Isolate 列表 | vm-service 等 |

### 3.2 記憶體使用

#### Isolate 級別

```bash
curl -s "$BASE/getMemoryUsage?isolateId=$ISOLATE"
```

| 欄位 | 說明 |
|------|------|
| `heapUsage` | Dart Heap 已用位元組 |
| `heapCapacity` | Dart Heap 總容量位元組 |
| `externalUsage` | 外部（native）記憶體位元組 |

**健康指標：**
- Heap 利用率 (`heapUsage / heapCapacity`) > 90% 表示 GC 壓力大
- `externalUsage` 過高可能是圖片/native 資源洩漏

#### Isolate Group 級別

```bash
curl -s "$BASE/getIsolateGroupMemoryUsage?isolateGroupId=$ISOGROUP"
```

返回欄位同上，但是整個 Isolate Group 的彙總。

### 3.3 物件分配概況（Allocation Profile）

```bash
curl -s "$BASE/_getAllocationProfile?isolateId=$ISOLATE"
```

**返回結構：**
- `memoryUsage` — 同 getMemoryUsage
- `members[]` — 每個類的分配統計：
  - `class.name` — 類名
  - `instancesCurrent` — 當前例項數
  - `bytesCurrent` — 當前佔用位元組
  - `instancesAccumulated` — 累計分配例項數
  - `accumulatedSize` — 累計分配位元組

> ⚠️ 欄位名是 **`class`**，不是 `classRef`。實測（Dart 3.12.2，2026-07-27）單個 member 的完整鍵為
> `['_new', '_old', 'accumulatedSize', 'bytesCurrent', 'class', 'instancesAccumulated', 'instancesCurrent', 'type']`。
> 用 `m['classRef']` 會直接 `KeyError`。

**注意：** debug 模式下類名可能顯示為 `?`，這是正常的。profile 模式下類名更完整。

**分析指令碼：**

```python
members = result['members']
sorted_m = sorted(members, key=lambda m: m.get('bytesCurrent', 0), reverse=True)
for m in sorted_m[:20]:
    cls = (m.get('class') or {}).get('name', '?')
    instances = m['instancesCurrent']
    size_kb = m['bytesCurrent'] / 1024
    print(f"{cls}: {instances} instances, {size_kb:.1f} KB")
```

### 3.4 Timeline（幀效能 + GC + 事件追蹤）

#### 獲取 Timeline 資料

```bash
curl -s "$BASE/getVMTimeline?timeOriginMicros=0&timeExtentMicros=999999999999" -o timeline.json
```

**返回 `traceEvents[]`，每個事件包含：**

| 欄位 | 說明 |
|------|------|
| `name` | 事件名稱 |
| `cat` | 分類（`Embedder`, `GC`, `Dart`） |
| `ph` | Phase: `B`=Begin, `E`=End, `X`=Complete, `b`/`e`=async |
| `ts` | 時間戳（微秒） |
| `dur` | 持續時間（微秒，僅 `ph=X`） |
| `tid` | 執行緒 ID |
| `args` | 附加引數 |

#### 幀效能分析

關鍵事件（都是 `B`/`E` 配對）：

| 事件名 | 執行緒 | 含義 |
|--------|------|------|
| `Animator::BeginFrame` | UI Thread | UI 幀處理時間 |
| `GPURasterizer::Draw` | Raster Thread | 光柵化時間 |
| `VsyncProcessCallback` | UI Thread | Vsync 回撥總時間 |
| `PipelineProduce` | UI Thread | Pipeline 生產（async b/e） |
| `Frame Request Pending` | UI Thread | 幀請求等待（async b/e） |

**Jank 判定標準：**
- `> 16.67ms` (60fps) — Jank（掉幀）
- `> 33.34ms` (30fps) — Severe Jank（嚴重掉幀）
- `> 100ms` — 可能是啟動/大量資料載入

**幀時間計算（B/E 配對）：**

```python
def calc_frame_durations(events, name):
    begins = sorted([e for e in events if e['name']==name and e['ph']=='B'], key=lambda e: e['ts'])
    ends = sorted([e for e in events if e['name']==name and e['ph']=='E'], key=lambda e: e['ts'])
    return [e['ts'] - b['ts'] for b, e in zip(begins, ends) if e['ts'] - b['ts'] > 0]
```

#### GC 事件分析

GC 事件 `cat` 為 `"GC"`，也是 `B`/`E` 配對。

**關鍵 GC 階段：**

| GC 階段 | 說明 | 關注閾值 |
|---------|------|----------|
| `ConcurrentMark` | 併發標記 | > 10ms 需關注 |
| `CollectOldGeneration` | 老年代回收 | > 10ms 可能造成卡頓 |
| `CollectNewGeneration` | 新生代回收 | > 5ms 需關注 |
| `Scavenge` | 新生代清掃 | > 3ms 需關注 |
| `Sweep` / `ConcurrentSweep` | 清掃 | 通常較快 |
| `FinishIncrementalCompact` | 增量壓縮完成 | > 10ms 需關注 |
| `NotifyIdle` | 空閒通知觸發 GC | 正常 |

#### Timeline 流控制

```bash
# 檢視當前錄製的流
curl -s "$BASE/getVMTimelineFlags"

# 可用流: API, Compiler, CompilerVerbose, Dart, Debugger, Embedder, GC, Isolate, Microtask, VM
# 預設錄製: Dart, Embedder, GC
```

**注意：** `setVMTimelineFlags` 的 `recordedStreams` 引數需要 JSON 陣列格式，透過 HTTP GET 傳遞時格式複雜，建議保持預設流即可。

### 3.5 HTTP 網路請求

```bash
curl -s "$BASE/ext.dart.io.getHttpProfile?isolateId=$ISOLATE"
```

**返回 `requests[]`：**

| 欄位 | 說明 |
|------|------|
| `id` | 請求 ID |
| `uri` | 請求 URL |
| `method` | HTTP 方法 |
| `status` | 狀態碼 |
| `startTime` | 開始時間（微秒） |
| `endTime` | 結束時間（微秒） |

> 🔴 **實測對 FMP 無效，不要在這裡花時間。** 2026-07-27 在 debug 會話實測：應用剛從三個音源
> 載入上百首排行榜資料，`getHttpProfile` 仍返回 **0 個請求**；按下面的方法啟用
> `httpEnableTimelineLogging`（返回 `{'enabled': True}`）後重查，依然 **0 個**；
> `getVMTimeline` 的 12934 個事件裡 HTTP/Socket 相關也是 **0 個**。
>
> 需要看 FMP 的網路行為，用 `AppLogger` 的 source adapter 日誌，或在 Dio 上掛 interceptor。

```bash
# 啟用 HTTP timeline 日誌（實測未能讓 FMP 的請求出現）
curl -s "$BASE/ext.dart.io.httpEnableTimelineLogging?isolateId=$ISOLATE&enabled=true"
```

> 保留一個未驗證的可能：上述實測是在流量發生**之後**才啟用 logging 的。嚴格的複測應先啟用再產生流量。
> 但同一次實測中 `getSocketProfile` 對**當下存活**的連線也返回 0，這一點無法用啟用時機解釋。

### 3.6 Socket 和檔案

> 🔴 **同樣實測返回空。** `getSocketProfile` → 0 sockets，`getOpenFiles` → 0 files，
> 而當時 Isar 已開啟、三個音源的 HTTP 連線剛完成。與 §3.5 一併視為對 FMP 不可用。

```bash
# Socket 連線
curl -s "$BASE/ext.dart.io.getSocketProfile?isolateId=$ISOLATE"

# 開啟的檔案
curl -s "$BASE/ext.dart.io.getOpenFiles?isolateId=$ISOLATE"

# 單個檔案詳情
curl -s "$BASE/ext.dart.io.getOpenFileById?isolateId=$ISOLATE&id=<FILE_ID>"
```

## 4. Flutter Extension API

透過 `ext.flutter.*` 擴充套件可以控制 Flutter 框架的除錯功能。

### 4.1 效能分析開關

這些擴充套件控制是否在 Timeline 中記錄額外的效能資料：

```bash
# 查詢當前狀態（返回 enabled: true/false）
curl -s "$BASE/ext.flutter.profileWidgetBuilds?isolateId=$ISOLATE"

# 啟用（在 Timeline 中記錄每個 Widget 的 build 時間）
curl -s "$BASE/ext.flutter.profileWidgetBuilds?isolateId=$ISOLATE&enabled=true"
```

| 擴充套件 | 說明 | 效能影響 |
|------|------|----------|
| `profileWidgetBuilds` | 記錄 Widget build 時間 | 中等 |
| `profileUserWidgetBuilds` | 僅記錄使用者 Widget build | 較低 |
| `profileRenderObjectPaints` | 記錄 RenderObject paint 時間 | 中等 |
| `profileRenderObjectLayouts` | 記錄 RenderObject layout 時間 | 中等 |
| `profilePlatformChannels` | 記錄 Platform Channel 呼叫 | 低 |

**啟用後需要觸發 UI 操作（如滾動、切換頁面），然後透過 `getVMTimeline` 獲取新的 Timeline 資料來分析。**

### 4.2 視覺除錯

```bash
# 顯示效能覆蓋層（幀率圖表）
curl -s "$BASE/ext.flutter.showPerformanceOverlay?isolateId=$ISOLATE&enabled=true"

# 顯示重繪彩虹（每次重繪變色）
curl -s "$BASE/ext.flutter.repaintRainbow?isolateId=$ISOLATE&enabled=true"

# 顯示除錯繪製（邊框、間距等）
curl -s "$BASE/ext.flutter.debugPaint?isolateId=$ISOLATE&enabled=true"

# 反轉過大圖片（幫助發現未最佳化的圖片）
curl -s "$BASE/ext.flutter.invertOversizedImages?isolateId=$ISOLATE&enabled=true"

# 時間膨脹（慢動畫，值 > 1.0 減慢，< 1.0 加速）
curl -s "$BASE/ext.flutter.timeDilation?isolateId=$ISOLATE&timeDilation=5.0"
```

### 4.3 Widget/Render/Layer Tree Dump

```bash
# Widget 樹（完整，可能非常大 ~900KB）
curl -s "$BASE/ext.flutter.debugDumpApp?isolateId=$ISOLATE"

# Render 樹（完整，可能非常大 ~2MB）
curl -s "$BASE/ext.flutter.debugDumpRenderTree?isolateId=$ISOLATE"

# Layer 樹
curl -s "$BASE/ext.flutter.debugDumpLayerTree?isolateId=$ISOLATE"

# Focus 樹
curl -s "$BASE/ext.flutter.debugDumpFocusTree?isolateId=$ISOLATE"

# Semantics 樹（無障礙）
curl -s "$BASE/ext.flutter.debugDumpSemanticsTreeInTraversalOrder?isolateId=$ISOLATE"
```

**返回格式：** `result.data` 為純文字字串。

**實測體積**（2026-07-27，debug 模式，首頁已載入三個音源的排行榜）：

| 端點 | 返回大小 | agent 可直讀？ |
|------|---------|--------------|
| `debugDumpRenderTree` | **3.85 MB** | ❌ 會灌爆 context |
| `debugDumpApp` | **1.37 MB** | ❌ |
| `inspector.getRootWidgetSummaryTree` | 345 KB | ⚠️ 勉強，建議仍落盤 |
| `debugDumpLayerTree` | 43 KB | ✅ |
| `debugDumpSemanticsTreeInTraversalOrder` | 22 KB | ✅ |

**永遠先落盤再 grep，不要把前兩個直接讀進對話。** 體積隨頁面複雜度增長，上面的數字是下限不是上限。

### 4.4 Widget Inspector

```bash
# 獲取 Widget 樹根節點
curl -s "$BASE/ext.flutter.inspector.getRootWidgetSummaryTree?isolateId=$ISOLATE"

# 獲取子節點
curl -s "$BASE/ext.flutter.inspector.getChildren?isolateId=$ISOLATE&objectGroup=<GROUP>&arg=<NODE_ID>"

# 獲取詳細子樹
curl -s "$BASE/ext.flutter.inspector.getDetailsSubtree?isolateId=$ISOLATE&objectGroup=<GROUP>&arg=<NODE_ID>"

# 檢查 Widget 建立位置是否被追蹤
curl -s "$BASE/ext.flutter.inspector.isWidgetCreationTracked?isolateId=$ISOLATE"
# 返回 result: true 表示可以看到 Widget 的原始碼位置

# 追蹤 dirty Widget rebuild
curl -s "$BASE/ext.flutter.inspector.trackRebuildDirtyWidgets?isolateId=$ISOLATE&enabled=true"

# 追蹤 repaint Widget
curl -s "$BASE/ext.flutter.inspector.trackRepaintWidgets?isolateId=$ISOLATE&enabled=true"
```

### 4.5 渲染引擎資訊

```bash
# 檢查是否使用 Impeller 渲染引擎
curl -s "$BASE/ext.ui.window.impellerEnabled?isolateId=$ISOLATE"
# 返回 enabled: true/false
```

### 4.6 應用狀態

```bash
# 首幀是否已傳送
curl -s "$BASE/ext.flutter.didSendFirstFrameEvent?isolateId=$ISOLATE"

# 首幀是否已光柵化
curl -s "$BASE/ext.flutter.didSendFirstFrameRasterizedEvent?isolateId=$ISOLATE"

# 結構化錯誤是否啟用
curl -s "$BASE/ext.flutter.inspector.structuredErrors?isolateId=$ISOLATE"
```

---

## 5. Isar 資料庫除錯

FMP 使用 Isar 資料庫，debug 模式下暴露了 Isar Inspector 擴充套件。

Isar 查詢和匯出可能包含使用者搜尋詞、播放歷史、本地下載路徑、帳號後設資料、設定項和其他本地隱私資料。只查詢最小必要 collection 和欄位；不要把完整 export、schema dump、查詢結果、VM Service token 或臨時 JSON 檔案直接附到報告中。分享前應刪掉 token、絕對路徑、使用者標識和歷史記錄，並清理 `$TEMP` 中的除錯輸出。

```bash
# 列出所有 Isar 例項
curl -s "$BASE/ext.isar.listInstances?isolateId=$ISOLATE"
# 返回: {"result": ["fmp_database"]}

# 獲取資料庫 Schema（所有 Collection 的欄位定義）
curl -s "$BASE/ext.isar.getSchema?isolateId=$ISOLATE"
# 返回完整的 Schema JSON，包含所有 Collection 的 properties

# 執行查詢
curl -s "$BASE/ext.isar.executeQuery?isolateId=$ISOLATE&instance=fmp_database&collection=Track&filter=..."

# 匯出 JSON
curl -s "$BASE/ext.isar.exportJson?isolateId=$ISOLATE&instance=fmp_database&collection=Track"

# 監聽例項變化
curl -s "$BASE/ext.isar.watchInstance?isolateId=$ISOLATE&instance=fmp_database"
```

---

## 6. 常用除錯指令碼

### 6.1 一鍵記憶體快照

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

PowerShell 版本：

```powershell
$BASE = "http://127.0.0.1:<PORT>/<TOKEN>="
$ISOLATE = "isolates/<NUMBER>"

curl.exe -s "$BASE/getVM" -o "$env:TEMP\vm.json"
curl.exe -s "$BASE/getMemoryUsage?isolateId=$ISOLATE" -o "$env:TEMP\mem.json"

@'
import json, os
tmp = os.environ["TEMP"]

with open(os.path.join(tmp, "vm.json"), encoding="utf-8") as f:
    vm = json.load(f)["result"]
with open(os.path.join(tmp, "mem.json"), encoding="utf-8") as f:
    mem = json.load(f)["result"]

print(f"Process RSS:     {vm['_currentRSS']/1024/1024:.1f} MB (peak: {vm['_maxRSS']/1024/1024:.1f} MB)")
print(f"Dart Memory:     {vm['_currentMemory']/1024/1024:.1f} MB")
print(f"Heap Used:       {mem['heapUsage']/1024/1024:.1f} MB")
print(f"Heap Capacity:   {mem['heapCapacity']/1024/1024:.1f} MB")
print(f"Heap Util:       {mem['heapUsage']/mem['heapCapacity']*100:.1f}%")
print(f"External:        {mem['externalUsage']/1024/1024:.1f} MB")
'@ | python -
```

### 6.2 一鍵幀效能分析

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

# GC 彙總
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

PowerShell 中把第一行替換為 `$BASE = "http://127.0.0.1:<PORT>/<TOKEN>="`，把輸出路徑改成 `$env:TEMP\timeline.json`，並用 `@' ... '@ | python -` 執行 Python 程式碼。

### 6.3 記憶體變化監控（前後對比）

```bash
# 操作前快照
curl -s "$BASE/getMemoryUsage?isolateId=$ISOLATE" -o "$TEMP/mem_before.json"

# ... 執行操作（如切換頁面、播放音樂等）...

# 操作後快照
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

PowerShell 中同樣使用 `curl.exe`、`$env:TEMP` 和 here-string 執行 Python。

---

## 7. 注意事項

### 7.1 Debug vs Profile vs Release

| 能力 | Debug | Profile | Release |
|------|-------|---------|---------|
| VM Service API | ✅ | ✅ | ❌ |
| 類名可見（Allocation Profile） | 部分 | ✅ | ❌ |
| Widget 建立位置追蹤 | ✅ | ❌ | ❌ |
| 效能資料準確性 | 低（有除錯開銷） | 高 | N/A |
| Isar Inspector | ✅ | ❌ | ❌ |

**建議：** 效能分析用 profile 模式 (`flutter run --profile`)，功能除錯用 debug 模式。

### 7.2 模擬器 vs 真機

- 模擬器的幀時間和記憶體資料不代表真機表現
- 模擬器上的 jank 可能在真機上不存在（反之亦然）
- RSS 在模擬器上通常偏高

### 7.3 VM Service URI 會變

- 每次 `flutter run` 會生成新的 URI
- URI 中的 token 必須視為臨時 secret；複製命令、截圖和日誌時先脫敏
- 除錯匯出的 VM/Isar JSON 應只儲存在本機臨時目錄，使用完立即刪除
- Hot restart 不會改變 URI，但 hot reload 也不會
- 完全重啟應用會生成新 URI
- **如果 API 呼叫無響應或返回空，先確認 URI 是否仍然有效**

### 7.4 Timeline Ring Buffer

- Timeline 使用環形緩衝區，舊事件會被覆蓋
- 如果需要長時間錄製，考慮定期匯出
- `getVMTimeline` 的 `timeOriginMicros=0&timeExtentMicros=999999999999` 獲取所有緩衝區內的事件

### 7.5 API 呼叫不會阻塞應用

- 所有 VM Service API 呼叫都是非侵入性的
- 但啟用 profiling 擴充套件（如 `profileWidgetBuilds`）會增加執行時開銷
- 除錯完成後建議關閉不需要的 profiling 擴充套件

### 7.6 完整 API 參考

- [Dart VM Service Protocol](https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md)
- [Flutter Engine Service Extensions](https://github.com/flutter/flutter/wiki/Engine-specific-Service-Protocol-extensions)
- [Flutter Framework Service Extensions](https://github.com/flutter/flutter/wiki/Framework-specific-Service-Protocol-extensions)
