# FMP 项目 - 任务完成检查清单

## 每次代码修改后

### 1. 代码生成 (如果修改了 Isar 模型或 Riverpod)
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 2. 静态分析
```bash
flutter analyze
```
确保没有 error 和 warning

### 3. 运行测试 (如果有)
```bash
flutter test
```

## 功能完成后

### 1. 运行应用测试
```bash
# Windows
flutter run -d windows

# Android
flutter run -d android
```

### 2. 功能验证检查
- [ ] 新功能正常工作
- [ ] 没有破坏现有功能
- [ ] UI 显示正确
- [ ] 错误处理得当

### 3. 代码质量检查
- [ ] 遵循项目代码风格
- [ ] 添加必要的注释
- [ ] 没有硬编码的值 (使用常量)
- [ ] 没有未使用的代码

## Phase 完成后

### 测试验收标准
| 阶段 | 测试命令 | 验收标准 |
|------|----------|----------|
| Phase 1 | `flutter run -d windows` | 应用启动，显示空白 Shell |
| Phase 2 | `flutter run -d windows` | 可播放 B站音频 |
| Phase 3 | `flutter run -d android` | 歌单管理正常 |
| Phase 4 | 两平台都测试 | UI 响应式正常 |
| Phase 5 | 分别测试 Android/Windows | 平台特性正常 |
| Phase 6 | 全面测试 | 性能达标，无明显 bug |

## 提交代码前

### 1. 确保干净构建
```bash
flutter clean
flutter pub get
flutter pub run build_runner build
flutter analyze
```

### 2. 确保应用可运行
```bash
flutter run -d windows
```

### 3. Git 提交
```bash
git add .
git commit -m "feat/fix/refactor: 描述"
```

## 常见问题解决

### 依赖冲突
```bash
flutter pub cache repair
flutter clean
flutter pub get
```

### 代码生成问题
```bash
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

### Windows 音频不工作
确保 `pubspec.yaml` 包含 `just_audio_windows: ^0.2.2`
