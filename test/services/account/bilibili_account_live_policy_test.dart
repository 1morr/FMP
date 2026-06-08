import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bilibili account delegates medal wall live lookup to live client', () {
    final accountSource =
        File('lib/services/account/bilibili_account_service.dart')
            .readAsStringSync();
    final liveClientSource =
        File('lib/data/sources/bilibili_live_client.dart').readAsStringSync();

    expect(accountSource, contains('BilibiliLiveClient'));
    expect(accountSource, contains('getMedalWallRooms'));
    expect(accountSource, isNot(contains('getRoomInfoOld')));

    expect(
      liveClientSource,
      contains('SourceHttpPolicy.createBilibiliLiveDio'),
    );
    expect(liveClientSource, contains('MedalWall'));
    expect(liveClientSource, contains('getRoomInfoOld'));
  });
}
