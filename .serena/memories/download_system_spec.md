# 下载管理系统 - 需求规格

## 一、功能概述

为 FMP 实现完整的下载管理系统，支持单曲和歌单下载，提供已下载内容管理和下载任务管理。

## 二、数据模型

### 2.1 DownloadTask（修改现有）

```dart
@collection
class DownloadTask {
  Id id;
  int trackId;                    // 关联的歌曲ID
  int? playlistDownloadTaskId;    // 所属歌单下载任务ID（null=独立单曲任务）
  
  @Enumerated(EnumType.name)
  DownloadStatus status;          // pending/downloading/paused/completed/failed
  
  double progress;                // 0.0 - 1.0
  int downloadedBytes;
  int? totalBytes;
  String? errorMessage;
  int priority;                   // 排序优先级（越小越优先）
  
  DateTime createdAt;
  DateTime? completedAt;
}

enum DownloadStatus {
  pending,      // 等待中
  downloading,  // 下载中
  paused,       // 已暂停
  completed,    // 已完成
  failed,       // 失败
}
```

### 2.2 PlaylistDownloadTask（新增）

```dart
@collection
class PlaylistDownloadTask {
  Id id;
  int playlistId;                 // 关联的歌单ID
  String playlistName;            // 快照歌单名（防止歌单删除后显示异常）
  List<int> trackIds;             // 要下载的歌曲ID列表
  
  @Enumerated(EnumType.name)
  DownloadStatus status;          // pending/downloading/paused/completed/failed
  
  int priority;                   // 排序优先级
  DateTime createdAt;
  DateTime? completedAt;
}
```

### 2.3 Settings 扩展

```dart
// 在 Settings 模型中添加：
String? downloadPath;             // 自定义下载路径（null=使用默认）
int maxConcurrentDownloads = 3;   // 最大并发下载数 (1-5)
DownloadImageOption downloadImageOption = DownloadImageOption.coverOnly;

enum DownloadImageOption {
  none,           // 不下载图片
  coverOnly,      // 仅封面
  coverAndAvatar, // 封面和头像
}
```

## 三、下载路径与文件结构

### 3.1 默认下载路径

| 平台 | 默认路径 |
|------|----------|
| Android | `外部存储/Music/FMP/` |
| Windows | `用户文档/FMP/` |

### 3.2 下载存储规则

| 下载来源 | 存储位置 |
|----------|----------|
| 歌单详情页下载 | `{下载路径}/{歌单名}_{歌单ID}/` |
| 搜索页面下载（不在歌单中） | `{下载路径}/未分类/` |
| 队列/播放页面下载 | `{下载路径}/未分类/` |

### 3.3 目录结构

```
{下载路径}/
├── {歌单名}_{歌单ID}/
│   ├── .metadata.json               ← 歌单元数据
│   ├── cover.jpg                    ← 歌单封面（如开启）
│   ├── {视频标题}/                  ← 每个视频一个文件夹
│   │   ├── metadata.json            ← 歌曲元数据
│   │   ├── cover.jpg                ← 视频封面（如开启）
│   │   ├── audio.m4a                ← 单P视频音频
│   │   └── (或多P情况)
│   │       ├── P01 - {分P标题}.m4a
│   │       ├── P02 - {分P标题}.m4a
│   │       └── ...
│   └── ...
├── 未分类/
│   └── {视频标题}/
│       ├── metadata.json
│       ├── cover.jpg
│       └── audio.m4a
└── .avatars/                         ← 头像统一存储
    ├── {UP主ID}.jpg
    └── ...
```

### 3.4 metadata.json 格式

**歌单元数据 (.metadata.json)**:
```json
{
  "playlistId": 123,
  "name": "歌单名称",
  "createdAt": "2024-01-15T10:30:00Z"
}
```

**歌曲元数据 (metadata.json)**:
```json
{
  "sourceId": "BV1xx411x7xx",
  "sourceType": "bilibili",
  "title": "视频标题",
  "artist": "UP主名称",
  "artistId": "12345678",
  "durationMs": 180000,
  "pages": [
    {"cid": 123, "pageNum": 1, "title": "P1标题", "durationMs": 60000},
    {"cid": 456, "pageNum": 2, "title": "P2标题", "durationMs": 60000}
  ],
  "downloadedAt": "2024-01-15T10:30:00Z"
}
```

### 3.3 文件名特殊字符转换

```
/  →  ／ (U+FF0F)    \  →  ＼ (U+FF3C)
:  →  ： (U+FF1A)    *  →  ＊ (U+FF0A)
?  →  ？ (U+FF1F)    "  →  ＂ (U+FF02)
<  →  ＜ (U+FF1C)    >  →  ＞ (U+FF1E)
|  →  ｜ (U+FF5C)
```

