import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/app_info/ios_home_directory.dart';

void main() {
  group('iosHomeDirectory', () {
    test('is the parent of the container tmp directory', () {
      expect(iosHomeDirectory('/c/Application/ABC/tmp'), '/c/Application/ABC');
      expect(iosHomeDirectory('/c/Application/ABC/tmp/'), '/c/Application/ABC');
    });

    test('is null for anything else', () {
      expect(iosHomeDirectory('/var/tmpfiles'), isNull);
      expect(iosHomeDirectory('/c/ABC/cache'), isNull);
      expect(iosHomeDirectory('/c/ABC/mytmp'), isNull);
      expect(iosHomeDirectory('/tmp'), isNull);
      expect(iosHomeDirectory(''), isNull);
    });
  });
}
