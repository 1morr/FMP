import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/windows/lyrics_window.dart';

/// 桌面歌詞子視窗整棵樹的無障礙語意。
///
/// 子視窗曾整棵包在 `ExcludeSemantics` 裡，讀屏連標題列的關閉鈕都找不到。
/// 這裡 pump 整個子視窗 app，確認標題列控制項仍在語意樹上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 子視窗一啟動就會設定視窗大小、置頂，並向主視窗註冊跨引擎通道；
  // 測試裡兩個原生端都不存在。置中視窗要先問視窗大小再問螢幕配置，那一步
  // 讓它停在原地 —— 這裡要看的是畫面，不是視窗擺在哪。
  const platformChannels = [
    MethodChannel('window_manager'),
    MethodChannel('mixin.one/desktop_multi_window/channels'),
  ];

  setUp(() {
    for (final channel in platformChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) => call.method == 'getBounds'
                ? Completer<Object?>().future
                : Future.value(),
          );
    }
  });

  tearDown(() {
    for (final channel in platformChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('the title bar controls stay in the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const LyricsWindowApp());
    await tester.pump();

    // 主視窗推來字串之前，子視窗用的是自己的預設文案。
    for (final label in ['上一首', '播放', '下一首', '关闭']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    semantics.dispose();
  });
}