## 四、下载队列调度逻辑

### 4.1 核心规则

1. **任务类型**：独立单曲任务 + 歌单任务（内含多个单曲）
2. **歌单限制**：同一时间只有一个歌单任务处于"执行中"
3. **并发共享**：歌单内歌曲 + 独立单曲 共享并发限制
4. **执行顺序**：按 priority 字段排序（可拖动调整）
5. **分P处理**：自动下载视频的所有分P

### 4.2 调度示例

```
队列: [单曲A, 歌单X(含5首), 单曲B, 歌单Y(含3首)]
并发限制: 3

执行状态:
- 槽位1: 单曲A ✓
- 槽位2: 歌单X-歌曲1 ✓
- 槽位3: 歌单X-歌曲2 ✓
- 单曲B: 等待（歌单X占用了2个槽位）
- 歌单Y: 等待（歌单X未完成）
```

### 4.3 失败处理

- 单曲失败：标记为 failed，跳过继续下载其他
- 歌单内歌曲失败：跳过该歌曲，继续下载歌单内其他歌曲
- 歌单完成后汇总失败列表

### 4.4 程序重启恢复

1. 启动时扫描 `status=downloading` 的任务
2. 删除已下载的不完整文件
3. 将状态改为 `paused`，等待用户手动继续
4. 不做断点续传（URL 会过期，从头下载更可靠）

## 五、页面设计

### 5.1 下载入口

| 位置 | 触发方式 | 操作 |
|------|----------|------|
| 歌单详情页 | 右上角下载按钮 | 下载整个歌单（所有分P） |
| 音乐库页面 | 长按歌单 → 菜单 | 下载整个歌单（所有分P） |
| 各页面歌曲项 | 菜单 | 下载单曲（含所有分P） |

### 5.2 已下载页面 (DownloadedPage)

**入口**：音乐库页面左上角按钮

**布局**：与音乐库页面相同的歌单网格

**数据来源**：直接扫描文件系统目录结构（类似本地音乐播放器）

**工作流程**：
1. 扫描下载目录，获取所有子文件夹
2. 每个文件夹 = 一个歌单
3. 读取 .metadata.json 获取歌单信息
4. 扫描文件夹内的子文件夹，每个 = 一首歌
5. 读取 metadata.json 获取歌曲信息
6. 文件不存在则不显示（用户手动删除的情况）

**顶部信息**：
- 已用存储空间
- 可用存储空间

**歌单来源**：
- 下载目录中的所有文件夹（每个文件夹 = 一个歌单）
- "未分类" 文件夹（不属于任何歌单的已下载歌曲）

**歌单卡片显示**：
- 歌单名称
- 已下载歌曲数
- 占用空间大小

**歌单菜单**：
- 删除此歌单所有下载（删除整个文件夹）

**点击歌单**：进入已下载歌单详情

**歌曲交互**（与音乐库一致）：
- 点击 → 临时播放
- 菜单 → 添加到队列、下一首播放、删除下载等
- 分P展开 → 复用现有 _GroupHeader 组件

**播放逻辑**：
- 优先复用数据库中已有的 Track 记录
- 如果数据库中不存在，创建临时 Track 对象（从 metadata.json 读取信息）

### 5.3 下载管理页面 (DownloadManagerPage)

**入口**：设置页面 → 下载管理

**顶部**：
- 并发数设置下拉框 (1-5)
- 批量操作按钮：全部暂停 / 全部继续 / 清空队列

**任务列表**（可拖动排序）：

```
正在下载
├── ≡ 🎵 歌曲标题A        ████████░░ 80%    [⏸] [🗑]
├── ≡ 📁 歌单X (3/12)     ████░░░░░░ 25%    [⏸] [🗑]
│       ├── P1 标题       ██████████ 100%   ✓
│       ├── P2 标题       ████████░░ 75%    [⏸] [🗑]
│       └── P3 标题       等待中...          [⏸] [🗑]

等待中
├── ≡ 🎵 歌曲标题B        等待中...          [⏸] [🗑]
└── ≡ 📁 歌单Y (0/8)      等待中...          [⏸] [🗑]
```

**任务操作**：
| 操作 | 独立单曲 | 歌单任务 | 歌单内歌曲 |
|------|----------|----------|------------|
| 暂停/继续 | ✓ | ✓ | ✓ |
| 删除 | ✓ | ✓ | ✓ |
| 重试（失败时） | ✓ | - | ✓ |
| 拖动排序 | ✓ | ✓ | - |

