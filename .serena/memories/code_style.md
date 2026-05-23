# FMP 代码风格与约定

此记忆只保留编码风格细节。项目架构、文件结构、数据模型、命令等权威信息请看根目录 `AGENTS.md`。

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

## 架构与 UI 规则

架构边界、provider/database/audio/UI 规范以根目录 `AGENTS.md` 和对应子目录
`AGENTS.md` 为准；本记忆不重复维护这些规则。若这里的风格提示与 scoped
instruction 冲突，按 scoped instruction 处理。

## 代码生成

修改 Isar model、Riverpod 生成文件或 i18n json 后，运行对应生成命令；常用命令见 `AGENTS.md`。
