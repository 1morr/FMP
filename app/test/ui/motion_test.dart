import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/motion.dart';
import 'package:fmp/ui/now_playing/now_playing.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

import '../support/motion.dart';

import 'package:fmp/ui/common/cover.dart';

/// 共用的動態元件（`docs/design/DESIGN.md`〈狀態變化對照〉）：按下縮放、
/// 載入中的轉圈，與減少動態效果時仍照原本時長動的淡入淡出。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    ProviderScope(
      child: TranslationProvider(
        child: MaterialApp(
          theme: buildTheme(
            brightness: Brightness.light,
            density: Density.touch,
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );

  double scaleOf(WidgetTester tester, Finder button) => tester
      .widget<ScaleTransition>(
        find.descendant(
          of: button,
          matching: find.byKey(const Key('press-scale')),
        ),
      )
      .scale
      .value;

  /// 讀「減少動態效果」的共用入口（`DESIGN.md`〈狀態變化對照〉：只經它讀）：
  /// 跟著系統設定，選取的動法在減少動態效果時是 out 280、不彈跳。
  testWidgets('the reduce motion entry follows the system setting', (
    tester,
  ) async {
    late BuildContext context;
    Widget probe() => Builder(
      builder: (c) {
        context = c;
        return const SizedBox();
      },
    );
    await pump(tester, probe());
    expect(FmpMotion.reduced(context), isFalse);
    expect(FmpMotion.selection(context).curve, FmpMotion.springCurve);

    reduceMotion(tester);
    await tester.pump();
    expect(FmpMotion.reduced(context), isTrue);
    final selection = FmpMotion.selection(context);
    expect(selection.duration, FmpMotion.mid);
    expect(selection.curve, FmpMotion.outCurve);
  });

  group('press', () {
    Future<void> pressHalfway(WidgetTester tester, Finder target) async {
      final gesture = await tester.startGesture(tester.getCenter(target));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }

    for (final (name, button) in [
      (
        'plain icon button',
        PlainIconButton(
          icon: FmpIcons.more,
          tooltip: 'more',
          onTap: () {},
          size: 44,
        ),
      ),
      (
        'glass icon button',
        GlassIconButton(
          icon: FmpIcons.more,
          tooltip: 'more',
          onTap: () {},
          touch: true,
        ),
      ),
      (
        'play button',
        const PlayPauseButton(playing: false, size: 44, iconSize: 22),
      ),
    ]) {
      testWidgets('$name: shrinks toward 0.92 while held, also with reduced '
          'motion, and springs back on release', (tester) async {
        reduceMotion(tester);
        await pump(tester, button);
        final target = find.byWidget(button);
        await pressHalfway(tester, target);
        expect(scaleOf(tester, target), inExclusiveRange(.92, 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(scaleOf(tester, target), moreOrLessEquals(.92));
      });
    }

    testWidgets('text button: shrinks to 0.96 while held', (tester) async {
      await pump(tester, FmpButton(label: 'OK', onTap: () {}));
      final target = find.byType(FmpButton);
      await pressHalfway(tester, target);
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf(tester, target), moreOrLessEquals(.96));
    });
  });

  group('spinner', () {
    double turns(WidgetTester tester) => tester
        .widget<RotationTransition>(find.byKey(const Key('spinner-turns')))
        .turns
        .value;

    testWidgets('turns once every 900ms at a steady speed', (tester) async {
      await pump(tester, const Spinner());
      await tester.pump(const Duration(milliseconds: 225));
      expect(turns(tester), moreOrLessEquals(.25, epsilon: .01));
      await tester.pump(const Duration(milliseconds: 225));
      expect(turns(tester), moreOrLessEquals(.5, epsilon: .01));
    });

    testWidgets('with reduced motion, once every 3 seconds', (tester) async {
      reduceMotion(tester);
      await pump(tester, const Spinner());
      await tester.pump(const Duration(milliseconds: 750));
      expect(turns(tester), moreOrLessEquals(.25, epsilon: .01));
    });
  });

  testWidgets('a cover fades in over out 160 once its image has loaded, '
      'also with reduced motion', (tester) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coverImageLoaderProvider.overrideWithValue((_) => MemoryImage(_png)),
        ],
        child: MaterialApp(
          theme: buildTheme(
            brightness: Brightness.light,
            density: Density.touch,
          ),
          home: const Center(
            child: Cover(url: 'https://example.com/c', size: 40, radius: 9),
          ),
        ),
      ),
    );
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byKey(Cover.imageFadeKey),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    expect(opacity(), 0);
    // 解碼在真的非同步裡完成。
    await tester.runAsync(
      () =>
          precacheImage(MemoryImage(_png), tester.element(find.byType(Cover))),
    );
    for (var i = 0; i < 5 && opacity() == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(), 1);
  });

  /// 換歌時的封面（`Cover.crossFade`）：新封面解碼出第一個 frame 才交叉淡出，
  /// 之前舊封面完整留著；新封面載入失敗才淡到預設底。
  group('cover change', () {
    late Map<String, _PendingImage> images;

    Future<void> showCover(WidgetTester tester, String url) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              coverImageLoaderProvider.overrideWithValue((url) => images[url]!),
            ],
            child: MaterialApp(
              theme: buildTheme(
                brightness: Brightness.light,
                density: Density.touch,
              ),
              home: Center(
                child: Cover(url: url, size: 40, radius: 9, crossFade: true),
              ),
            ),
          ),
        );

    /// 畫著 [image] 的那張圖外面所有淡入淡出相乘的透明度；不在畫面上是 null。
    double? opacityOf(WidgetTester tester, _PendingImage image) {
      final found = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is ResizeImage &&
            (w.image as ResizeImage).imageProvider == image,
      );
      if (found.evaluate().isEmpty) return null;
      return tester
          .widgetList<FadeTransition>(
            find.ancestor(of: found, matching: find.byType(FadeTransition)),
          )
          .fold<double>(1, (v, f) => v * f.opacity.value);
    }

    Future<void> showLoadedA(WidgetTester tester) async {
      // 在測試本體裡建：Completer 的 future 跟著建它的 zone 排工作，setUp 裡
      // 建的錯誤傳遞走真的 microtask，fake async 的 pump 跑不到。
      images = {'a': _PendingImage(), 'b': _PendingImage()};
      await tester.runAsync(() => images['a']!.load());
      await showCover(tester, 'a');
      await tester.pumpAndSettle();
      expect(opacityOf(tester, images['a']!), 1);
    }

    testWidgets('the old cover stays whole until the new one has a frame, '
        'then they cross-fade', (tester) async {
      await showLoadedA(tester);
      await showCover(tester, 'b');
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, images['a']!), 1);

      await tester.runAsync(() => images['b']!.load());
      // 第一個 frame 到了、換過去，下一幀才開始淡。
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(opacityOf(tester, images['a']!), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, images['a']!), isNull);
      expect(opacityOf(tester, images['b']!), 1);
    });

    testWidgets('when the new cover fails, the old one fades to the plain '
        'fill', (tester) async {
      await showLoadedA(tester);
      await showCover(tester, 'b');
      await tester.pump();
      expect(opacityOf(tester, images['a']!), 1);

      images['b']!.fail();
      // 失敗回報、換成底色，下一幀才開始淡。
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(opacityOf(tester, images['a']!), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, images['a']!), isNull);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('reduced motion keeps fades', () {
    testWidgets('a fade still takes its full duration', (tester) async {
      reduceMotion(tester);
      Widget fade(double opacity) => PreservedFade(
        opacity: opacity,
        child: const SizedBox.square(dimension: 10),
      );
      await pump(tester, fade(0));
      await pump(tester, fade(1));
      await tester.pump(const Duration(milliseconds: 100));
      final opacity = tester
          .widget<FadeTransition>(find.byType(FadeTransition).last)
          .opacity
          .value;
      expect(opacity, inExclusiveRange(0, 1));
    });

    testWidgets('a switch cross-fades over its full duration', (tester) async {
      reduceMotion(tester);
      await pump(
        tester,
        const PreservedSwitcher(child: Text('a', key: Key('a'))),
      );
      await pump(
        tester,
        const PreservedSwitcher(child: Text('b', key: Key('b'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('a'), findsNothing);
    });
  });
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// 由測試決定什麼時候載好（[load]）或失敗（[fail]）的圖。
class _PendingImage extends ImageProvider<_PendingImage> {
  final _info = Completer<ImageInfo>();

  Future<void> load() async {
    if (_info.isCompleted) return;
    _info.complete(ImageInfo(image: await decodeImageFromList(_png)));
  }

  void fail() => _info.completeError(StateError('cover failed'));

  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_info.future);
}
