import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/platform/platform_capabilities.dart';

/// 設定頁「快取上限」的選項（MiB，ADR 0016 §決定 3）。
const cacheLimitOptionsMebibytes = [128, 256, 512, 1024];

/// 電台狀態刷新間隔的選項（分，ADR 0017 §決定 6）：`0` 是關閉。
const radioStatusIntervalOptionsMinutes = [0, 1, 3, 5, 10];

/// 電台狀態刷新間隔的預設（分）。
const defaultRadioStatusIntervalMinutes = 5;

/// 「網路」設定套用預設之後的值（ADR 0011 §決定 7）。
@immutable
final class Network {
  const Network({
    required this.cacheLimitMebibytes,
    required this.radioStatusInterval,
    required this.stored,
  });

  /// 生效的快取上限（MiB）：使用者設定的，沒有就是平台宣告的預設。
  final int cacheLimitMebibytes;

  /// 電台狀態的刷新間隔；`null` 是關閉（設定為 0 分）。
  final Duration? radioStatusInterval;

  /// 使用者設定過的值；欄位為 `null` 表示沒設定過、目前用的是預設。
  final NetworkSettings stored;

  @override
  bool operator ==(Object other) =>
      other is Network &&
      other.cacheLimitMebibytes == cacheLimitMebibytes &&
      other.radioStatusInterval == radioStatusInterval &&
      other.stored == stored;

  @override
  int get hashCode =>
      Object.hash(cacheLimitMebibytes, radioStatusInterval, stored);

  @override
  String toString() =>
      'Network(cacheLimitMebibytes: $cacheLimitMebibytes, '
      'radioStatusInterval: $radioStatusInterval, stored: $stored)';
}

/// 在讀取時套用預設：沒設定過的快取上限用 [defaultCacheLimitMebibytes]（平台層宣告，
/// `PlatformCapabilities.cache`），電台間隔用 [defaultRadioStatusIntervalMinutes]。預設值不寫進資料庫，改預設不需要 migration。
Network resolveNetwork(
  NetworkSettings stored, {
  required int defaultCacheLimitMebibytes,
}) => Network(
  cacheLimitMebibytes: stored.cacheLimitMebibytes ?? defaultCacheLimitMebibytes,
  radioStatusInterval: switch (stored.radioStatusIntervalMinutes ??
      defaultRadioStatusIntervalMinutes) {
    0 => null,
    final minutes => Duration(minutes: minutes),
  },
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

  /// 只寫電台狀態刷新間隔；`0` 是關閉，`null` 清回沒設定過（跟隨預設）。不在
  /// [radioStatusIntervalOptionsMinutes] 裡的值拋 [ArgumentError]。
  Future<void> setRadioStatusInterval(int? minutes) {
    final repository = ref.read(networkSettingsRepositoryProvider);
    if (minutes == null) {
      return repository.clear(radioStatusIntervalMinutes: true);
    }
    if (!radioStatusIntervalOptionsMinutes.contains(minutes)) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'must be one of $radioStatusIntervalOptionsMinutes',
      );
    }
    return repository.write(radioStatusIntervalMinutes: minutes);
  }
}
