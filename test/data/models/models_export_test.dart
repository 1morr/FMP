import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/models.dart';

void main() {
  group('models barrel exports', () {
    test('exports Account with the persisted model set', () {
      final account = Account()
        ..platform = SourceIds.netease
        ..userName = 'tester';

      expect(account.platform, SourceIds.netease);
      expect(account.userName, 'tester');
    });
  });
}
