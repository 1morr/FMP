# 下載管理頁面重構：槽位機制設計

## 概述

重構下載管理頁面，引入「下載槽位」概念，解決以下問題：
1. 下載速度快時「下載中」區域來不及顯示
2. 暫停任務後會自動調度其他任務填補

## 設計目標

- 頂部固定顯示槽位區域，數量 = 用戶設定的同時下載數
- 暫停的任務保留在槽位中，不觸發新任務調度
- 所有槽位被占用或暫停時，不會繼續下載其他任務

---

## 一、UI 結構

```
┌─────────────────────────────────────┐
│  AppBar: 下載管理 + 批量操作菜單     │
├─────────────────────────────────────┤
│  槽位區域（固定高度）                │
│  ┌─────┐ ┌─────┐ ┌─────┐           │
│  │下載中│ │已暫停│ │ 空  │  ← 占位符  │
│  └─────┘ └─────┘ └─────┘           │
├─────────────────────────────────────┤
│  等待中 (12)                        │
│  - 任務卡片                         │
│  - 任務卡片                         │
├─────────────────────────────────────┤
│  ▼ 已完成/失敗 (可折疊)              │
│  - 已完成任務                       │
│  - 失敗任務                         │
└─────────────────────────────────────┘
```

### 槽位區域特性

- 顯示數量 = `settings.maxConcurrentDownloads`
- 包含：正在下載 + 已暫停（`isInSlot=true`）的任務
- 空槽位顯示占位符（虛線邊框 + 淡灰色背景 + 下載圖標）
- 不標示槽位編號

---

## 二、數據模型變更

### DownloadTask 新增欄位

```dart
@collection
class DownloadTask {
  // ... 現有欄位 ...
  
  /// 是否占用下載槽位
  bool isInSlot = false;
}
```

### DownloadRepository 新增方法

```dart
/// 獲取占用槽位的任務
Future<List<DownloadTask>> getTasksInSlot();

/// 獲取占用槽位的任務數量
Future<int> countTasksInSlot();

/// 重置下載中任務為暫停但保留槽位
Future<void> resetDownloadingToPausedInSlot();
```

---

## 三、調度邏輯變更

### 可用槽位計算

```dart
可用槽位 = maxConcurrentDownloads - count(isInSlot == true)
```

### isInSlot 狀態變化表

| 事件 | isInSlot 變化 |
|------|--------------|
| 任務開始下載（進入槽位） | `false → true` |
| 任務暫停 | 保持 `true` |
| 任務從暫停恢復 | 保持 `true`，直接開始下載 |
| 任務完成 | `true → false` |
| 任務失敗 | `true → false` |
| 任務被刪除/取消 | `true → false` |

### resumeTask() 邏輯調整

```dart
Future<void> resumeTask(int taskId) async {
  final task = await _downloadRepository.getTaskById(taskId);
  if (task == null) return;
  
  if (task.isInSlot) {
    // 槽位內任務：直接開始下載
    task.status = DownloadStatus.downloading;
    await _downloadRepository.saveTask(task);
    _startDownload(task);
  } else {
    // 非槽位任務：改為 pending，等待調度
    task.status = DownloadStatus.pending;
    await _downloadRepository.saveTask(task);
    _triggerSchedule();
  }
}
```

---

## 四、邊界情況處理

### 服務初始化

重置 `downloading` 狀態的任務為 `paused`，但保持 `isInSlot = true`。

### 用戶減少同時下載數

例如從 3 改為 2，但當前有 3 個任務在槽位中：
- 不主動踢出已在槽位的任務
- 可用槽位變成負數時不調度新任務
- 槽位內任務完成/失敗後自然減少

### 全部暫停/繼續

- `pauseAll()`：暫停所有下載，`isInSlot` 保持 `true`
- `resumeAll()`：恢復所有 `isInSlot=true` 的暫停任務

---

## 五、實現步驟

1. **數據模型** - 修改 `DownloadTask`，新增 `isInSlot` 欄位
2. **Repository** - 新增查詢方法
3. **DownloadService** - 修改調度邏輯和狀態處理
4. **UI** - 重構 `DownloadManagerPage`

---

## 六、需要執行的命令

```bash
# 重新生成 Isar 代碼
flutter pub run build_runner build --delete-conflicting-outputs
```
