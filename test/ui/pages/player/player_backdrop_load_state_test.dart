import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/player/blurred_cover_backdrop.dart';

/// 1×1 透明 PNG。
final _pngBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _backdrop({
  required String? sourceKey,
  required List<ImageProvider> candidates,
}) {
  return MaterialApp(
    home: Stack(
      children: [
        BlurredCoverBackdrop(
          sourceKey: sourceKey,
          imageCandidates: candidates,
          colorScheme: const ColorScheme.light(),
          surfaceOverlayAlpha: 0.5,
          surfaceContainerOverlayAlpha: 0.5,
        ),
      ],
    ),
  );
}

void main() {
  group('BlurredCoverBackdropLoadState', () {
    test('keeps failed requests marked until the source key changes', () {
      final state = BlurredCoverBackdropLoadState();

      state.updateDesiredKey('network:bad-cover');
      expect(
        state.shouldRequest('network:bad-cover', hasCandidates: true),
        isTrue,
      );

      final generation = state.markRequested('network:bad-cover');
      expect(
        state.shouldRequest('network:bad-cover', hasCandidates: true),
        isFalse,
      );

      state.markFailed('network:bad-cover', generation);
      expect(state.requestedKey, 'network:bad-cover');
      expect(
        state.shouldRequest('network:bad-cover', hasCandidates: true),
        isFalse,
      );

      state.updateDesiredKey('network:next-cover');
      expect(state.requestedKey, isNull);
      expect(
        state.shouldRequest('network:next-cover', hasCandidates: true),
        isTrue,
      );
    });
  });

  group('BlurredCoverBackdrop', () {
    /// 換到沒有封面的歌時，上一首的背景不能留著。
    final noCover = <String, (String?, List<ImageProvider>)>{
      'without a source key': (null, const []),
      'without image candidates': ('network:no-candidates', const []),
    };

    for (final MapEntry(key: label, value: (sourceKey, candidates))
        in noCover.entries) {
      testWidgets('clears the previous cover $label', (tester) async {
        final cover = MemoryImage(_pngBytes);
        // 先在真事件迴圈裡把封面解碼進 ImageCache：在 fake async 區裡開始的
        // 解碼只有 `tester.pump` 推得動，在 runAsync 裡等它不可靠。背景之後的
        // precache 就是同步的快取命中。
        await tester.pumpWidget(_backdrop(sourceKey: null, candidates: []));
        await tester.runAsync(
          () => precacheImage(
            cover,
            tester.element(find.byType(BlurredCoverBackdrop)),
          ),
        );

        await tester.pumpWidget(
          _backdrop(sourceKey: 'network:cover', candidates: [cover]),
        );
        await tester.pump(); // post-frame precache 的 await 接續與 setState
        await tester.pump(); // setState 後的重建
        expect(find.byType(Image), findsOneWidget);

        await tester.pumpWidget(
          _backdrop(sourceKey: sourceKey, candidates: candidates),
        );
        await tester.pump(); // post-frame 清除後的重建

        expect(find.byType(Image), findsNothing);
      });
    }
  });
}
