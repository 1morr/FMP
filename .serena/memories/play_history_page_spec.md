# 播放歷史頁面需求規格

## 頁面入口
- **位置**：首頁「最近播放」區域的「查看全部」按鈕
- **路由**：`/history`

## 頁面佈局

### AppBar
- 標題：「播放歷史」
- 右側操作按鈕：
  - 日曆按鈕（DatePicker 彈窗，選擇日期後跳轉到該日期）
  - 搜索按鈕（展開搜索框，搜索標題/藝術家）
  - 更多菜單（清空所有歷史）

### 統計區域（頂部卡片）
- 今日/本週播放數量
- 總播放數
- 播放時長統計（基於 durationMs 累計）

### 篩選與排序區域
- **FilterChip**（與搜索頁一致）：
  - 只顯示「Bilibili」和「YouTube」兩個選項
  - 兩個都勾選 = 顯示全部
  - 使用 `Set<SourceType>` 管理狀態
- **排序**（DropdownButton）：
  - 時間倒序（默認）
  - 時間正序
  - 播放次數（全局 vs 篩選範圍可切換）
  - 歌曲時長

### 主要內容區：垂直時間軸
- **視覺樣式**：左側連續豎線 + 圓點節點
- **分組方式**：每日分組（「今天」「昨天」「2月5日」等）
- **列表項**：標準 ListTile 佈局
  - 封面縮略圖（48x48）
  - 標題（最多2行）+ 藝術家
  - 播放時間（絕對時間格式）
  - 音源圖標（與探索頁一致）
  - 操作菜單按鈕

### 時間顯示格式
- 今天：時分（14:32）
- 超過1天：月日+時分（2月5日 14:32）
- 超過1年：年月日（2025年2月5日）

## 交互功能

### 歌曲項操作
- **點擊**：臨時播放（`playTemporary`）
- **長按**：進入多選模式
- **操作菜單**：
  - 播放
  - 下一首播放
  - 加入隊列
  - 加入歌單
  - 下載
  - 刪除此記錄
  - 刪除此歌的所有記錄

### 多選模式
- 長按任意項進入
- 點擊選中/取消選中
- 底部操作欄：批量刪除、批量加入隊列、批量加入歌單
- 點擊空白或返回退出多選

### 刪除功能
- 單條刪除（菜單或左滑）
- 刪除某首歌的所有記錄（菜單）
- 清空所有歷史（AppBar 更多菜單，需確認對話框）

## 數據層擴展

### PlayHistoryRepository 需要新增方法
- `getHistoryByDateRange(DateTime start, DateTime end)` - 按日期範圍查詢
- `getHistoryBySource(SourceType type)` - 按音源篩選
- `searchHistory(String keyword)` - 關鍵詞搜索
- `deleteAllForTrack(String trackKey)` - 刪除某首歌的所有記錄
- `getPlayCountForTrack(String trackKey)` - 獲取某首歌的播放次數

### Provider 需要新增
- `playHistoryPageProvider` - 頁面狀態管理（篩選、排序、搜索、分頁）
- `playHistoryStatsProvider` - 統計數據

## 文件結構
```
lib/
├── data/repositories/play_history_repository.dart  # 新增方法 + PlayHistoryStats + HistorySortOrder
├── providers/play_history_provider.dart            # 新增 providers 和 notifiers
├── ui/
│   ├── pages/history/play_history_page.dart        # 播放歷史主頁面
│   └── router.dart                                 # 添加 /history 路由
└── ui/pages/home/home_page.dart                    # 添加「查看全部」入口
```

## 實現狀態
- [x] PlayHistoryRepository 擴展
- [x] PlayHistoryPageProvider 狀態管理
- [x] 播放歷史頁面 UI
- [x] 路由配置
- [x] 首頁入口

## 參考頁面
- 探索頁（ExplorePage）- TrackTile 樣式、菜單操作
- 搜索頁（SearchPage）- FilterChip 實現
- 歌單詳情頁（PlaylistDetailPage）- 多選模式