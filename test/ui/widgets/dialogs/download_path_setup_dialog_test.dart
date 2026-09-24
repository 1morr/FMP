import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/download/download_path_provider.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:fmp/ui/widgets/dialogs/download_path_setup_dialog.dart';

import '../../../support/fakes/fake_settings_repository.dart';

/// 第一次下載前的選目錄對話框。
///
/// 選好的目錄存不進設定時，對話框會回到「可以再選一次」的狀態；如果只是這樣而
/// 沒有任何提示，使用者看到的就是按了沒反應。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a path that cannot be saved is reported to the user', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);

    await tester.pumpWidget(
      TranslationProvider(
        child: ProviderScope(
          overrides: [
            downloadPathManagerProvider.overrideWithValue(
              _UnsavablePathManager(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DownloadPathSetupDialog()),
          ),
        ),
      ),
    );

    await tester.tap(find.text(t.downloadPathSetup.selectFolder));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text(t.downloadPathSetup.saveFailed(error: t.error.noPermission)),
      findsOneWidget,
    );
    // 回到可以重選的狀態，而不是卡在轉圈。
    expect(find.text(t.downloadPathSetup.selectFolder), findsOneWidget);
  });
}

/// 平台的資料夾選擇器在測試裡叫不起來，這裡直接回一個路徑；失敗的是之後的儲存。
class _UnsavablePathManager extends DownloadPathManager {
  _UnsavablePathManager() : super(FakeSettingsRepository(Settings()));

  @override
  Future<String?> selectDirectory(BuildContext context) async => 'C:/Music/FMP';

  @override
  Future<void> saveDownloadPath(String path) async {
    throw PathAccessException(path, const OSError('Access is denied', 5));
  }
}
