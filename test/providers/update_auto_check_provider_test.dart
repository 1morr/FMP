import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/providers/system/update_auto_check_provider.dart';
import 'package:fmp/providers/system/update_provider.dart';
import 'package:fmp/services/update/update_service.dart';
import 'package:isar_community/isar.dart';

import '../support/isar_test_harness.dart';

/// 啟動時的自動檢查更新。
///
/// 這裡守的是節流的四個分支，以及那個「先寫時間戳再送請求」的順序 —— 順序反過
/// 來不會有任何編譯或型別錯誤，但會讓一台連不上 GitHub 的機器每次啟動都重試。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('updateAutoCheckProvider', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('update_auto_check_');
      isar = await Isar.open(
        [SettingsSchema],
        directory: tempDir.path,
        name: 'update_auto_check_test',
      );
      settingsRepository = SettingsRepository(isar);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<_FakeUpdateService> run({
      required bool autoCheckUpdates,
      DateTime? lastUpdateCheckAt,
      UpdateInfo? available,
      bool throwOnCheck = false,
      void Function(ToastMessage message)? onToast,
    }) async {
      await settingsRepository.update(
        (s) => s
          ..autoCheckUpdates = autoCheckUpdates
          ..lastUpdateCheckAt = lastUpdateCheckAt,
      );

      final service = _FakeUpdateService(
        available: available,
        throwOnCheck: throwOnCheck,
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          updateAutoCheckEnabledProvider.overrideWithValue(true),
          updateAutoCheckStartupDelayProvider.overrideWithValue(Duration.zero),
          updateProvider.overrideWith(() => UpdateNotifier(service: service)),
        ],
      );
      addTearDown(container.dispose);

      if (onToast != null) {
        container.read(toastServiceProvider).messageStream.listen(onToast);
      }

      await container.read(updateAutoCheckProvider.future);
      return service;
    }

    Future<DateTime?> storedLastCheck() async =>
        (await settingsRepository.get()).lastUpdateCheckAt;

    test('does not check when the setting is off', () async {
      final service = await run(autoCheckUpdates: false);

      expect(service.checkCallCount, 0);
      expect(await storedLastCheck(), isNull);
    });

    test('does not check again within the daily window', () async {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      final service = await run(
        autoCheckUpdates: true,
        lastUpdateCheckAt: oneHourAgo,
      );

      expect(service.checkCallCount, 0);
      expect(await storedLastCheck(), oneHourAgo);
    });

    test('checks again once the daily window has passed', () async {
      final longAgo = DateTime.now().subtract(const Duration(hours: 25));
      final service = await run(
        autoCheckUpdates: true,
        lastUpdateCheckAt: longAgo,
      );

      expect(service.checkCallCount, 1);
      expect(await storedLastCheck(), isNot(longAgo));
      expect(
        (await storedLastCheck())!.isAfter(longAgo),
        isTrue,
        reason: 'the timestamp should have been moved to now',
      );
    });

    test('a failing check still spends the daily budget', () async {
      final service = await run(autoCheckUpdates: true, throwOnCheck: true);

      expect(service.checkCallCount, 1);
      // 時間戳在請求之前就寫下去了，所以失敗照樣記帳 —— 否則一台離線的機器
      // 會在每次啟動時重試。
      expect(await storedLastCheck(), isNotNull);
    });

    test('a found update is announced once', () async {
      final toasts = <ToastMessage>[];
      final service = await run(
        autoCheckUpdates: true,
        available: UpdateInfo(
          version: '9.9.9',
          releaseNotes: 'test release',
          publishedAt: DateTime(2026),
        ),
        onToast: toasts.add,
      );

      expect(service.checkCallCount, 1);
      expect(toasts, hasLength(1));
      expect(toasts.single.type, ToastType.info);
      expect(toasts.single.message, contains('9.9.9'));
    });

    test('an up-to-date result shows nothing', () async {
      final toasts = <ToastMessage>[];
      await run(autoCheckUpdates: true, onToast: toasts.add);

      expect(toasts, isEmpty);
    });
  });
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({this.available, this.throwOnCheck = false});

  final UpdateInfo? available;
  final bool throwOnCheck;
  int checkCallCount = 0;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    checkCallCount++;
    if (throwOnCheck) throw StateError('github is unreachable');
    return available;
  }
}
