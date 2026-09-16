import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/system/update_provider.dart';

const _tag = 'UpdateAutoCheck';

/// 這個進程能不能真的發出檢查請求。
///
/// `UpdateService` 直接打 GitHub API，而 `flutter test` 跑的是真的 Dio 與真的
/// `PackageInfo`，所以預設在測試進程裡關掉 —— 讓一個啟動副作用在整個測試套件裡
/// 對外發請求，是那種只會在 CI 上偶爾紅一次的東西。provider 測試把它覆寫成
/// true 來驅動真正的邏輯。
final updateAutoCheckEnabledProvider = Provider<bool>(
  (ref) => !Platform.environment.containsKey('FLUTTER_TEST'),
);

/// 啟動到檢查之間的等待。
///
/// 是 provider 而不是直接讀 [AppConstants]，只為了讓 provider 測試不必真的等
/// 那幾秒 —— 延遲的長度與理由仍然屬於 `AppConstants`。
final updateAutoCheckStartupDelayProvider = Provider<Duration>(
  (ref) => AppConstants.autoUpdateCheckStartupDelay,
);

/// 啟動後在背景檢查一次更新，一天最多一次。
///
/// 由 `FMPApp.build` 的 `ref.watch` 錨住（見 `lib/providers/AGENTS.md` §
/// Provider Rules 的「有副作用的 provider 必須錨在 MaterialApp 之上」）。
///
/// **時間戳先寫再送請求。** 失敗的檢查同樣要吃掉當天的額度：反過來寫的話，一台
/// 連不上 GitHub 的機器會在每次啟動時重試，而使用者永遠看不到任何結果。節流的
/// 目的本來就不是「保證每天檢查成功一次」，是「一天最多打擾 GitHub 一次」。
///
/// 為什麼一天一次、以及什麼時候要重新評估這個決定，記在
/// `lib/services/AGENTS.md` § Update System。
final updateAutoCheckProvider = FutureProvider<void>((ref) async {
  if (!ref.read(updateAutoCheckEnabledProvider)) return;

  // await 之前先把要用的東西讀完。Riverpod 3 對已經 dispose 的 Ref 會拋
  // UnmountedRefException，在 await 之前讀完比事後補 ref.mounted 護欄更直接
  //（`accountStatusCheckProvider` 出於同樣理由這樣寫）。
  final SettingsRepository settingsRepository;
  final ToastService toastService;
  final Duration startupDelay;
  try {
    settingsRepository = ref.read(settingsRepositoryProvider);
    toastService = ref.read(toastServiceProvider);
    startupDelay = ref.read(updateAutoCheckStartupDelayProvider);
  } catch (e) {
    // 資料庫還沒開 —— 沒有設定就沒有節流簿記，這一輪整個略過。
    AppLogger.debug('Skipping auto update check: $e', _tag);
    return;
  }

  await Future<void>.delayed(startupDelay);
  if (!ref.mounted) return;

  final settings = await settingsRepository.get();
  if (!settings.autoCheckUpdates) {
    AppLogger.debug('Automatic update check is disabled', _tag);
    return;
  }

  final lastCheck = settings.lastUpdateCheckAt;
  if (lastCheck != null &&
      DateTime.now().difference(lastCheck) <
          AppConstants.autoUpdateCheckInterval) {
    AppLogger.debug('Already checked for updates at $lastCheck', _tag);
    return;
  }

  // 先記帳再請求：拋出來的檢查一樣算用掉了今天的額度。
  final now = DateTime.now();
  await settingsRepository.update((s) => s.lastUpdateCheckAt = now);
  AppLogger.info('Auto update check starting (stamped $now)', _tag);
  if (!ref.mounted) return;

  await ref.read(updateProvider.notifier).checkForUpdate();
  if (!ref.mounted) return;

  final state = ref.read(updateProvider);
  switch (state.status) {
    case UpdateStatus.updateAvailable:
      final version = state.updateInfo?.version;
      if (version == null) return;
      AppLogger.info('Auto update check found version $version', _tag);
      toastService.showInfo(
        t.settings.autoCheckUpdates.found(version: version),
      );
    case UpdateStatus.error:
      // 只記 log：使用者沒有要求這次檢查，失敗不該彈東西給他看。
      AppLogger.warning(
        'Auto update check failed: ${state.errorMessage}',
        _tag,
      );
    default:
      AppLogger.info('Auto update check: already up to date', _tag);
  }
});

/// 「自動檢查更新」開關在設定頁的狀態。
///
/// 放在這裡而不是 `lib/providers/settings/`：它控制的就是上面那個 provider，
/// 兩邊讀同一個欄位，分開放只會讓下一個讀者兩邊各找一次。
class AutoCheckUpdatesNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    // 預設 true 與 `Settings.autoCheckUpdates` 一致 —— 載入前後值相同，
    // 開關不會在進入設定頁時播一次開啟動畫。
    return true;
  }

  Future<void> _load() async {
    final settings = await ref.read(settingsRepositoryProvider).get();
    if (!ref.mounted) return;
    state = settings.autoCheckUpdates;
  }

  Future<void> setEnabled(bool value) async {
    await ref
        .read(settingsRepositoryProvider)
        .update((s) => s.autoCheckUpdates = value);
    if (!ref.mounted) return;
    state = value;
  }
}

final autoCheckUpdatesProvider =
    NotifierProvider<AutoCheckUpdatesNotifier, bool>(
      AutoCheckUpdatesNotifier.new,
    );
