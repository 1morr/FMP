import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/audio_backend_lifecycle.dart';
import 'package:fmp/playback/playback.dart';

import '../support/fake_audio_backend.dart';

/// App 要結束時（例如 Windows 關視窗）先釋放音訊後端：media_kit 的 libmpv
/// 執行緒在 Dart VM 關掉後還呼叫 FFI callback，整個行程會崩潰（brief 事實
/// W11）。
void main() {
  /// 照引擎的做法送 `System.requestAppExit`，回傳框架的回答。
  Future<String?> requestAppExit(WidgetTester tester) async {
    const codec = JSONMethodCodec();
    ByteData? reply;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.platform.name,
      codec.encodeMethodCall(
        const MethodCall('System.requestAppExit', {'type': 'cancelable'}),
      ),
      (data) => reply = data,
    );
    final result = codec.decodeEnvelope(reply!) as Map<String, Object?>;
    return result['response'] as String?;
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    FakeAudioBackend backend,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioBackendOverride(() => backend)],
        child: const SizedBox(),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(SizedBox)));
  }

  testWidgets('the backend is disposed before the app exits', (tester) async {
    final backend = FakeAudioBackend();
    final container = await pump(tester, backend);
    container.read(audioBackendProvider);

    expect(await requestAppExit(tester), 'exit');
    expect(backend.disposed, isTrue);
  });

  testWidgets('without a backend nothing is created on exit', (tester) async {
    var created = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBackendOverride(() {
            created++;
            return FakeAudioBackend();
          }),
        ],
        child: const SizedBox(),
      ),
    );

    expect(await requestAppExit(tester), 'exit');
    expect(created, 0);
  });

  testWidgets('the provider disposes the backend once, also after an exit '
      'request', (tester) async {
    final backend = FakeAudioBackend();
    final container = await pump(tester, backend);
    container.read(audioBackendProvider);

    await requestAppExit(tester);
    await tester.pumpWidget(const SizedBox());

    expect(backend.calls.where((c) => c == 'dispose'), hasLength(1));
  });
}
