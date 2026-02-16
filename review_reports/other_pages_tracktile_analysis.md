# 其他页面 TrackTile 统一分析

## 当前状态

### 已统一使用 TrackTile 组件 ✅
1. **explore_page.dart** - `_ExploreTrackTile` ✅
2. **home_page.dart** - `_RankingTrackTile` ✅

### 仍使用自定义实现的页面

| 页面 | 组件 | 使用 | 特殊需求 | 建议 |
|------|------|------|---------|------|
| **playlist_detail_page** | `_TrackListTile` | ListTile | 分P显示、下载标记、选择模式 | 🟡 可选统一 |
| **search_page** | `_LocalTrackTile` | ListTile | 左侧缩进、分P标记 | 🟡 可选统一 |
| **downloaded_category_page** | `_DownloadedTrackTile` | ListTile | 分P显示、缩进 | 🟡 可选统一 |
| **queue_page** | `_DraggableQueueItem` | InkWell | 拖拽功能、固定高度 | 🔴 不建议统一 |
| **import_preview_page** | `_UnmatchedTrackTile` | ListTile | 匹配选择、特殊布局 | 🔴 不建议统一 |
| **import_preview_page** | `_AlternativeTrackTile` | ListTile | 备选项显示 | 🔴 不建议统一 |

## 详细分析

### 1. playlist_detail_page.dart - `_TrackListTile`

**当前实现**: 标准 ListTile

**特殊功能**:
- 分P显示（多P视频）
- 下载状态标记
- 选择模式
- 左侧缩进（分P子项）

**是否适合统一**: 🟡 **可选**

**统一方案**:
```dart
// 可以使用 TrackTile，但需要自定义 leading 和 subtitle
TrackTile(
  track: track,
  isPlaying: isPlaying,
  onTap: onTap,
  leading: isPartOfMultiPage ? _buildPageIndicator() : null,  // 需要扩展 TrackTile
  subtitle: _buildSubtitleWithDownloadIcon(),
  trailing: _buildTrailing(),
)
```

**问题**: TrackTile 目前不支持自定义 `leading`，需要扩展

**建议**: **暂不统一**，因为：
- 需要大量自定义逻辑
- 当前 ListTile 实现已经很好
- 统一收益不大

---

### 2. search_page.dart - `_LocalTrackTile`

**当前实现**: ListTile + 左侧缩进

**特殊功能**:
- 左侧缩进 56dp（表示是本地歌单中的歌曲）
- 分P标记（P1, P2...）
- 选择模式

**是否适合统一**: 🟡 **可选**

**统一方案**:
```dart
Padding(
  padding: EdgeInsets.only(left: 56),
  child: TrackTile(
    track: track,
    isPlaying: isPlaying,
    onTap: onTap,
    // 需要自定义 leading 显示 P1, P2...
  ),
)
```

**问题**: 同样需要自定义 `leading`

**建议**: **暂不统一**

---

### 3. downloaded_category_page.dart - `_DownloadedTrackTile`

**当前实现**: ListTile + 可选缩进

**特殊功能**:
- 分P显示
- 可选左侧缩进
- 文件路径相关逻辑

**是否适合统一**: 🟡 **可选**

**建议**: **暂不统一**，与 playlist_detail_page 类似

---

### 4. queue_page.dart - `_DraggableQueueItem`

**当前实现**: InkWell + 自定义布局

**特殊功能**:
- **拖拽排序**（核心功能）
- 固定高度（拖拽计算需要）
- 自定义 feedback 样式
- 删除按钮

**是否适合统一**: 🔴 **不建议**

**原因**:
- 拖拽功能需要完全自定义布局
- 需要精确控制高度和样式
- TrackTile 无法满足这些需求

**建议**: **保持现状**

---

### 5. import_preview_page.dart - `_UnmatchedTrackTile` & `_AlternativeTrackTile`

**当前实现**: ListTile + 特殊布局

**特殊功能**:
- 匹配选择界面
- 备选项显示
- 复杂的交互逻辑

**是否适合统一**: 🔴 **不建议**

**建议**: **保持现状**

---

## 总结

### 当前统一情况

| 状态 | 页面数 | 页面 |
|------|--------|------|
| ✅ 已统一 | 2 | explore_page, home_page |
| 🟡 可选统一 | 3 | playlist_detail, search, downloaded_category |
| 🔴 不建议统一 | 3 | queue, import_preview (2个) |

### 建议

**不建议继续统一其他页面**，原因：

1. **功能差异大**
   - 其他页面有特殊的显示需求（分P、缩进、下载标记）
   - TrackTile 需要大量扩展才能支持

2. **收益递减**
   - 已统一的 2 个页面是最简单、最标准的场景
   - 其他页面统一的成本 > 收益

3. **代码复杂度**
   - 如果强行统一，TrackTile 会变得非常复杂
   - 需要大量可选参数和条件判断
   - 反而降低可维护性

4. **当前实现已经很好**
   - 所有页面都使用标准 ListTile
   - 样式已经统一（都遵循 Material Design）
   - 没有明显的不一致问题

### 如果一定要统一

需要扩展 TrackTile 支持以下功能：

```dart
class TrackTile extends StatelessWidget {
  // 现有参数
  final Track track;
  final bool isPlaying;
  final int? rank;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? subtitle;

  // 新增参数（支持其他页面）
  final Widget? leading;           // 自定义 leading（分P标记等）
  final EdgeInsets? padding;       // 自定义内边距（缩进）
  final bool indent;               // 是否缩进
  final double indentWidth;        // 缩进宽度
  final bool showDownloadIcon;     // 是否显示下载图标
  final String? pageLabel;         // 分P标签（P1, P2...）

  // ... 更多参数
}
```

**问题**: 参数过多，组件变得臃肿，违反单一职责原则

### 最佳实践建议

**保持现状**，原因：

1. ✅ **已统一的页面**（explore, home）是最需要统一的
   - 这两个页面使用排名模式，之前有性能问题
   - 统一后样式一致，代码简洁

2. ✅ **其他页面使用标准 ListTile**
   - 符合 Material Design 规范
   - 样式已经统一
   - 代码清晰易懂

3. ✅ **特殊页面保持自定义**
   - queue_page: 拖拽功能必须自定义
   - import_preview_page: 复杂交互逻辑

### 结论

**当前的统一程度已经足够**：
- 排行榜页面（有排名）使用 TrackTile
- 标准列表页面使用 ListTile
- 特殊功能页面自定义实现

这是一个**平衡的方案**，既保证了样式统一，又保持了代码的简洁性和可维护性。

## 如果用户坚持要统一

如果你确实想统一所有页面，我建议：

1. **先扩展 TrackTile 组件**
   - 添加 `leading` 参数支持自定义
   - 添加 `padding` 参数支持缩进
   - 添加更多可选参数

2. **逐步替换**
   - 先替换 playlist_detail_page（最简单）
   - 再替换 search_page
   - 最后替换 downloaded_category_page

3. **保持特殊页面不变**
   - queue_page 必须保持自定义
   - import_preview_page 保持自定义

但我的建议是：**不要这样做**，因为成本太高，收益太低。