### 5.4 设置页面扩展

```
存储
├── 下载管理              →  进入下载管理页面
├── 下载路径              →  目录选择对话框
│   └── 当前: /storage/.../FMP/
├── 同时下载数量          →  [1] [2] [3] [4] [5]
└── 下载图片              →  [关闭] / [仅封面] / [封面和头像]
```

## 六、服务架构

```
┌─────────────────────────────────────────────────────────────┐
│                  DownloadController                          │
│              (Riverpod StateNotifier)                        │
│  - downloadTasksProvider (所有任务状态)                       │
│  - activeDownloadsProvider (正在下载的任务)                   │
│  - downloadedTracksProvider (已下载的歌曲)                    │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    DownloadService                           │
│  - startDownload(track/playlist)                            │
│  - pauseTask(taskId) / resumeTask(taskId)                   │
│  - cancelTask(taskId)                                       │
│  - reorderTasks(taskIds)                                    │
│  - deleteDownloadedFile(trackId)                            │
│  - 内部调度器：管理并发、优先级                               │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  DownloadRepository                          │
│  - DownloadTask CRUD                                        │
│  - PlaylistDownloadTask CRUD                                │
│  - 查询：按状态、按歌单、按优先级                             │
└─────────────────────────────────────────────────────────────┘
```

## 七、平台特性

### 7.1 Android
- **后台下载**：使用 Foreground Service + 通知栏显示进度
- **存储权限**：需要请求 WRITE_EXTERNAL_STORAGE 权限
- **默认路径**：`外部存储/Music/FMP/`

### 7.2 Windows
- **后台下载**：应用最小化后继续下载
- **路径长度**：截断过长文件名（避免超过 260 字符限制）
- **默认路径**：`用户文档/FMP/`

### 7.3 通用
- **网络限制**：不限制网络类型（WiFi/移动数据均可下载）
- **磁盘空间**：下载前检查可用空间，不足时提示用户

## 八、重复下载处理

| 场景 | 处理方式 |
|------|----------|
| 同一歌单重复下载同一首歌 | 提示"已下载"，不执行 |
| 不同歌单下载同一首歌 | 允许，各歌单文件夹各存一份 |
| 重复下载整个歌单 | 增量更新，只下载新增歌曲 |

## 九、边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 下载中歌单被删除 | 继续下载到原定文件夹 |
| 下载中歌曲被移除 | 继续下载（已加入队列） |
| 用户更改下载路径 | 只影响新下载，旧文件保留 |
| 歌单名称变更 | 已下载的文件夹名不变 |
| 视频变为不可用 | 下载失败，记录失败原因 |
| Bilibili URL 过期 | 下载开始时获取最新 URL |
| 磁盘空间不足 | 下载前检查，不足时提示并暂停 |
| 文件被用户手动删除 | 扫描时不显示，播放失败时清理 downloadedPath |

## 十、关键实现要点

1. **图片下载**：根据设置决定是否下载封面/头像，未下载时使用 Placeholder
2. **头像去重**：头像统一存储在 `.avatars/` 目录，按 UP主ID 命名避免重复下载
3. **歌单名冲突**：使用 `{歌单名}_{歌单ID}` 格式
4. **已下载页面数据来源**：直接扫描文件系统目录结构，不依赖数据库
5. **下载位置规则**：歌曲存储在触发下载时所在的歌单文件夹中
6. **Track.downloadedPath 字段**：保留该字段，下载完成时更新，用于快速判断是否已下载
7. **播放已下载内容**：优先复用数据库中已有的 Track，否则从 metadata.json 创建临时对象
8. **文件丢失处理**：扫描时文件不存在则不显示，同时清理 Track.downloadedPath

## 十一、实现优先级建议

### Phase 1: 核心下载功能
1. 数据模型创建/修改 + build_runner
2. DownloadRepository 实现
3. DownloadService 基础实现（单曲下载）
4. 设置页面：下载路径、并发数、图片选项

### Phase 2: 下载管理页面
1. DownloadManagerPage UI
2. 任务列表显示
3. 暂停/继续/删除/重试操作
4. 拖动排序

### Phase 3: 歌单下载
1. PlaylistDownloadTask 支持
2. 歌单下载调度逻辑
3. 下载入口（歌单详情页、长按菜单）

### Phase 4: 已下载页面
1. DownloadedPage UI
2. 歌单分组逻辑
3. 存储空间显示
4. 删除下载功能

### Phase 5: 完善
1. 歌曲菜单下载选项
2. 程序重启恢复
3. 错误处理优化
