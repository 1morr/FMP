# FMP 缓存系统架构

## 概述

FMP 使用自定义的缓存管理器来控制图片缓存，支持：
- 限制最大缓存数量
- 设置过期时间
- 手动清除缓存
- 持久化缓存上限设置

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                      Settings Page                           │
│   _CacheSizeListTile, _CacheLimitListTile, _ClearCacheListTile │
│                            │                                 │
│                            ▼                                 │
│              refreshableCacheStatsProvider                   │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      CacheService                            │
│              (lib/services/cache/cache_service.dart)         │
│                                                              │
│  职责：                                                       │
│  - 获取缓存大小和统计信息                                      │
│  - 清除缓存                                                   │
│  - 更新缓存上限设置                                            │
│  - 管理缓存目录                                               │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    FmpCacheManager                           │
│            (lib/services/cache/fmp_cache_manager.dart)       │
│                                                              │
│  职责：                                                       │
│  - 自定义 flutter_cache_manager 配置                          │
│  - 限制缓存数量 (默认 500 张)                                  │
│  - 设置过期时间 (默认 7 天)                                    │
│                                                              │
│  使用方式：                                                    │
│  CachedNetworkImage(                                         │
│    cacheManager: FmpCacheManager.instance,                   │
│    imageUrl: url,                                            │
│  )                                                           │
└─────────────────────────────────────────────────────────────┘
```

## 文件位置

| 文件 | 职责 |
|------|------|
| `lib/services/cache/fmp_cache_manager.dart` | 自定义缓存管理器 |
| `lib/services/cache/cache_service.dart` | 缓存服务层 |
| `lib/providers/cache_provider.dart` | Riverpod Providers |
| `lib/ui/pages/settings/settings_page.dart` | 设置页面 UI |

## Provider 结构

```dart
// 基础 Providers
final settingsRepositoryProvider = Provider<SettingsRepository>
final cacheServiceProvider = Provider<CacheService>

// 缓存统计
final cacheStatsProvider = FutureProvider<CacheStats>
final cacheStatsRefreshProvider = StateProvider<int>  // 刷新触发器
final refreshableCacheStatsProvider = FutureProvider<CacheStats>
```

## CacheStats 数据结构

```dart
class CacheStats {
  final int imageCacheBytes;      // 图片缓存大小（字节）
  final int imageCacheCount;      // 图片缓存数量
  final int maxCacheMB;           // 缓存上限（MB）
  
  String get formattedImageCacheSize;  // 格式化的大小字符串
  String get formattedMaxCache;        // 格式化的上限字符串
  double get usagePercent;             // 使用百分比
}
```

## 缓存位置

| 平台 | 路径 |
|------|------|
| Windows | `C:\Users\<用户名>\AppData\Local\Temp\fmpImageCache\` |
| Android | `/data/data/<包名>/cache/fmpImageCache/` |

## 使用注意

1. **所有 CachedNetworkImage 必须使用 FmpCacheManager**
   ```dart
   CachedNetworkImage(
     cacheManager: FmpCacheManager.instance,  // 必须添加
     imageUrl: url,
   )
   ```

2. **刷新缓存统计**
   ```dart
   ref.invalidate(refreshableCacheStatsProvider);
   ```

3. **清除缓存**
   ```dart
   final cacheService = ref.read(cacheServiceProvider);
   await cacheService.clearAllCache();
   ```

## 与旧系统的区别

| 方面 | 旧系统 | 新系统 |
|------|--------|--------|
| 缓存位置 | `libCachedImageData` | `fmpImageCache` |
| 数量限制 | 无 | 默认 500 张 |
| 过期时间 | 系统默认 | 7 天 |
| 清除功能 | 假实现 | 真正清除 |
| 大小显示 | 硬编码 | 真实计算 |
