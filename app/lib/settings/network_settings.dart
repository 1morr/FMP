import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/platform/platform_capabilities.dart';

/// 設定頁「快取上限」的選項（MiB，ADR 0016 §決定 3）。
const cacheLimitOptionsMebibytes = [128, 256, 512, 1024];

/// 「網路」設定套用預設之後的值（ADR 0011 §決定 7）。
@immutable
final class Network {
  const Network({required this.cacheLimitMebibytes, required this.stored});

  /// 生效的快取上限（MiB）：使用者設定的，沒有就是平台宣告的預設。
  final int cacheLimitMebibytes;

  /// 使用者設定過的值；欄位為 `null` 表示沒設定過、目前用的是預設。
  final NetworkSettings stored;

  @override
  bool operator ==(Object other) =>
      other is Network &&
      other.cacheLimitMebibytes == cacheLimitMebibytes &&
      other.stored == stored;

  @override
  int get hashCode => Object.hash(cacheLimitMebibytes, stored);

  @override
  String toString() =>
      'Network(cacheLimitMebibytes: $cacheLimitMebibytes, stored: $stored)';
}

/// 在讀取時套用預設：沒設定過的欄位用 [defaultCacheLimitMebibytes]（平台層宣告，
/// `PlatformCapabilities.cache`）。預設值不寫進資料庫，改預設不需要 migration。
Network resolveNetwork(
  NetworkSettings stored, {
  required int defaultCacheLimitMebibytes,
}) => Network(
  cacheLimitMebibytes: stored.cacheLimitMebibytes ?? defaultCacheLimitMebibytes,
  stored: stored,
);

/// 「網路」設定：監看 `network_settings` 那一列，對外是套用預設後的 [Network]。
///
/// 預設上限來自平台宣告（`PlatformCapabilities.cache`）。
final networkProvider = StreamNotifierProvider<NetworkNotifier, Network>(
  NetworkNotifier.new,
);

final class NetworkNotifier extends StreamNotifier<Network> {
  @override
  Stream<Network> build() {
    final defaultLimit = ref
        .watch(platformCapabilitiesProvider)
        .cache!
        .defaultLimitMebibytes;
    return ref
        .watch(networkSettingsRepositoryProvider)
        .watch()
        .map(
          (stored) =>
              resolveNetwork(stored, defaultCacheLimitMebibytes: defaultLimit),
        );
  }

  /// 只寫快取上限這個欄位；`null` 清回沒設定過（跟隨平台預設）。
  Future<void> setCacheLimit(int? mebibytes) {
    final repository = ref.read(networkSettingsRepositoryProvider);
    return mebibytes == null
        ? repository.clear(cacheLimitMebibytes: true)
        : repository.write(cacheLimitMebibytes: mebibytes);
  }
}
