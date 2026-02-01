# 電台功能規格書 (Radio Feature Specification)

## 概述

用戶可以導入 YouTube/Bilibili 直播間 URL，在應用內像收音機一樣持續播放直播音頻。

## 需求摘要

| 項目 | 決策 |
|------|------|
| **直播類型** | 所有直播（提取音頻） |
| **播放模式** | 獨立於現有音樂系統，有自己的 Controller |
| **切換行為** | 互斥切換（暫停音樂↔停止電台） |
| **組織方式** | 簡單列表 |
| **標題處理** | 自動獲取 + 可編輯 |
| **UI 位置** | 獨立 Tab（底部導航） |
| **Mini player** | 電台模式專用顯示 |
| **資料存儲** | 獨立 Isar 表 (RadioStation) |
| **自動重連** | 斷流後自動重試最多 3 次 |
| **即時資訊** | 定時刷新觀眾數和直播時長（每 5 分鐘） |

## 技術方案

### 直播流獲取

**YouTube 直播**：
- 使用 `youtube_explode_dart`
- 獲取 HLS manifest URL: `yt.videos.streamsClient.getHttpLiveStreamUrl(videoId)`
- `media_kit` (libmpv) 原生支持 HLS

**Bilibili 直播**：
- API: `https://api.live.bilibili.com/room/v1/Room/playUrl?cid={roomId}&platform=web&quality=4`
- 返回 FLV 或 HLS 流地址
- `media_kit` (libmpv) 原生支持
- 需要 `Referer: https://live.bilibili.com` header

**房間資訊 API**：
- YouTube: `yt.videos.get(videoId)` 獲取標題、封面、觀看人數
- Bilibili: `https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom?room_id={roomId}`
  - 返回：房間標題、主播名、封面、觀看人數、開播時間

### 架構設計

```
┌─────────────────────────────────────┐
│          RadioPage (Tab)             │
│  - 電台列表 + 添加按鈕               │
│  - 點擊播放/停止                     │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│        RadioController              │
│  (StateNotifier<RadioState>)        │
│  - 管理電台列表 (CRUD)               │
│  - 控制播放/停止                     │
│  - 與 AudioController 互斥          │
│  - 斷流自動重連 (最多3次)            │
│  - 流地址/房間資訊定期刷新 (5分鐘)    │
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│      MediaKitAudioService           │
│  (共用現有實例)                      │
│  - playUrl() 播放直播流              │
│  - 直播流 = 普通 URL 播放            │
└─────────────────────────────────────┘
```

**核心思路**：
- **共用 `MediaKitAudioService`** — 直播流本質就是 URL 播放，不需要新播放器
- **新建 `RadioController`** — 與 `AudioController` 平級，管理電台邏輯
- **互斥機制** — 播電台前 `AudioController.pause()`，播音樂前 `RadioController.stop()`
- **新建 `RadioStation` Isar model** — 獨立存儲
- **Mini player 模式切換** — 根據 `isRadioPlaying` 顯示不同內容

### 直播流特性處理

直播流是無限長度的，與普通音樂播放有本質區別：
1. **沒有 duration** — 進度條無意義，改為顯示「已播放時長」
2. **沒有 "播放完成"** — 不觸發 `onTrackCompleted`
3. **斷流重連** — 監聽 error/completion 事件，自動重連
4. **流地址過期** — 定期刷新（與房間資訊一起，每5分鐘）

## 數據模型

```dart
@collection
class RadioStation {
  Id id = Isar.autoIncrement;
  
  @Index(unique: true)
  String url;           // 原始直播間 URL
  
  String title;         // 電台名稱（自動獲取+可編輯）
  String? thumbnailUrl; // 封面
  String? hostName;     // 主播名稱
  
  @Enumerated(EnumType.name)
  SourceType sourceType; // youtube, bilibili
  
  String sourceId;      // roomId (Bilibili) 或 videoId (YouTube)
  
  int sortOrder;        // 排序順序
  DateTime createdAt;
  DateTime? lastPlayedAt;
}
```

### RadioState

```dart
@freezed
class RadioState with _$RadioState {
  const factory RadioState({
    @Default([]) List<RadioStation> stations,     // 所有電台
    RadioStation? currentStation,                  // 正在播放的電台
    @Default(false) bool isPlaying,               // 是否正在播放
    @Default(false) bool isLoading,               // 是否正在加載
    @Default(false) bool isBuffering,             // 是否正在緩衝
    String? error,                                 // 錯誤信息
    
    // 即時資訊（定時刷新）
    int? viewerCount,                             // 觀眾數
    DateTime? liveStartTime,                      // 開播時間（用於計算直播時長）
    Duration? playDuration,                       // 已播放時長
  }) = _RadioState;
}
```

## 新增文件清單

