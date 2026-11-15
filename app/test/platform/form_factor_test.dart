import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

/// 寬度分級與密度：`docs/design/DESIGN.md`〈中寬度〉的分級表。
void main() {
  group('width class', () {
    test('is narrow below 600', () {
      expect(WidthClass.of(320), WidthClass.narrow);
      expect(WidthClass.of(599.9), WidthClass.narrow);
    });

    test('is medium from 600 to below 1200', () {
      expect(WidthClass.of(600), WidthClass.medium);
      expect(WidthClass.of(1199.9), WidthClass.medium);
    });

    test('is wide from 1200', () {
      expect(WidthClass.of(1200), WidthClass.wide);
      expect(WidthClass.of(2560), WidthClass.wide);
    });
  });

  group('density', () {
    test('is touch on phones and tablets', () {
      expect(Density.of(TargetPlatform.iOS), Density.touch);
      expect(Density.of(TargetPlatform.android), Density.touch);
    });

    test('is pointer on desktops', () {
      expect(Density.of(TargetPlatform.macOS), Density.pointer);
      expect(Density.of(TargetPlatform.windows), Density.pointer);
      expect(Density.of(TargetPlatform.linux), Density.pointer);
    });
  });

  group('a screen reads', () {
    Future<FormFactor> formFactorAt(WidgetTester tester, Size size) async {
      late FormFactor formFactor;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              formFactor = FormFactor.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return formFactor;
    }

    testWidgets('the width class of the window', (tester) async {
      expect(
        (await formFactorAt(tester, const Size(390, 844))).widthClass,
        WidthClass.narrow,
      );
      expect(
        (await formFactorAt(tester, const Size(820, 1180))).widthClass,
        WidthClass.medium,
      );
      expect(
        (await formFactorAt(tester, const Size(1280, 800))).widthClass,
        WidthClass.wide,
      );
    });

    testWidgets('touch density on a phone even when the window is wide', (
      tester,
    ) async {
      final formFactor = await formFactorAt(tester, const Size(1366, 1024));
      expect(formFactor.widthClass, WidthClass.wide);
      expect(formFactor.density, Density.touch);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

    testWidgets('pointer density on a desktop even when the window is medium', (
      tester,
    ) async {
      final formFactor = await formFactorAt(tester, const Size(720, 560));
      expect(formFactor.widthClass, WidthClass.medium);
      expect(formFactor.density, Density.pointer);
    }, variant: const TargetPlatformVariant({TargetPlatform.windows}));
  });
}
