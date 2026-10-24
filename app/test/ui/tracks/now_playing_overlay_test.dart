import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
import 'package:material_ui/material_ui.dart';

// 正在播放的封面遮罩（ADR 0035 §決定 1、P-05）：主色遮罩加動態指示器，暫停或減少動態時不動。

Future<void> _pump(
  WidgetTester tester, {
  required PlaybackState state,
  bool disableAnimations = false,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [playbackStateProvider.overrideWithValue(AsyncData(state))],
    child: MaterialApp(
      theme: buildAppTheme(
        Brightness.light,
        fontFamilyFallback: const [],
        textLocale: const Locale('en'),
      ),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const Scaffold(body: NowPlayingOverlay(size: 48)),
      ),
    ),
  ),
);

void main() {
  testWidgets('covers the cover with the primary color at 80%', (tester) async {
    await _pump(tester, state: const Paused());

    final scheme = Theme.of(tester.element(find.byType(NowPlayingOverlay)))
        .colorScheme;
    final box = tester.widget<ColoredBox>(
      find.byKey(NowPlayingOverlay.overlayKey),
    );
    expect(box.color, scheme.primary.withValues(alpha: 0.8));
    expect(
      tester.getSize(find.byKey(NowPlayingOverlay.overlayKey)),
      const Size(48, 48),
    );
  });

  testWidgets('animates while playing', (tester) async {
    await _pump(tester, state: const Playing());

    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('is still when paused', (tester) async {
    await _pump(tester, state: const Paused());

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('stops when paused and moves again when playing', (tester) async {
    await _pump(tester, state: const Playing());
    expect(tester.hasRunningAnimations, isTrue);

    await _pump(tester, state: const Paused());
    expect(tester.hasRunningAnimations, isFalse);

    await _pump(tester, state: const Playing());
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('is still when the system asks for less motion', (tester) async {
    await _pump(tester, state: const Playing(), disableAnimations: true);

    expect(tester.hasRunningAnimations, isFalse);
  });
}
