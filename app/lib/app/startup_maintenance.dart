import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/data/providers.dart';

/// 啟動維護的一個項目（ADR 0017 §決定 1）。
final class StartupMaintenanceTask {
  const StartupMaintenanceTask({required this.id, required this.run});

  /// 寫進 log 的識別字。
  final String id;
  final Future<void> Function() run;
}

/// 啟動維護清單，依序跑。項目分屬各層，在這裡由組裝層收集；新項目加在這裡。
final startupMaintenanceTasksProvider = Provider<List<StartupMaintenanceTask>>((
  ref,
) {
  final log = ref.watch(logProvider);
  return [
    StartupMaintenanceTask(
      id: 'log-retention',
      run: () async {
        // 沒有資料目錄的平台沒有 log 檔，沒有東西要刪。
        final file = log.file;
        if (file == null) return;
        final deleted = await file.deleteExpired();
        log.info(
          'Deleted expired log files',
          tag: _tag,
          fields: {'count': deleted},
        );
      },
    ),
    StartupMaintenanceTask(
      id: 'orphan-tracks',
      run: () async {
        final deleted = await ref
            .read(tracksRepositoryProvider)
            .deleteOrphans();
        log.info(
          'Deleted orphan tracks',
          tag: _tag,
          fields: {'count': deleted},
        );
      },
    ),
  ];
});

const _tag = 'maintenance';

/// 依序跑 [tasks]。每項各自 try：失敗經 [Log.report] 進錯誤歷史後接著跑下一項，
/// 不重試、不跳提示（ADR 0013 §決定 5）。每項跑完寫一筆 log。
Future<void> runStartupMaintenance(
  List<StartupMaintenanceTask> tasks,
  Log log,
) async {
  for (final task in tasks) {
    try {
      await task.run();
      log.info(
        'Startup maintenance task finished',
        tag: _tag,
        fields: {'id': task.id, 'outcome': 'ok'},
      );
    } on Object catch (error, stackTrace) {
      log.report(
        'Startup maintenance task failed',
        AppError.wrap(error, stackTrace),
        tag: _tag,
      );
      log.info(
        'Startup maintenance task finished',
        tag: _tag,
        fields: {'id': task.id, 'outcome': 'failed'},
      );
    }
  }
}
