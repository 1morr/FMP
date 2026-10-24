import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/queue/queue_view.dart';

/// 佇列目的地的根頁（ADR 0035 §決定 2）：各寬度都是整頁的 [QueueView]；佇列空時是空狀態
/// （PR 8 換成舊版的引導）。
///
/// 外殼的 `IndexedStack` 讓每個目的地一直掛著，所以沒選到時（[visible] 為假）不建清單：
/// 每次切過來都從目前這首附近開始，隱藏時也不替每一列讀 provider。
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!visible) return const SizedBox.shrink();
    // 還在讀佇列時（`null`）什麼都不畫，免得啟動時先閃一下空狀態。
    final empty = ref.watch(
      playbackQueueProvider.select((queue) => queue.value?.entries.isEmpty),
    );
    if (empty == null) return const SizedBox.shrink();
    if (empty) {
      final t = ref.watch(translationsProvider).shell;
      return EmptyState(
        icon: Icons.queue_music,
        title: t.queueEmptyTitle,
        body: t.queueEmptyBody,
      );
    }
    return const QueueView();
  }
}
