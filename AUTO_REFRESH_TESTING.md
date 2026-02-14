# 自动刷新功能测试指南

## 功能概述

已成功实现歌单自动刷新功能，包括：

1. ✅ 在编辑对话框中添加自动刷新设置 UI
2. ✅ 后台监控服务，每小时检查一次需要刷新的歌单
3. ✅ 应用启动时自动检查并刷新过期歌单
4. ✅ 同时只刷新一个歌单（避免 API 限流）
5. ✅ 导入后默认不开启自动刷新
6. ✅ 刷新完成后更新 `lastRefreshed` 时间戳

## 实现的文件

### 新增文件
- `lib/services/refresh/auto_refresh_service.dart` - 自动刷新后台服务

### 修改的文件
- `lib/app.dart` - 初始化自动刷新服务
- `lib/data/models/playlist.dart` - 已有字段（无需修改）
- `lib/services/library/playlist_service.dart` - 添加自动刷新参数
- `lib/providers/playlist_provider.dart` - 更新方法签名
- `lib/providers/refresh_provider.dart` - 保存 lastRefreshed 时间戳
- `lib/ui/pages/library/widgets/create_playlist_dialog.dart` - 添加自动刷新 UI
- `lib/i18n/zh-CN/library.i18n.json` - 简体中文翻译
- `lib/i18n/en/library.i18n.json` - 英文翻译
- `lib/i18n/zh-TW/library.i18n.json` - 繁体中文翻译

## 测试步骤

### 1. 导入歌单并启用自动刷新

1. 启动应用
2. 进入「音乐库」页面
3. 点击「导入歌单」按钮
4. 粘贴一个 B站/YouTube/网易云/QQ音乐/Spotify 歌单链接
5. 完成导入后，长按歌单卡片，选择「编辑歌单」
6. 向下滚动到「自动刷新」部分
7. 打开「启用自动刷新」开关
8. 选择刷新间隔（例如：1 小时）
9. 确认「更新时通知」已勾选
10. 点击「保存」

**预期结果：**
- 歌单的 `refreshIntervalHours` 字段被设置为选择的值
- 歌单的 `notifyOnUpdate` 字段为 `true`

### 2. 测试手动刷新更新时间戳

1. 在音乐库页面，长按已导入的歌单
2. 选择「刷新歌单」
3. 等待刷新完成

**预期结果：**
- 刷新完成后显示成功提示
- 再次编辑歌单，应该能看到「上次刷新: 刚刚」

### 3. 测试自动刷新触发

**方法 A：修改数据库（推荐）**

1. 导入一个歌单
2. 编辑歌单 → 启用自动刷新 → 间隔选择 1 小时
3. 保存
4. 使用数据库工具（如 Isar Inspector）将 `lastRefreshed` 改为 2 小时前
5. 等待最多 30 分钟（服务每 30 分钟检查一次）

**预期结果：**
- 30 分钟内自动触发刷新
- 刷新完成后显示通知
- `lastRefreshed` 更新为当前时间

**方法 B：快速测试（临时修改代码）**

1. 临时修改 `lib/services/refresh/auto_refresh_service.dart`：
```dart
// 将检查间隔从 30 分钟改为 1 分钟
_checkTimer = Timer.periodic(
  const Duration(minutes: 1),  // 原来是 minutes: 30
  (_) => _checkAndRefresh(),
);
```

2. 重启应用
3. 导入一个歌单，编辑 → 启用自动刷新 → 间隔选择 1 小时
4. 使用数据库工具将 `lastRefreshed` 改为 2 小时前
5. 等待 1 分钟

**测试完成后记得改回 30 分钟！**

**方法 C：应用启动检查**

**预期结果：**
- 自动触发刷新
- 刷新完成后显示通知（如果启用了通知）
- `lastRefreshed` 更新为当前时间

### 4. 测试应用启动时检查

1. 使用数据库工具将某个歌单的 `lastRefreshed` 改为 2 小时前
2. 确保该歌单的 `refreshIntervalHours` 为 1
3. 完全关闭应用
4. 重新启动应用

**预期结果：**
- 应用启动后自动检查并刷新过期歌单
- 刷新完成后显示通知

### 5. 测试并发限制（同时只刷新一个）

1. 创建 2 个或更多导入的歌单
2. 全部启用自动刷新，间隔设为 1 小时
3. 使用数据库工具将它们的 `lastRefreshed` 都改为 2 小时前
4. 触发检查（等待或重启应用）

**预期结果：**
- 歌单按 `lastRefreshed` 时间排序，最久未刷新的优先
- 同时只有一个歌单在刷新
- 第一个完成后，等待 5 秒再开始下一个

### 6. 测试禁用自动刷新

1. 编辑已启用自动刷新的歌单
2. 关闭「启用自动刷新」开关
3. 保存

**预期结果：**
- `refreshIntervalHours` 被设置为 `null`
- 该歌单不再被自动刷新

### 7. 测试 UI 显示

1. 编辑一个已刷新过的导入歌单
2. 查看「自动刷新」部分

**预期结果：**
- 如果启用了自动刷新，显示当前设置
- 显示「上次刷新」时间（相对时间格式）
  - 刚刚
  - X 分钟前
  - X 小时前
  - X 天前
  - 或完整日期时间

## 日志检查

查看应用日志，应该能看到：

```
[AutoRefreshService] Starting auto-refresh service
[AutoRefreshService] Found X playlists needing refresh
[AutoRefreshService] Auto-refreshing playlist: 歌单名称
[RefreshManagerNotifier] Refresh completed for playlist: 歌单名称
```

## 已知限制

1. **检查频率**：每小时检查一次，不是精确到分钟
2. **并发限制**：同时只刷新一个歌单，大量歌单需要排队
3. **网络依赖**：需要网络连接才能刷新
4. **API 限流**：频繁刷新可能触发平台限流

## 故障排除

### 自动刷新没有触发

1. 检查 `refreshIntervalHours` 是否为 `null`
2. 检查 `lastRefreshed` 是否已过期
3. 检查应用日志是否有错误
4. 确认 `AutoRefreshService` 已启动

### 刷新失败

1. 检查网络连接
2. 检查源平台是否可访问
3. 查看错误日志
4. 尝试手动刷新确认问题

## 性能考虑

- 自动刷新服务使用 `Timer.periodic`，内存占用极小
- 每次检查只查询数据库，不进行网络请求
- 只有需要刷新的歌单才会触发网络请求
- 刷新间隔之间有 5 秒延迟，避免请求过快

## 未来改进建议

1. 添加全局设置：
   - 启用/禁用全局自动刷新
   - 默认刷新间隔
   - 最大并发刷新数
   - 仅在 WiFi 下刷新

2. 智能刷新：
   - 根据歌单更新频率动态调整间隔
   - 夜间暂停刷新

3. 刷新历史：
   - 记录刷新历史
   - 显示刷新统计

4. 更细粒度的通知：
   - 新增歌曲通知
   - 删除歌曲通知
   - 批量刷新完成通知