```
lib/
├── data/
│   ├── models/
│   │   └── radio_station.dart           # RadioStation Isar model
│   └── repositories/
│       └── radio_repository.dart        # RadioStation CRUD
├── services/
│   └── radio/
│       ├── radio_source.dart            # URL 解析、流地址獲取、房間資訊
│       └── radio_controller.dart        # RadioController + RadioState + Provider
├── ui/
│   ├── pages/
│   │   └── radio/
│   │       └── radio_page.dart          # 電台列表頁面
│   └── widgets/
│       └── radio/
│           ├── radio_list_tile.dart     # 電台列表項
│           ├── radio_mini_player.dart   # 電台 mini player
│           └── add_radio_dialog.dart    # 添加電台對話框
└── providers/
    └── radio_provider.dart              # Riverpod providers
```

## 修改文件清單

| 文件 | 修改內容 |
|------|----------|
| `main.dart` | 初始化 RadioController |
| `lib/data/models/` | 重新生成 Isar schema（包含 RadioStation） |
| `lib/ui/layouts/main_layout.dart` | 添加電台 Tab |
| `lib/router.dart` | 添加 /radio 路由 |
| `lib/ui/widgets/player/mini_player.dart` | 根據模式切換顯示（音樂/電台） |
| `lib/services/audio/audio_provider.dart` | 播放音樂前停止電台 |

## UI 設計

### 電台列表項
```
┌──────────────────────────────────────────────┐
│ [封面]  電台名稱                           ⋮ │
│         主播名 · 🔴 直播中 · 1.2萬觀看      │
└──────────────────────────────────────────────┘
```

- 點擊整行播放/暫停
- 三點菜單：編輯、刪除
- 長按可拖動排序

### Mini player（電台模式）
```
┌──────────────────────────────────────────────┐
│ [封面]  電台名稱              🔴LIVE    [■] │
│         12:34:56 已播放 · 緩衝中...          │
└──────────────────────────────────────────────┘
```

- 無進度條（直播無限長度）
- 顯示已播放時長
- 停止按鈕（不是暫停）
- 點擊跳轉電台頁面（不是全屏播放器）

### 添加電台對話框
```
┌──────────────────────────────────────────────┐
│                添加電台                       │
├──────────────────────────────────────────────┤
│  直播間 URL                                  │
│  ┌────────────────────────────────────────┐ │
│  │ https://live.bilibili.com/123456       │ │
│  └────────────────────────────────────────┘ │
│                                              │
│  支持 YouTube 和 Bilibili 直播               │
│                                              │
│              [取消]     [添加]               │
└──────────────────────────────────────────────┘
```

## 互斥機制實現

### AudioController 中
```dart
Future<void> _playTrack(Track track, ...) async {
  // 播放音樂前停止電台
  final radioController = _ref.read(radioControllerProvider.notifier);
  await radioController.stop();
  
  // ... 原有邏輯
}
```

### RadioController 中
```dart
Future<void> play(RadioStation station) async {
  // 播放電台前暫停音樂（保留隊列位置）
  final audioController = _ref.read(audioControllerProvider.notifier);
  await audioController.pause();
  
  // ... 播放電台
}
```

## 斷流重連邏輯

```dart
class RadioController {
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];

  void _onPlaybackError(Object error) async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      state = state.copyWith(
        isPlaying: false,
        error: '連線失敗，請稍後重試',
      );
      return;
    }

    final delay = _reconnectDelays[_reconnectAttempts];
    _reconnectAttempts++;
    
    state = state.copyWith(error: '連線中斷，${delay.inSeconds}秒後重試...');
    
    await Future.delayed(delay);
    await _refreshStreamAndPlay();
  }

  void _onPlaybackSuccess() {
    _reconnectAttempts = 0;  // 重置重連計數
  }
}
```

## 定時刷新邏輯

```dart
class RadioController {
  Timer? _infoRefreshTimer;
  Timer? _playDurationTimer;

  void _startTimers() {
    // 每5分鐘刷新房間資訊和流地址
    _infoRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _refreshStationInfo(),
    );
    
    // 每秒更新已播放時長
    _playDurationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updatePlayDuration(),
    );
  }

  Future<void> _refreshStationInfo() async {
    if (state.currentStation == null) return;
    
    final info = await _radioSource.getStationInfo(state.currentStation!);
    state = state.copyWith(
      viewerCount: info.viewerCount,
      liveStartTime: info.liveStartTime,
    );
    
    // 如果流地址過期，刷新並重新播放
    // ...
  }
}
```

## 實現優先級

### Phase 1: 基礎功能
1. RadioStation model + Repository
2. RadioSource（URL 解析、流地址獲取）
3. RadioController 基礎播放
4. RadioPage 列表 UI
5. 添加電台功能

### Phase 2: 整合
6. 底部導航添加電台 Tab
7. Mini player 模式切換
8. 互斥播放機制

### Phase 3: 增強
9. 自動重連
10. 定時刷新房間資訊
11. 編輯/刪除/排序功能

## 注意事項

1. **流地址有效期**：Bilibili 直播流地址可能在幾小時後過期，需要定期刷新
2. **直播狀態檢查**：播放前應檢查直播是否仍在進行，未開播時顯示適當提示
3. **網絡錯誤處理**：直播流對網絡敏感，需要良好的錯誤提示和重連機制
4. **Windows 兼容性**：media_kit 在 Windows 上對 HLS/FLV 的支持良好，應該沒問題
5. **Android 後台**：共用 MediaKitAudioService，已有的後台播放機制應該直接適用
