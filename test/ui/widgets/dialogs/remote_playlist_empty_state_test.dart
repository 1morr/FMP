import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart';

void main() {
  testWidgets('a short sheet with large text scrolls instead of overflowing', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 「加入歌單」面板沒有歌單時，實機字級 2.0 下這裡溢出 34px。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 360,
              height: 150,
              child: RemotePlaylistEmptyState(
                title: 'No playlists yet',
                hint: 'Create a playlist in the library first',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
