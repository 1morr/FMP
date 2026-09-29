import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/database_error_app.dart';
import 'package:fmp/core/app_flavor.dart';

void main() {
  testWidgets('says the database cannot be opened and shows the error', (
    tester,
  ) async {
    await tester.pumpWidget(
      DatabaseErrorApp(
        flavor: AppFlavor.dev,
        error: const FormatException('file is not a database'),
      ),
    );

    expect(find.text('無法開啟資料庫'), findsOneWidget);
    expect(
      find.text('FormatException: file is not a database'),
      findsOneWidget,
    );
  });
}
