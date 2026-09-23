import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/network/connectivity_service.dart';

/// app 外層掛在 Navigator 之上的控制項，要讀屏看得到。
///
/// 這些控制項（網路狀態 Banner 與它的重試按鈕、Windows 標題列）畫在路由之前，
/// 路由的 ModalBarrier 帶 `BlockSemantics`，同一個語意容器裡先畫的節點會被整段
/// 丟掉。畫面上完全正常，只有讀屏聽不到 —— 所以這裡在真的 Navigator 底下量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 測試主機是 Windows 時外層會多掛標題列，它在 `initState` 會問視窗是否
    // 最大化；測試裡沒有 window_manager 的原生端。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          return call.method == 'isMaximized' ? false : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Widget app() {
    LocaleSettings.setLocale(AppLocale.en);
    return TranslationProvider(
      child: ProviderScope(
        overrides: [
          audioControllerProvider.overrideWith(_NetworkErrorController.new),
          connectivityProvider.overrideWith(_OnlineConnectivity.new),
        ],
        child: MaterialApp(
          builder: (context, child) => AppContentWrapper(child: child),
          home: const Scaffold(body: Text('page')),
        ),
      ),
    );
  }

  testWidgets('controls above the Navigator stay in the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await tester.pump();
    // Banner 的滑入動畫跑完；不用 pumpAndSettle，歌詞等其他 provider 可能一直有排程。
    await tester.pump(const Duration(seconds: 1));

    // 路由本身照常讀得到。
    expect(find.bySemanticsLabel('page'), findsOneWidget);

    // 狀態文字沒有自己的節點，會併進外層節點的標籤裡。
    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(t.networkStatus.playbackNetworkError)),
      ),
      findsOneWidget,
    );
    final retry = find.bySemanticsLabel(t.networkStatus.retry);
    expect(retry, findsOneWidget);
    expect(tester.getSemantics(retry).flagsCollection.isButton, isTrue);

    // 標題列只在 Windows 上掛；CI 的 Linux 主機量不到這一段。
    if (Platform.isWindows) {
      for (final label in [
        t.general.minimize,
        t.general.maximize,
        t.general.close,
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
    }
    semantics.dispose();
  });
}

/// 播放時遇到網路錯誤、還沒在重試：Banner 顯示文字與重試按鈕。
class _NetworkErrorController extends AudioController {
  @override
  PlayerState build() => const PlayerState(isNetworkError: true);
}

/// 不做 DNS 輪詢的連線狀態。
class _OnlineConnectivity extends ConnectivityNotifier {
  @override
  ConnectivityState build() =>
      const ConnectivityState(isConnected: true, isInitialized: true);
}
