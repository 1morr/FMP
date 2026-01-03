# FMP 项目 - 代码风格与约定

## 项目结构

```
lib/
├── main.dart                # 应用入口
├── app.dart                 # App 配置和主 Widget
├── core/                    # 核心模块
│   ├── constants/           # 常量定义
│   ├── extensions/          # Dart 扩展
│   ├── utils/               # 工具函数
│   └── errors/              # 错误处理
├── data/                    # 数据层
│   ├── models/              # Isar 数据模型
│   ├── repositories/        # 数据仓库
│   └── sources/             # 音源解析
├── services/                # 服务层
│   ├── audio/               # 音频服务
│   ├── download/            # 下载服务
│   ├── search/              # 搜索服务
│   ├── import/              # 导入服务
│   ├── library/             # 音乐库服务
│   └── platform/            # 平台服务
├── providers/               # Riverpod Providers
└── ui/                      # UI 层
    ├── pages/               # 页面 (按功能分组)
    ├── widgets/             # 共享组件
    ├── layouts/             # 响应式布局
    └── theme/               # 主题配置
```

## 命名约定

### 文件命名
- 使用 snake_case: `audio_service.dart`, `track_repository.dart`
- Widget 文件与类名对应: `home_page.dart` -> `HomePage`

### 类命名
- 使用 PascalCase: `AudioService`, `TrackRepository`
- Widget: `HomePage`, `MiniPlayer`
- Provider: `audioProvider`, `playlistProvider`

### 变量命名
- 使用 camelCase: `currentTrack`, `isPlaying`
- 私有变量前缀 `_`: `_player`, `_tracks`
- 常量使用 lowerCamelCase: `maxCacheSizeMB`

## 代码风格

### Linting
项目使用 `flutter_lints` 包的默认规则 (analysis_options.yaml)

### 文档注释
- 使用 `///` 进行文档注释
- 示例:
```dart
/// 音源类型枚举
enum SourceType {
  bilibili,
  youtube,
}

/// 歌曲/音频实体
@collection
class Track {
  /// 源平台的唯一ID (如 BV号, YouTube video ID)
  late String sourceId;
}
```

### 导入顺序
1. Dart SDK
2. Flutter SDK
3. 第三方包
4. 项目内部包 (相对路径)

示例:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../data/models/track.dart';
import '../providers/database_provider.dart';
```

## 架构模式

### 分层架构
1. **UI 层**: Widgets, Pages, Layouts
2. **Provider 层**: Riverpod 状态管理
3. **Service 层**: 业务逻辑
4. **Data 层**: 数据模型、仓库、数据源

### Riverpod 使用
- 使用 `FutureProvider` 处理异步初始化
- 使用 `StateNotifierProvider` 管理复杂状态
- 使用 `Provider` 提供依赖注入

### Isar 数据模型
- 使用 `@collection` 注解
- 添加适当的 `@Index` 索引
- 模型文件需要 `part 'xxx.g.dart'` 声明

## UI 规范

### Material Design 3
- 使用 Material 3 组件和设计语言
- 支持 Dynamic Color
- 响应式布局断点:
  - Mobile: < 600dp
  - Tablet: 600-1200dp
  - Desktop: > 1200dp

### 主题
- 支持浅色/深色主题
- 自定义配色方案
- 使用 `ThemeData` 和 `ColorScheme`
