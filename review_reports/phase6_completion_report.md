# Phase 6 完成报告：UI 规范统一

## 完成时间
2026-02-17

## 任务完成情况

### Task 6.1: 消除硬编码颜色 ✅
**文件修改：**
1. `lib/ui/pages/settings/settings_page.dart`
   - Line 298: `Color(0xFF6750A4)` → `Theme.of(context).colorScheme.primary`
   - Line 1473: `Colors.grey` → `Theme.of(context).colorScheme.outline` (hint text)
   - Line 1535: `Colors.grey` → `Theme.of(context).colorScheme.outline` (unset binding text)

2. `lib/ui/pages/settings/download_manager_page.dart`
   - `_buildStatusIcon()` 方法中的状态图标颜色：
     - `Colors.orange` → `colorScheme.tertiary` (pending)
     - `Colors.grey` → `colorScheme.outline` (paused)
     - `Colors.green` → `colorScheme.primary` (completed)
     - `Colors.red` → `colorScheme.error` (failed)

**效果：** 所有硬编码颜色已替换为主题感知的 colorScheme 属性，确保深色/浅色主题正确支持。

### Task 6.2: 消除硬编码 BorderRadius 和动画时长 ✅
**文件修改：**
1. `lib/ui/widgets/horizontal_scroll_section.dart`
   - Line 126: `Duration(milliseconds: 400)` → `AnimationDurations.normal`

2. `lib/ui/pages/settings/lyrics_source_settings_page.dart`
   - Line 128: `BorderRadius.circular(12)` → `AppRadius.borderRadiusLg`

**效果：** 使用 UI 常量系统统一管理圆角和动画时长，提高代码可维护性。

### Task 6.3: 统一菜单项内部布局风格 ✅
**文件修改：**
1. `lib/ui/pages/library/library_page.dart`
   - PlaylistCard 菜单项从 `Row` 风格改为 `ListTile` 风格
   - 包括：play_mix, add_all, shuffle_add, edit, refresh, delete

2. `lib/ui/pages/home/home_page.dart`
   - PlaylistCard 菜单项从 `Row` 风格改为 `ListTile` 风格
   - RadioStation 删除菜单项从 `Row` 风格改为 `ListTile` 风格

**统一后的格式：**
```dart
PopupMenuItem(
  value: 'action',
  child: ListTile(
    leading: const Icon(Icons.icon_name),
    title: Text(t.text),
    contentPadding: EdgeInsets.zero,
  ),
),
```

**效果：** 所有菜单项使用统一的 ListTile 布局，视觉一致性更好，间距和对齐更标准。

### Task 6.4: 提取 PlaylistCard 共享操作 ✅
**新建文件：**
- `lib/ui/widgets/playlist_card_actions.dart`

**提取的共享方法：**
1. `PlaylistCardActions.addAllToQueue()` - 添加歌单所有歌曲到队列
2. `PlaylistCardActions.shuffleAddToQueue()` - 随机添加歌单所有歌曲到队列
3. `PlaylistCardActions.playMix()` - 播放 Mix 歌单

**文件修改：**
1. `lib/ui/pages/library/library_page.dart`
   - 导入 `playlist_card_actions.dart`
   - `_addAllToQueue()`, `_shuffleAddToQueue()`, `_playMix()` 方法改为调用共享工具类

2. `lib/ui/pages/home/home_page.dart`
   - 导入 `playlist_card_actions.dart`
   - `_addAllToQueue()`, `_shuffleAddToQueue()`, `_playMix()` 方法改为调用共享工具类

**效果：** 消除了代码重复，两个页面的 PlaylistCard 共享相同的业务逻辑实现，降低维护成本。

## 总结

Phase 6 的所有 4 个任务已全部完成：
- ✅ Task 6.1: 消除硬编码颜色
- ✅ Task 6.2: 消除硬编码 BorderRadius 和动画时长
- ✅ Task 6.3: 统一菜单项内部布局风格
- ✅ Task 6.4: 提取 PlaylistCard 共享操作

**代码质量提升：**
1. 主题一致性：所有颜色使用 colorScheme，支持深色/浅色主题
2. UI 规范统一：使用 UI 常量系统管理圆角和动画时长
3. 视觉一致性：所有菜单项使用统一的 ListTile 布局
4. 代码复用：提取共享操作到工具类，减少重复代码

## 代码修复

在完成所有任务后，进行了代码静态分析并修复了以下问题：

1. **导入路径修复** (`lib/ui/widgets/playlist_card_actions.dart`)
   - 修正了相对导入路径
   - 移除了不存在的包导入

2. **缺失导入添加**
   - `lib/ui/widgets/horizontal_scroll_section.dart`: 添加 `ui_constants.dart` 导入
   - `lib/ui/pages/settings/lyrics_source_settings_page.dart`: 添加 `ui_constants.dart` 导入

3. **方法签名修复** (`lib/ui/pages/settings/download_manager_page.dart`)
   - `_buildStatusIcon()` 添加 `BuildContext context` 参数

4. **未使用导入清理**
   - `lib/ui/pages/library/library_page.dart`: 移除 `source_provider.dart`, `track.dart`, `audio_provider.dart`
   - `lib/ui/pages/home/home_page.dart`: 移除 `source_provider.dart`

**验证结果：**
```
flutter analyze --no-pub
No issues found! (ran in 6.7s)
```

## 建议后续工作

- 考虑在其他页面中也使用 `PlaylistCardActions` 工具类
- 继续检查项目中是否还有其他硬编码的 UI 值需要统一
