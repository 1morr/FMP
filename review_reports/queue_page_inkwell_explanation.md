# Queue Page 为什么使用 InkWell 而不是 ListTile

## 代码分析

### Queue Page 的实现

```dart
// lib/ui/pages/queue/queue_page.dart (Line 537-606)

Widget buildTileContent({bool isFeedback = false}) {
  return SizedBox(
    height: itemHeight,
    child: Material(
      color: isFeedback ? colorScheme.surfaceContainerHigh : Colors.transparent,
      elevation: isFeedback ? 8 : 0,
      borderRadius: isFeedback ? AppRadius.borderRadiusMd : null,
      child: InkWell(                    // ← 使用 InkWell
        onTap: isFeedback ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              TrackThumbnail(...),       // 封面
              SizedBox(width: 12),
              Expanded(                  // 歌曲信息
                child: Column(...),
              ),
              if (track.durationMs != null)
                Text(...),               // 时长
              if (!isFeedback)
                IconButton(...),         // 删除按钮
            ],
          ),
        ),
      ),
    ),
  );
}
```

## 为什么不用 ListTile？

### 原因 1: 拖拽功能需要自定义布局

Queue Page 使用了 **ReorderableListView** 实现拖拽排序功能：

```dart
class _DraggableQueueItem extends StatelessWidget {
  // 拖拽相关回调
  final VoidCallback onDragStart;
  final void Function(int) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  // 拖拽状态
  final bool isDragging;
  final bool isDragTarget;

  // ...
}
```

**关键点**：
- 拖拽时需要显示 **feedback widget**（拖拽时跟随手指的半透明副本）
- Feedback widget 需要与原始 widget **完全相同的布局**
- 使用 `buildTileContent(isFeedback: true/false)` 复用布局代码

**如果用 ListTile**：
```dart
// ❌ 问题：ListTile 的内部结构无法完全复制
Widget buildFeedback() {
  return ListTile(...);  // 拖拽反馈的样式会不一致
}
```

**使用 InkWell**：
```dart
// ✅ 正确：完全控制布局，feedback 和原始项完全一致
Widget buildTileContent({bool isFeedback = false}) {
  return InkWell(
    child: Row(...),  // 自定义布局，可以精确复制
  );
}
```

### 原因 2: 需要精确控制高度

```dart
return SizedBox(
  height: itemHeight,  // ← 固定高度，用于拖拽计算
  child: Material(...),
);
```

**拖拽功能需要**：
- 固定的 `itemHeight`（用于计算拖拽位置）
- 精确的边距和间距（保证拖拽时对齐）

**ListTile 的问题**：
- 高度由内容自动计算
- 内部间距不可精确控制
- 拖拽时可能出现对齐问题

### 原因 3: 自定义拖拽反馈样式

```dart
Material(
  color: isFeedback ? colorScheme.surfaceContainerHigh : Colors.transparent,
  elevation: isFeedback ? 8 : 0,                    // ← 拖拽时有阴影
  borderRadius: isFeedback ? AppRadius.borderRadiusMd : null,  // ← 拖拽时有圆角
  child: InkWell(...),
)
```

**拖拽反馈需要**：
- 不同的背景色（半透明高亮）
- 阴影效果（elevation: 8）
- 圆角边框

**ListTile 无法实现**：
- ListTile 的 Material 层在内部，无法自定义
- 无法根据 `isFeedback` 动态改变样式

### 原因 4: trailing 有多个元素

```dart
Row(
  children: [
    TrackThumbnail(...),
    Expanded(child: Column(...)),
    if (track.durationMs != null)
      Text(...),              // ← 时长
    if (!isFeedback)
      IconButton(...),        // ← 删除按钮
  ],
)
```

**Queue Page 的 trailing 区域有**：
- 时长文本
- 删除按钮

**如果用 ListTile**：
```dart
ListTile(
  trailing: Row(              // ← 可以用 Row
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(...),
      IconButton(...),
    ],
  ),
)
```

**但这样会有问题**：
- `trailing` 的 Row 宽度不可控
- 与拖拽功能的精确布局冲突
- 无法实现 feedback 样式的完全复制

## 对比：为什么 Playlist Detail Page 可以用 ListTile？

### Playlist Detail Page

```dart
ListTile(
  leading: TrackThumbnail(...),
  title: Text(...),
  subtitle: Row(...),
  trailing: Row(
    children: [
      Text(duration),
      PopupMenuButton(...),
    ],
  ),
)
```

**关键区别**：
- ✅ **没有拖拽功能**
- ✅ 不需要固定高度
- ✅ 不需要自定义 feedback
- ✅ ListTile 的默认样式就够用

### Queue Page

```dart
InkWell(
  child: Row(
    children: [
      TrackThumbnail(...),
      Expanded(child: Column(...)),
      Text(duration),
      IconButton(remove),
    ],
  ),
)
```

**关键需求**：
- ❌ **有拖拽功能** → 需要自定义布局
- ❌ 需要固定高度 → ListTile 高度自动
- ❌ 需要自定义 feedback → ListTile 无法实现
- ❌ 需要精确控制间距 → ListTile 间距固定

## 总结

### Queue Page 使用 InkWell 的原因

| 需求 | ListTile | InkWell | 结论 |
|------|----------|---------|------|
| 拖拽功能 | ❌ 无法复制内部结构 | ✅ 完全控制布局 | 必须用 InkWell |
| 固定高度 | ❌ 高度自动计算 | ✅ 可精确控制 | 必须用 InkWell |
| 自定义 feedback | ❌ Material 层在内部 | ✅ 可自定义 Material | 必须用 InkWell |
| 精确间距 | ❌ 间距固定 | ✅ 完全控制 | 必须用 InkWell |

### 使用原则

**使用 ListTile**：
- ✅ 标准列表项
- ✅ 不需要拖拽
- ✅ 不需要精确控制布局
- ✅ leading 只有单个 widget

**使用 InkWell**：
- ✅ 需要拖拽功能
- ✅ 需要自定义 feedback
- ✅ 需要精确控制高度/间距
- ✅ leading 有多个元素（如排名+封面）
- ✅ 需要自定义 Material 样式

## 代码示例对比

### ❌ 如果 Queue Page 用 ListTile（会有问题）

```dart
// 问题 1: 无法复制 ListTile 的内部结构用于 feedback
Widget buildFeedback() {
  return ListTile(...);  // feedback 样式会不一致
}

// 问题 2: 无法自定义 Material 层
ListTile(...)  // 无法根据 isFeedback 改变背景色和阴影

// 问题 3: 高度不固定
ListTile(...)  // 拖拽计算会出错
```

### ✅ 实际使用 InkWell（正确）

```dart
// 优势 1: 可以完全复制布局
Widget buildTileContent({bool isFeedback = false}) {
  return InkWell(child: Row(...));  // 完全一致
}

// 优势 2: 可以自定义 Material 层
Material(
  color: isFeedback ? highlight : transparent,
  elevation: isFeedback ? 8 : 0,
  child: InkWell(...),
)

// 优势 3: 固定高度
SizedBox(height: itemHeight, child: InkWell(...))
```

## 结论

Queue Page 使用 InkWell 是**正确且必要的选择**，因为：
1. 拖拽功能需要自定义布局和 feedback
2. 需要精确控制高度和间距
3. 需要动态改变 Material 样式
4. ListTile 无法满足这些需求

这不是性能优化，而是**功能需求**决定的架构选择。
