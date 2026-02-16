# 数据库迁移和版本更新指南

## 问题背景

当旧版本 APK/Windows Installer 升级到新版本时，如果新版本添加了数据库字段，Isar 会使用类型默认值：
- `int` → `0`
- `bool` → `false`
- `String?` → `null`
- `List` → `[]`

如果代码期望的默认值不是这些，就会导致功能异常。

## Isar 自动迁移机制

**Isar 3.x 会自动处理 schema 变更：**
- **添加字段**：新字段使用类型默认值（int=0, bool=false 等）
- **删除字段**：旧数据中的字段被忽略
- **重命名字段**：视为删除旧字段+添加新字段（数据丢失）
- **修改类型**：可能导致错误或数据丢失

**注意：** Isar 没有 `version` 参数，不需要手动管理版本号。

## 解决方案：迁移函数

位置：`lib/providers/database_provider.dart`

### `_migrateDatabase()` 函数

**职责：**
1. 初始化新安装的数据库（创建默认 Settings、PlayQueue）
2. 修复旧版本升级后的异常值
3. 为新字段设置合理的默认值

**工作原理：**
```dart
Future<void> _migrateDatabase(Isar isar) async {
  await isar.writeTxn(() async {
    var settings = await isar.settings.get(0);
    if (settings == null) {
      // 全新安装
      await isar.settings.put(Settings());
    } else {
      // 旧版本升级，检查并修复异常值
      bool needsUpdate = false;
      
      if (settings.maxConcurrentDownloads < 1) {
        settings.maxConcurrentDownloads = 3;
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        await isar.settings.put(settings);
      }
    }
  });
}
```

### 当前迁移逻辑

修复以下字段的异常值：
- `maxConcurrentDownloads`：< 1 或 > 5 → 重置为 3
- `maxCacheSizeMB`：< 1 → 重置为 32
- `audioQualityLevelIndex`：不在 0-2 范围 → 重置为 0
- `downloadImageOptionIndex`：不在 0-2 范围 → 重置为 1
- `lyricsDisplayModeIndex`：不在 0-2 范围 → 重置为 0
- `maxLyricsCacheFiles`：< 1 → 重置为 50
- `audioFormatPriority`：空字符串 → 'aac,opus'
- `youtubeStreamPriority`：空字符串 → 'audioOnly,muxed,hls'
- `bilibiliStreamPriority`：空字符串 → 'audioOnly,muxed'
- `lyricsSourcePriority`：空字符串 → 'netease,qqmusic,lrclib'
- `enabledSources`：空列表 → ['bilibili', 'youtube']

## 添加新字段的步骤

**示例：添加新字段 `int newFeatureTimeout = 30;`**

### Step 1: 修改模型
```dart
// lib/data/models/settings.dart
@collection
class Settings {
  // ... 现有字段 ...
  
  /// 新功能超时时间（秒）
  int newFeatureTimeout = 30;  // 期望默认值
}
```

### Step 2: 添加迁移逻辑
```dart
// lib/providers/database_provider.dart
Future<void> _migrateDatabase(Isar isar) async {
  await isar.writeTxn(() async {
    var settings = await isar.settings.get(0);
    if (settings != null) {
      bool needsUpdate = false;
      
      // ... 现有迁移逻辑 ...
      
      // 修复新字段（旧版本升级后会是 0）
      if (settings.newFeatureTimeout < 1) {
        settings.newFeatureTimeout = 30;
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        await isar.settings.put(settings);
      }
    }
  });
}
```

### Step 3: 重新生成代码
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Step 4: 测试迁移
1. 安装旧版本 APK
2. 创建一些数据
3. 安装新版本 APK（覆盖安装）
4. 验证数据正常，新字段有正确的默认值

## 删除字段的步骤

**示例：删除字段 `autoRefreshImports` 和 `defaultRefreshIntervalHours`**

### Step 1: 从模型中删除
```dart
// lib/data/models/settings.dart
// 删除这两行：
// bool autoRefreshImports = true;
// int defaultRefreshIntervalHours = 24;
```

