# FMP 代码风格与约定

此记忆只保留编码风格细节。项目架构、文件结构、数据模型、命令等权威信息请看根目录 `CLAUDE.md`。

## 命名约定

- 文件使用 snake_case：`audio_service.dart`, `track_repository.dart`
- Widget 文件与类名对应：`home_page.dart` → `HomePage`
- 类名使用 PascalCase：`AudioService`, `TrackRepository`
- 变量、常量使用 lowerCamelCase：`currentTrack`, `maxCacheSizeMB`
- 私有成员使用 `_` 前缀

## Import 顺序

1. Dart SDK
2. Flutter SDK
3. 第三方包
4. 项目内部相对路径

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
```

## 架构边界

- UI 层只调用 `AudioController`，不要直接调用 `AudioService`
- Riverpod provider 负责状态和依赖注入，业务逻辑放 service/controller
- Isar model 修改后必须检查 `CLAUDE.md` 的 Database Migration 规则
- 不要在 build 期间修改 provider/state；需要延后时用事件回调或 `Future.microtask()`

## UI 规范

- 使用 Material 3 / `ColorScheme`
- 响应式断点以 `CLAUDE.md` 为准
- UI 魔法数字优先使用 `lib/core/constants/ui_constants.dart`
- 图片加载必须走 `TrackThumbnail` / `TrackCover` / `ImageLoadingService`

## 代码生成

修改 Isar model、Riverpod 生成文件或 i18n json 后，运行对应生成命令；常用命令见 `CLAUDE.md`。