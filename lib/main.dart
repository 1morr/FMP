import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: 初始化 Isar 数据库
  // TODO: 初始化音频服务
  // TODO: 初始化平台特定服务（托盘、快捷键等）

  runApp(
    const ProviderScope(
      child: FMPApp(),
    ),
  );
}
