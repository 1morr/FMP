import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

void main() {
  testWidgets('shows the app name, flavor and data directory', (tester) async {
    await tester.pumpWidget(
      appProviderScope(
        overrides: [
          dataDirectoryProvider.overrideWithValue(Directory('/data/fmp-dev')),
        ],
        child: const FmpApp(flavor: AppFlavor.dev),
      ),
    );

    expect(find.text('FMP Dev'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('/data/fmp-dev'), findsOneWidget);
  });
}
