import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/download_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/download/download_providers.dart';
import 'package:fmp/providers/download/download_settings_provider.dart';
import 'package:fmp/services/download/download_service.dart';
import 'package:fmp/ui/pages/settings/download_manager_page.dart';
import 'package:isar_community/isar.dart';

import '../../../support/isar_test_harness.dart';

/// 一列的曲目查詢永久失敗時，畫面必須說它失敗，不能一直說「載入中」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeIsarForTests();
  });

  Future<Widget> buildPage(
    tester, {
    required AsyncValue<Track?> trackState,
    required List<Isar> disposables,
  }) async {
    final isar = (await tester.runAsync(
      () => Isar.open(
        [TrackSchema, DownloadTaskSchema, SettingsSchema, PlaylistSchema],
        directory: '${Directory.current.path}/.dart_tool',
        name: 'download_manager_error_state_test',
      ),
    ))!;
    disposables.add(isar);

    final sourceManager = SourceManager();
    addTearDown(sourceManager.dispose);

    final service = DownloadService(
      downloadRepository: DownloadRepository(isar),
      trackRepository: TrackRepository(isar),
      settingsRepository: SettingsRepository(isar),
      sourceManager: sourceManager,
    );

    final task = DownloadTask()
      ..id = 7
      ..trackId = 42
      ..status = DownloadStatus.failed;

    return TranslationProvider(
      child: ProviderScope(
        // 與 `main.dart:192` 一致：關掉 Riverpod 3 的自動重試，否則失敗的
        // provider 會被重跑而停在載入態，測不到 error 分支。
        retry: (retryCount, error) => null,
        overrides: [
          downloadServiceProvider.overrideWithValue(service),
          downloadTasksProvider.overrideWith((ref) => Stream.value([task])),
          maxConcurrentDownloadsProvider.overrideWithValue(1),
          trackByIdProvider(42).overrideWith(
            (ref) => switch (trackState) {
              AsyncData(:final value) => Future.value(value),
              _ => Future<Track?>.error(
                const FileSystemException('database unavailable'),
              ),
            },
          ),
        ],
        child: const MaterialApp(home: DownloadManagerPage()),
      ),
    );
  }

  testWidgets('a failed track lookup is not rendered as still loading', (
    tester,
  ) async {
    LocaleSettings.setLocale(AppLocale.en);
    final disposables = <Isar>[];
    addTearDown(
      () => tester.runAsync(() async {
        for (final isar in disposables) {
          await isar.close(deleteFromDisk: true);
        }
      }),
    );

    await tester.pumpWidget(
      await buildPage(
        tester,
        trackState: const AsyncError(
          FileSystemException('database unavailable'),
          StackTrace.empty,
        ),
        disposables: disposables,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text(t.settings.downloadManager.trackLoadFailed),
      findsOneWidget,
      reason: 'the row must say the lookup failed',
    );
    expect(
      find.text(t.general.loading),
      findsNothing,
      reason: 'a permanently failed lookup must not read as in progress',
    );
  });

  testWidgets('a resolved track still shows its title', (tester) async {
    LocaleSettings.setLocale(AppLocale.en);
    final disposables = <Isar>[];
    addTearDown(
      () => tester.runAsync(() async {
        for (final isar in disposables) {
          await isar.close(deleteFromDisk: true);
        }
      }),
    );

    await tester.pumpWidget(
      await buildPage(
        tester,
        trackState: AsyncData(
          Track()
            ..id = 42
            ..sourceId = 'bv1'
            ..sourceType = SourceIds.bilibili
            ..title = 'Track title',
        ),
        disposables: disposables,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Track title'), findsOneWidget);
    expect(find.text(t.settings.downloadManager.trackLoadFailed), findsNothing);
  });
}
