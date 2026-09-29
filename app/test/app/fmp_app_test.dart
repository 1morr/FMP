import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/core/app_flavor.dart';

void main() {
  testWidgets('shows the app name, flavor and data directory', (tester) async {
    await tester.pumpWidget(
      const FmpApp(flavor: AppFlavor.dev, dataDirectoryPath: '/data/fmp-dev'),
    );

    expect(find.text('FMP Dev'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('/data/fmp-dev'), findsOneWidget);
  });

  testWidgets('omits the data directory when the platform has none', (
    tester,
  ) async {
    await tester.pumpWidget(const FmpApp(flavor: AppFlavor.prod));

    expect(find.text('FMP'), findsOneWidget);
    expect(find.text('prod'), findsOneWidget);
  });
}
