# FMP 项目 - 常用命令

## Flutter 命令

### 开发运行
```bash
# 在 Windows 上运行
flutter run -d windows

# 在 Android 设备/模拟器上运行
flutter run -d android

# 列出可用设备
flutter devices
```

### 构建
```bash
# 分析代码
flutter analyze

# 清理构建缓存
flutter clean

# 获取依赖
flutter pub get

# 构建 Windows 应用
flutter build windows

# 构建 Android APK
flutter build apk
```

### 代码生成 (Isar, Riverpod)
```bash
# 生成 .g.dart 文件 (一次性)
flutter pub run build_runner build

# 持续监听并生成
flutter pub run build_runner watch

# 清理并重新生成
flutter pub run build_runner build --delete-conflicting-outputs
```

### 测试
```bash
# 运行所有测试
flutter test

# 运行特定测试文件
flutter test test/path/to/test.dart
```

## Git 命令

```bash
# 查看状态
git status

# 添加所有更改
git add .

# 提交
git commit -m "feat: 描述"

# 查看历史
git log --oneline -10
```

## Windows 系统命令

```bash
# 列出目录内容
dir /b "path\to\directory"

# 递归列出
dir /s /b "path"

# 查找文件
dir /s /b "*.dart"

# 切换目录
cd "path\to\directory"
```

## 项目特定命令

### 常见开发流程
```bash
# 1. 获取依赖
flutter pub get

# 2. 生成代码
flutter pub run build_runner build

# 3. 运行应用
flutter run -d windows
```

### 解决常见问题
```bash
# 清理并重新构建
flutter clean && flutter pub get && flutter pub run build_runner build

# 修复依赖问题
flutter pub cache repair
```
