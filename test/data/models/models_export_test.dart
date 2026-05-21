import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/models.dart';

void main() {
  group('models barrel exports', () {
    test('exports Account with the persisted model set', () {
      final account = Account()
        ..platform = SourceType.netease
        ..userName = 'tester';

      expect(account.platform, SourceType.netease);
      expect(account.userName, 'tester');
    });
  });
}
