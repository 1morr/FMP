import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/blank_screenshot.dart';

/// 實跑收到整張幾乎同色的截圖要判失敗（票 06b：`winpc` 螢幕睡著時截到白圖）。
/// PNG 用 Flutter 自己的編碼器產生，列的濾波方式與真的截圖工具一樣是混著用的。
void main() {
  /// 400×300 的白底；
  /// [frame] 時外圍加一圈 10 寬的黑框；[gradient] 是一條 320 寬漸層的高度。
  Future<Uint8List> screenshot(
    WidgetTester tester, {
    bool frame = false,
    double gradient = 0,
  }) async {
    return (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawRect(
          const ui.Rect.fromLTWH(0, 0, 400, 300),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF),
        );
      if (frame) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(5, 5, 390, 290),
          ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 10
            ..isAntiAlias = false
            ..color = const ui.Color(0xFF000000),
        );
      }
      if (gradient > 0) {
        // 正常畫面的玻璃、陰影與反鋸齒會帶出上百種顏色（實測最少 754 種）。
        canvas.drawRect(
          ui.Rect.fromLTWH(40, 40, 320, gradient),
          ui.Paint()
            ..shader = ui.Gradient.linear(
              const ui.Offset(40, 0),
              const ui.Offset(360, 0),
              [const ui.Color(0xFF101018), const ui.Color(0xFF8080A0)],
            ),
        );
      }
      final image = await recorder.endRecording().toImage(400, 300);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    }))!;
  }

  testWidgets('an all-white screenshot is blank, and says why', (tester) async {
    expect(
      blankScreenshotReason(await screenshot(tester)),
      'only 1 colours in 400x300 pixels',
    );
  });

  testWidgets('a white window inside a black frame is blank', (tester) async {
    // winpc 螢幕睡著時 PrintWindow 截到的樣子：白色只佔約 97%。
    expect(
      blankScreenshotReason(await screenshot(tester, frame: true)),
      'only 2 colours in 400x300 pixels',
    );
  });

  testWidgets('a framed page with some shading is not blank', (tester) async {
    expect(
      blankScreenshotReason(
        await screenshot(tester, frame: true, gradient: 20),
      ),
      isNull,
    );
  });

  testWidgets('a few specks of content still count as blank', (tester) async {
    // 顏色夠多，但 320×1 的漸層只佔 0.27%：99.5% 以上是白的仍算。
    expect(
      blankScreenshotReason(await screenshot(tester, gradient: 1)),
      isNotNull,
    );
  });

  testWidgets('a real run lists its blank and unreadable screenshots', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('fmp_blank_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/01-launch.png')
        .writeAsBytesSync(await screenshot(tester, frame: true, gradient: 20));
    File('${dir.path}/02-search.png')
        .writeAsBytesSync(await screenshot(tester, frame: true));
    File('${dir.path}/03-oops.png').writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/01-launch.txt').writeAsStringSync('首頁');

    expect(blankScreenshots(dir), [
      '02-search.png: only 2 colours in 400x300 pixels',
      '03-oops.png: unreadable PNG (not a PNG)',
    ]);
  });

  test('a file that is not a PNG is a FormatException, not a pass', () {
    expect(
      () => blankScreenshotReason(Uint8List.fromList(List.filled(64, 0))),
      throwsFormatException,
    );
  });
}
