import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/settings/network_settings.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 各類快取用了多少位元組，索引每次變動（下載、淘汰、清除）都跟著更新。快取庫
/// 還沒開好或開不起來時是 `null`（用量顯示 0）。
final cacheUsageProvider = StreamProvider.autoDispose<Map<CacheCategory, int>?>(
  (ref) async* {
    final CacheStore store;
    try {
      store = await ref.watch(cacheStoreProvider.future);
    } on Object {
      // 開不起來已由 cacheStoreProvider 記下。
      yield null;
      return;
    }
    yield* store.watchUsage();
  },
);

/// 設定頁的「網路」組：快取上限、各類用量、清除快取（ADR 0016 §決定 3）。
class NetworkControls extends ConsumerWidget {
  const NetworkControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkProvider).value;
    if (network == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).network;
    final notifier = ref.read(networkProvider.notifier);
    final spacing = AppTokens.of(context).spacing;
    final textTheme = Theme.of(context).textTheme;
    final usage = ref.watch(cacheUsageProvider).value;
    final defaultLimit = network.stored.cacheLimitMebibytes == null
        ? network.cacheLimitMebibytes
        : null;
    String size(int mebibytes) => '$mebibytes MB';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.cacheLimit, style: textTheme.titleSmall),
        // 未設定時選中的是平台預設，並標明；選任何一項才寫進資料庫。
        RadioGroup<int>(
          groupValue: network.cacheLimitMebibytes,
          onChanged: (mebibytes) {
            if (mebibytes == null) return;
            unawaited(notifier.setCacheLimit(mebibytes));
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mebibytes in {
                ...cacheLimitOptionsMebibytes,
                network.cacheLimitMebibytes,
              }.toList()..sort())
                RadioListTile<int>(
                  value: mebibytes,
                  title: Text(
                    mebibytes == defaultLimit
                        ? t.cacheLimitDefault(size: size(mebibytes))
                        : size(mebibytes),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.x4),
        Text(t.usage, style: textTheme.titleSmall),
        SizedBox(height: spacing.x2),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t.artwork),
          trailing: Text(
            formatByteSize(usage?[CacheCategory.image] ?? 0),
            style: textTheme.bodyMedium,
          ),
        ),
        SizedBox(height: spacing.x2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: () => unawaited(_confirmClear(context, ref)),
            child: Text(t.clear),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    // 對話框期間視窗跨過斷點時這個 widget 會換位置重建，`ref` 就不能再用：要用的
    // 先取好。
    final t = ref.read(translationsProvider).network;
    // 還在開的也等它開好再清；開不起來（已由 cacheStoreProvider 記下）就沒有
    // 磁碟上的快取要清。
    final store = ref
        .read(cacheStoreProvider.future)
        .then<CacheStore?>((store) => store, onError: (Object _) => null);
    final toaster = ref.read(toasterProvider);
    final log = ref.read(logProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.clearTitle),
        content: Text(t.clearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.clear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var cleared = true;
    try {
      await (await store)?.clear();
    } on Object catch (error, stackTrace) {
      // 清除失敗是快取庫的檔案問題，不是使用者資料；記下來，不報成功，用量照索引
      // 如實顯示。
      cleared = false;
      log.error(
        'Failed to clear the cache',
        tag: cacheLogTag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    // Flutter 記憶體裡解碼好的圖也一併清（ADR 0016 §決定 3）。
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (cleared) toaster.success(t.cleared);
  }
}
