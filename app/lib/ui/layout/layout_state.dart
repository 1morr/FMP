import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';

/// 依裝置記住的版面狀態（`layout_state`，design §3.4）。
final layoutStateProvider = StreamProvider<LayoutState>(
  (ref) => ref.watch(layoutStateRepositoryProvider).watch(),
);

/// 右側「正在播放」面板是否展開：沒記過是展開（design §9.4，ADR 0024 §決定 3「常駐」）。
final panelExpandedProvider = Provider<bool>(
  (ref) =>
      ref.watch(layoutStateProvider.select((s) => s.value?.panelExpanded)) ??
      true,
);

/// 左側導覽側欄是否展開：沒記過是收合（ADR 0035 §決定 5，各寬度同一個預設，舊版也是）。
final railExpandedProvider = Provider<bool>(
  (ref) =>
      ref.watch(layoutStateProvider.select((s) => s.value?.railExpanded)) ??
      false,
);

/// 記住的面板寬度；沒記過是 `null`。畫面上的寬度另依視窗夾取。
final panelStoredWidthProvider = Provider<double?>(
  (ref) => ref.watch(layoutStateProvider.select((s) => s.value?.panelWidth)),
);

/// 把面板的展開與寬度寫進 `layout_state`（沒給的不動）；寫成回 `true`。失敗只記 log：
/// 版面狀態沒存到不影響使用，下次再存。
Future<bool> savePanel(WidgetRef ref, {bool? expanded, double? width}) => _save(
  ref,
  'the now playing panel',
  (repository) => repository.write(panelExpanded: expanded, panelWidth: width),
);

/// [savePanel]，不等結果（按鈕的動作用）。
void rememberPanel(WidgetRef ref, {bool? expanded, double? width}) =>
    unawaited(savePanel(ref, expanded: expanded, width: width));

/// 把側欄的展開與否寫進 `layout_state`；寫成回 `true`，失敗只記 log（同 [savePanel]）。
Future<bool> saveRail(WidgetRef ref, {required bool expanded}) => _save(
  ref,
  'the side rail',
  (repository) => repository.write(railExpanded: expanded),
);

/// [saveRail]，不等結果（按鈕的動作用）。
void rememberRail(WidgetRef ref, {required bool expanded}) =>
    unawaited(saveRail(ref, expanded: expanded));

Future<bool> _save(
  WidgetRef ref,
  String what,
  Future<void> Function(LayoutStateRepository repository) write,
) async {
  final repository = ref.read(layoutStateRepositoryProvider);
  final log = ref.read(logProvider);
  try {
    await write(repository);
    return true;
  } on Object catch (error, stackTrace) {
    log.report(
      'Failed to remember $what',
      AppError.wrap(error, stackTrace),
      tag: 'layout',
    );
    return false;
  }
}
