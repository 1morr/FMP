import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bilibili account live imports use live HTTP policy', () {
    final source = File('lib/services/account/bilibili_account_service.dart')
        .readAsStringSync();

    expect(source, contains('SourceHttpPolicy.createBilibiliLiveDio'));
    expect(source, contains('_liveDio.get'));
    expect(source, contains('MedalWall'));
    expect(source, contains('getRoomInfoOld'));
  });
}
