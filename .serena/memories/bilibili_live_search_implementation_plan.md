# Bilibili 直播间搜索功能实现计划

## 一、功能概述

在搜索页面添加 Bilibili 直播间搜索功能，用户可以搜索主播/直播间，查看直播状态，播放直播流。

## 二、筛选器设计

```
[全部音源] [Bilibili] [YouTube]  |  [全部直播间] [未开播] [已开播]
     ↑ 音源筛选                        ↑ 直播间状态筛选（仅 Bilibili 可用）
```

## 三、搜索逻辑

| 筛选条件 | 搜索 API | 结果处理 |
|---------|---------|---------|
| **全部直播间** | `live_room` + `bili_user` | 合并去重，显示所有有直播间的结果 |
| **未开播** | `bili_user` | 筛选 `room_id > 0` 且 `is_live = false` |
| **已开播** | `live_room` + `bili_user` | 筛选 `is_live = true` 或 `liveStatus = 1` |

## 四、Bilibili API 端点

### 4.1 搜索直播间 (仅正在直播)
- URL: `https://api.bilibili.com/x/web-interface/search/type?search_type=live_room`
- 返回字段: `roomid`, `uid`, `uname`, `title`, `user_cover`, `cate_name`, `online`

### 4.2 搜索用户 (包括未开播)
- URL: `https://api.bilibili.com/x/web-interface/search/type?search_type=bili_user`
- 返回字段: `mid`, `uname`, `room_id`, `upic`, `usign`, `fans`
- 注意: `room_id = 0` 表示没有直播间

### 4.3 获取直播间详情
- URL: `https://api.live.bilibili.com/room/v1/Room/get_info?room_id=xxx`
- 返回字段: `room_id`, `uid`, `title`, `live_status`, `user_cover`, `area_name`, `online`

### 4.4 获取直播流
- URL: `https://api.live.bilibili.com/room/v1/Room/playUrl?cid=xxx&platform=h5`
- 返回: HLS (m3u8) 流地址

## 五、数据模型

### 5.1 LiveRoomFilter 枚举
```dart
enum LiveRoomFilter {
  all,      // 全部直播间
  offline,  // 未开播
  online,   // 已开播
}
```

### 5.2 LiveRoom 模型
```dart
class LiveRoom {
  final int roomId;       // 直播间 ID
  final int uid;          // 主播 UID
  final String uname;     // 主播名
  final String title;     // 直播间标题
  final String? cover;    // 封面
  final String? face;     // 头像
  final bool isLive;      // 是否正在直播
  final int? online;      // 在线人数
  final String? areaName; // 分区名
  final String? tags;     // 标签
  final int liveStatus;   // 0=未开播, 1=直播中, 2=轮播中
}
```

### 5.3 LiveSearchResult 模型
```dart
class LiveSearchResult {
  final List<LiveRoom> rooms;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasMore;
}
```

## 六、实现步骤

### 步骤 1: 创建数据模型
- 文件: `lib/data/models/live_room.dart`
- 内容: `LiveRoomFilter`, `LiveRoom`, `LiveSearchResult`

### 步骤 2: BilibiliSource 添加直播搜索 API
- 文件: `lib/data/sources/bilibili_source.dart`
- 新增方法:
  - `_searchLiveRoomApi()` - 搜索正在直播的直播间
  - `_searchBiliUserWithRoomApi()` - 搜索有直播间的用户
  - `searchLiveRooms()` - 综合搜索入口
  - `getLiveRoomInfo()` - 获取直播间详情
  - `getLiveStreamUrl()` - 获取直播流地址

### 步骤 3: 扩展 SearchState 和 SearchNotifier
- 文件: `lib/providers/search_provider.dart`
- SearchState 新增字段:
  - `liveRoomFilter` - 直播间筛选条件
  - `liveRoomResults` - 直播间搜索结果
  - `isLiveSearchMode` - 是否为直播搜索模式
- SearchNotifier 新增方法:
  - `setLiveRoomFilter()` - 设置直播间筛选
  - `searchLiveRooms()` - 执行直播间搜索
  - `loadMoreLiveRooms()` - 加载更多直播间

### 步骤 4: 修改搜索页面 UI
- 文件: `lib/ui/pages/search/search_page.dart`
- 修改 `_buildSourceFilter()`:
  - 将"全部"改为"全部音源"
  - 当选择 Bilibili 时显示直播间筛选器
- 修改 `_buildSearchResults()`:
  - 当有直播间筛选时显示直播间结果

### 步骤 5: 创建 LiveRoomTile 组件
- 文件: `lib/ui/pages/search/search_page.dart` (或单独文件)
- 组件: `_LiveRoomTile`
- 显示内容:
  - 封面/头像
  - 主播名
  - 直播状态标签（直播中/未开播/轮播中）
  - 分区
  - 在线人数（如果直播中）
  - 操作菜单

### 步骤 6: 实现直播流播放
- 获取 HLS 流地址
- 集成到现有播放器（media_kit 支持 HLS）

## 七、UI 组件设计

### 7.1 直播间筛选器
```dart
// 当选择 Bilibili 时显示
Row(
  children: [
    ChoiceChip(label: Text('全部直播间'), selected: filter == LiveRoomFilter.all),
    ChoiceChip(label: Text('未开播'), selected: filter == LiveRoomFilter.offline),
    ChoiceChip(label: Text('已开播'), selected: filter == LiveRoomFilter.online),
  ],
)
```

### 7.2 LiveRoomTile 布局
```
┌─────────────────────────────────────────────────┐
│ [封面]  主播名                    [直播中] [菜单] │
│  48x48  直播间标题                  分区  人气   │
└─────────────────────────────────────────────────┘
```

## 八、注意事项

1. **API 请求需要 buvid3 Cookie** - 已在 BilibiliSource 中实现
2. **HTML 标签清理** - 搜索结果中的 `<em class="keyword">` 需要清理
3. **图片 URL 修复** - 需要添加 `https:` 前缀
4. **去重逻辑** - 合并 live_room 和 bili_user 结果时按 roomId 去重
5. **直播状态** - 0=未开播, 1=直播中, 2=轮播中

## 九、测试文件

测试 demo 已创建: `test/bilibili_live_api_test.dart`
