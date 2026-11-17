import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/traffic_lights.dart';

/// 燈位經 `fmp/window` 的 `setTrafficLights` 告訴 macOS 原生端；沒有側欄或細欄的
/// 畫面要明確說「沒有燈位」，原生端才會把紅綠燈放回系統原位、不會一直藏著。
void main() {
  const channel = MethodChannel('fmp/window');
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  late List<Object?> sent;

  setUp(() {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setTrafficLights') sent.add(call.arguments);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget area({Key? key}) => TrafficLightsArea(
    key: key,
    spot: const Offset(7, 14),
    child: const SizedBox(width: 60, height: 52),
  );

  Widget app(Widget home) => TrafficLights(
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: home),
    ),
  );

  testWidgets('a screen without a sidebar or rail sends no spot', (
    tester,
  ) async {
    await tester.pumpWidget(app(const SizedBox()));
    expect(sent, [null]);
  }, variant: macOS);

  testWidgets('removing the last lights row sends no spot', (tester) async {
    await tester.pumpWidget(app(area()));
    await tester.pumpWidget(app(const SizedBox()));
    expect(sent, [
      {'x': 7.0, 'y': 14.0, 'minX': 0.0, 'maxX': 60.0},
      null,
    ]);
  }, variant: macOS);

  testWidgets('swapping one lights row for another in the same frame never '
      'sends no spot in between', (tester) async {
    await tester.pumpWidget(app(area(key: const ValueKey('side'))));
    await tester.pumpWidget(app(area(key: const ValueKey('rail'))));
    expect(sent, isNot(contains(null)));
  }, variant: macOS);

  testWidgets('a lights row covered by an opaque page sends no spot, and '
      'sends it again when the page goes away', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      TrafficLights(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) =>
                  Align(alignment: Alignment.topLeft, child: area()),
            ),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox()),
    );
    await tester.pumpAndSettle();
    expect(sent.last, isNull);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sent.last, {'x': 7.0, 'y': 14.0, 'minX': 0.0, 'maxX': 60.0});
  }, variant: macOS);

  testWidgets('other platforms send nothing', (tester) async {
    await tester.pumpWidget(app(area()));
    await tester.pumpWidget(app(const SizedBox()));
    expect(sent, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
