import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/system/update_provider.dart';
import 'package:fmp/services/update/update_service.dart';

void main() {
  group('UpdateNotifier operation generation', () {
    test('older checkForUpdate completion cannot overwrite newer check',
        () async {
      final service = _FakeUpdateService();
      final notifier = UpdateNotifier(service: service);

      final oldCheck = service.enqueueCheck(_info('v9.9.8'));
      final oldFuture = notifier.checkForUpdate();
      await pumpEventQueue(times: 2);

      final newCheck = service.enqueueCheck(null);
      final newFuture = notifier.checkForUpdate();
      await pumpEventQueue(times: 2);

      newCheck.complete();
      await newFuture;
      expect(notifier.state.status, UpdateStatus.upToDate);

      oldCheck.complete();
      await oldFuture;

      expect(notifier.state.status, UpdateStatus.upToDate);
      expect(notifier.state.updateInfo, isNull);
    });

    test('reset cancels delayed download progress and completion writes',
        () async {
      final service = _FakeUpdateService();
      final notifier = UpdateNotifier(service: service);

      service.enqueueCheck(_info('v9.9.9')).complete();
      await notifier.checkForUpdate();
      expect(notifier.state.status, UpdateStatus.updateAvailable);

      final download = service.enqueueDownload('/tmp/fmp-update.zip');
      final downloadFuture = notifier.downloadAndInstall();
      await pumpEventQueue(times: 2);

      service.progressCallbacks.single(50, 100);
      expect(notifier.state.downloadProgress, 0.5);

      notifier.reset();
      service.progressCallbacks.single(100, 100);
      download.complete();
      await downloadFuture;

      expect(notifier.state.status, UpdateStatus.idle);
      expect(notifier.state.downloadProgress, 0);
      expect(notifier.state.downloadedFilePath, isNull);
    });
  });
}

UpdateInfo _info(String version) {
  return UpdateInfo(
    version: version,
    releaseNotes: 'test release',
    windowsZipDownloadUrl: 'https://example.com/fmp.zip',
    publishedAt: DateTime(2026),
  );
}

class _FakeUpdateService extends UpdateService {
  final List<Completer<UpdateInfo?>> _checks = [];
  final List<Completer<String>> _downloads = [];
  final List<void Function(int received, int total)> progressCallbacks = [];

  Completer<void> enqueueCheck(UpdateInfo? info) {
    final gate = Completer<void>();
    final completer = Completer<UpdateInfo?>();
    _checks.add(completer);
    unawaited(gate.future.then((_) {
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    }));
    return gate;
  }

  Completer<void> enqueueDownload(String filePath) {
    final gate = Completer<void>();
    final completer = Completer<String>();
    _downloads.add(completer);
    unawaited(gate.future.then((_) {
      if (!completer.isCompleted) {
        completer.complete(filePath);
      }
    }));
    return gate;
  }

  @override
  Future<UpdateInfo?> checkForUpdate() {
    return _checks.removeAt(0).future;
  }

  @override
  Future<String?> getExistingDownloadPath(UpdateInfo info) async => null;

  @override
  Future<String> downloadAndInstall(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) {
    if (onProgress != null) {
      progressCallbacks.add(onProgress);
    }
    return _downloads.removeAt(0).future;
  }

  @override
  Future<void> installApk(String filePath) async {}
}
