import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';

void main() {
  test('parses the two flavors', () {
    expect(AppFlavor.parse('dev'), AppFlavor.dev);
    expect(AppFlavor.parse('prod'), AppFlavor.prod);
  });

  test('refuses a missing or unknown flavor instead of guessing', () {
    expect(() => AppFlavor.parse(null), throwsArgumentError);
    expect(() => AppFlavor.parse('staging'), throwsArgumentError);
  });
}
