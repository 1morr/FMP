import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/unsupported_platform_app.dart';
import 'package:fmp/core/app_flavor.dart';

void main() {
  testWidgets('tells the user the platform is not supported yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      const UnsupportedPlatformApp(flavor: AppFlavor.dev),
    );

    expect(find.text('此平台尚未支援'), findsOneWidget);
  });
}
