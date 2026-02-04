# Radio Refresh Service

## 概述
`RadioRefreshService` 是一個後台定時刷新服務，負責定期更新所有電台的直播狀態。

## 功能
- 應用啟動時立即獲取直播狀態
- 每 5 分鐘自動後台刷新
- 用戶進入任何頁面時直接顯示緩存，無需等待
- 緩存直播狀態和電台資訊（封面、標題、主播名）

## 初始化
在 `main.dart` 中創建實例：
```dart
RadioRefreshService.instance = RadioRefreshService();
```

`RadioController` 會設置 Repository 並啟動刷新：
```dart
RadioRefreshService.instance.setRepository(_repository);
```

## 使用
```dart
// 獲取直播狀態
final isLive = RadioRefreshService.instance.isStationLive(stationId);

// 手動刷新所有電台
await RadioRefreshService.instance.refreshAll();

// 監聽狀態變化
RadioRefreshService.instance.stateChanges.listen((_) {
  // 更新 UI
});
```