### Step 2: 清理相关代码
- 备份系统：从 `SettingsBackup` 中删除
- UI：删除相关显示/编辑界面
- 业务逻辑：删除使用这些字段的代码

### Step 3: 重新生成代码
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

**注意：** 删除字段不需要迁移逻辑，Isar 会自动忽略旧数据中的未知字段。

## 备份系统兼容性

如果字段也在备份系统中使用，需要同步修改：

**修改文件：**
- `lib/services/backup/backup_data.dart` - 添加/删除字段到 `SettingsBackup`
- `lib/services/backup/backup_service.dart` - 添加/删除备份/恢复逻辑

**注意：** 备份 JSON 的 `fromJson` 必须提供默认值：
```dart
newFeatureTimeout: json['newFeatureTimeout'] as int? ?? 30,
```

这样即使旧备份文件缺少该字段，也能正常恢复。

## 特殊情况处理

### 1. 修改字段类型

**不要直接修改字段类型：**
```dart
// ❌ 错误：从 int 改为 String
// int maxCacheSizeMB = 32;
String maxCacheSize = '32MB';  // 会导致数据丢失
```

**正确做法：**
1. 添加新字段 `maxCacheSize`
2. 在迁移逻辑中从旧字段转换：
   ```dart
   if (settings.maxCacheSize.isEmpty && settings.maxCacheSizeMB > 0) {
     settings.maxCacheSize = '${settings.maxCacheSizeMB}MB';
     needsUpdate = true;
   }
   ```
3. 几个版本后再删除旧字段

### 2. 重命名字段

Isar 会将重命名视为删除+添加，导致数据丢失。

**正确做法：**
1. 添加新字段
2. 在迁移逻辑中复制旧字段的值到新字段
3. 几个版本后删除旧字段

### 3. List 字段的默认值

```dart
// ✓ 正确：使用空列表
List<String> enabledSources = [];

// ✓ 更好：在迁移中检查并设置
if (settings.enabledSources.isEmpty) {
  settings.enabledSources = ['bilibili', 'youtube'];
  needsUpdate = true;
}
```

### 4. 可空字段 vs 非空字段

```dart
// 可空字段：旧版本升级后是 null
String? customDownloadDir;

// 非空字段：旧版本升级后是空字符串
String audioFormatPriority = 'aac,opus';

// 迁移时检查空字符串
if (settings.audioFormatPriority.isEmpty) {
  settings.audioFormatPriority = 'aac,opus';
}
```

## 测试清单

**每次修改数据库模型后：**
- [ ] 在 `_migrateDatabase()` 中添加迁移逻辑（如果需要）
- [ ] 更新备份系统（如果适用）
- [ ] 重新生成 Isar 代码
- [ ] 测试全新安装（数据库不存在）
- [ ] 测试旧版本→新版本的升级路径
- [ ] 测试备份恢复功能
- [ ] 更新本文档

## 常见问题

**Q: 为什么我的新字段值是 0 而不是我设置的默认值？**

A: Isar 在升级时使用类型默认值（int=0），不会使用你在模型中写的 `= 30`。必须在 `_migrateDatabase()` 中手动修复。

**Q: 我可以直接修改字段类型吗？**

A: 不建议。应该添加新字段，在迁移中转换数据，然后删除旧字段。

**Q: 删除字段需要迁移逻辑吗？**

A: 不需要。Isar 会自动忽略旧数据中的未知字段。

**Q: 如何测试迁移逻辑？**

A: 
1. 构建旧版本 APK 并安装
2. 创建测试数据
3. 构建新版本 APK 并覆盖安装
4. 检查数据是否正确迁移

## 版本历史

| 日期 | 变更内容 |
|------|---------|
| 2026-02 | 删除 `autoRefreshImports` 和 `defaultRefreshIntervalHours` |
| 2026-02 | 添加迁移函数 `_migrateDatabase()` |
