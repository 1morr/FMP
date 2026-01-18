# 首頁排行榜緩存系統

## 設計目標

解決用戶每次進入首頁都需要等待加載熱門排行榜數據的問題。

## 架構模式：主動後台刷新 (Proactive Background Refresh)

```
應用啟動
    │
    ├──► 立即獲取數據並緩存
    │
    └──► 啟動定時器（每 1 小時觸發）
              │
              ▼
         後台靜默刷新緩存
              │
              ▼
         （循環）

用戶進入首頁
    │
    ▼
直接顯示緩存（永不 loading，除首次啟動外）
```

## 核心組件

### RankingCacheService (`lib/services/cache/ranking_cache_service.dart`)

```dart
class RankingCacheService {
  static late final RankingCacheService instance;  // 全局單例
  
  // 緩存數據
  List<Track> _bilibiliTracks = [];
  List<Track> _youtubeTracks = [];
  
  // 定時器
  Timer? _refreshTimer;  // 每小時刷新
  
  // 狀態流（用於通知 UI 更新）
  final _stateController = StreamController<void>.broadcast();
  
  Future<void> initialize();     // 立即獲取 + 啟動定時器
  Future<void> _refreshAll();    // 並行刷新兩個數據源
}
```

### Provider 結構

```dart
// 1. 服務 Provider（使用全局單例）
final rankingCacheServiceProvider = Provider<RankingCacheService>((ref) {
  return RankingCacheService.instance;
});

// 2. 數據 Provider（StreamProvider 監聽更新）
final homeBilibiliMusicRankingProvider = StreamProvider<List<Track>>((ref) async* {
  final service = ref.watch(rankingCacheServiceProvider);
  if (service.bilibiliTracks.isNotEmpty) yield service.bilibiliTracks;
  await for (final _ in service.stateChanges) {
    yield service.bilibiliTracks;
  }
});

final homeYouTubeMusicRankingProvider = StreamProvider<List<Track>>(...);
```

## 初始化位置

在 `main.dart` 中，`runApp()` 之前：

```dart
// 初始化首頁排行榜緩存服務（後台加載，不阻塞啟動）
RankingCacheService.instance = RankingCacheService();
RankingCacheService.instance.initialize(); // 不等待，後台執行
```

## 行為說明

| 場景 | 顯示 | 後台動作 |
|------|------|----------|
| 應用剛啟動（無緩存） | Loading → 數據 | 獲取數據 |
| 之後任何時候進入首頁 | **立即顯示緩存** | 無 |
| 定時器觸發（每小時） | 用戶無感知 | 靜默刷新，完成後更新 UI |

## 配置參數

```dart
static const _refreshInterval = Duration(hours: 1);  // 刷新間隔
static const _previewCount = 10;                      // 首頁預覽數量
```

## 錯誤處理

- 刷新失敗時保留舊緩存，不清空數據
- 錯誤會打印到 debug 日誌，但不影響用戶體驗

## YouTube 數據源特殊處理

由於 YouTube 的 InnerTube API 無法穩定獲取熱門視頻，改用搜索 API 作為替代方案：

```dart
// YouTubeSource.getTrendingVideos()
// 1. 使用 UploadDateFilter.lastMonth 篩選最近一個月的視頻
var searchList = await _youtube.search.search(
  query,
  filter: yt.UploadDateFilter.lastMonth,
);

// 2. 獲取最多 60 個結果（多頁）
// 3. 本地按播放量排序，取前 30 個
allTracks.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
return allTracks.take(30).toList();
```

## 探索頁面使用

探索頁面（`explore_page.dart`）使用完整緩存數據：

```dart
// cachedBilibiliRankingProvider / cachedYouTubeRankingProvider
// 返回完整的緩存列表（不限制數量），供探索頁使用
yield service.bilibiliTracks;  // 不是 .take(10)
```

首頁預覽只顯示前 10 個，探索頁顯示完整列表。

## 相關文件

- `lib/services/cache/ranking_cache_service.dart` - 緩存服務
- `lib/providers/popular_provider.dart` - Provider 定義
- `lib/main.dart` - 服務初始化
- `lib/ui/pages/home/home_page.dart` - 首頁預覽（前 10 首）
- `lib/ui/pages/explore/explore_page.dart` - 探索頁面（完整列表）
