import 'package:flutter/material.dart';

/// 回報問題的位置。寫死而不是從 `update_service.dart` 的 `_repoOwner` 拼出來：
/// 這個畫面存在的前提就是「初始化在某一步炸了」，多引一個檔案就多一個
/// 可能還沒初始化好的相依。
const String kFmpIssuesUrl = 'https://github.com/1morr/FMP/issues';

/// `runApp()` 之前就拋出例外時，頂替上去的最小畫面。
///
/// Flutter 的 Windows 桌面模板把視窗的 `Show` 綁在第一帧回呼上，所以沒有
/// `runApp()` 就沒有第一帧、也就沒有視窗 —— 使用者雙擊之後什麼都不會發生
/// （issue #37）。這個畫面的唯一職責是把那種靜默失敗換成看得見的失敗。
///
/// 它刻意不碰 Riverpod、不碰 slang 的 `t` / `context.t`，也不讀 `AppTheme`：
/// **失敗的很可能正是那些東西**。`LocaleSettings.useDeviceLocaleSync()` 就排在
/// 啟動序列的前段，它自己拋出來的時候 `t.*` 讀到的是什麼沒有人知道。所以文案
/// 是寫死的英文 + 繁體中文兩行，兩種語言的使用者至少都讀得懂一行。
///
/// 這裡顯示原始的 `error.toString()`，是「原始例外不得上畫面」這條規則的刻意
/// 例外：這個時點連 log 頁面都還不存在，畫面上這幾行是使用者唯一
/// 能拿到的線索。原文同時已經由 `main.dart` 的 zone handler 記進 `AppLogger`。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error, this.logFilePath});

  /// 讓啟動中止的那個例外。
  final Object error;

  /// log 檔的完整路徑，落盤還沒掛上時是 null。
  final String? logFilePath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FMP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'FMP failed to start',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'FMP 啟動失敗',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Error / 錯誤'),
                    SelectableText(error.toString()),
                    if (logFilePath != null) ...[
                      const SizedBox(height: 20),
                      const _SectionLabel('Log file / 記錄檔'),
                      SelectableText(logFilePath!),
                    ],
                    const SizedBox(height: 20),
                    const _SectionLabel('Report this / 回報問題'),
                    const SelectableText(kFmpIssuesUrl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
