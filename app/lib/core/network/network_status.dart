import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';

/// 網路狀態的 log tag。和每次請求的網路紀錄（`network`）分開，讀網路紀錄的人
/// 不必濾掉它。
const networkStatusLogTag = 'network-status';

/// App 現在能不能上網（ADR 0016 §決定 6）。
enum NetworkStatus {
  /// 有介面，最近的請求沒有連續失敗。
  online,

  /// 系統回報沒有網路介面。
  noInterface,

  /// 有介面，但 [unreachableWindow] 內連續 [unreachableFailures] 次
  /// `NetworkError`、其間沒有任何回應。
  unreachable,
}

/// 一次請求對網路狀態有意義的結果。取消、網域不符、未登入而沒送出的請求不回報。
enum RequestOutcome {
  /// 拿到 HTTP 回應，不論狀態碼（429、404 也是連得上）。
  responded,

  /// 傳輸錯誤（`NetworkError`）：連不上、逾時、TLS 失敗。
  networkError,
}

/// HTTP client 回報請求結果的入口。API client（`SourceHttpClient`）與媒體
/// client 都接到同一個 [NetworkStatusNotifier.report]。
typedef RequestOutcomeSink = void Function(RequestOutcome outcome);

/// 連續失敗多少次算 [NetworkStatus.unreachable]。
const unreachableFailures = 3;

/// 連續失敗要在多久之內。
const unreachableWindow = Duration(seconds: 30);

/// 網路狀態的轉換（design §5.2）。純 Dart：時間以 `clock` 讀，不開計時器、
/// 不輪詢；狀態只隨輸入改變。
///
/// | 從 | 事件 | 到 |
/// |---|---|---|
/// | 任何 | 沒有介面 | `noInterface` |
/// | `noInterface` | 介面出現，或任何回應 | `online` |
/// | `online` | [unreachableWindow] 內第 [unreachableFailures] 次失敗，其間沒有回應 | `unreachable` |
/// | `unreachable` | 任何回應，或介面變化 | `online` |
///
/// 回應是比系統回報更強的證據：Windows 的 `connectivity_plus` 以 NCSI 判斷，
/// 在 proxy、VPN 後面會回報沒有介面而實際上連得上（ADR 0016 §決定 7 的更正）。
/// 失敗則不改變 `noInterface`：介面消失前送出的請求晚一點才失敗，不代表別的事。
final class NetworkStatusMachine {
  NetworkStatus _status = NetworkStatus.online;

  /// 上次回應之後的失敗時間，由舊到新；只在 `online` 時記。
  final _failures = <DateTime>[];

  NetworkStatus get status => _status;

  /// 查了一次介面（啟動、回到前景）。和 [interfacesChanged] 不同，有介面時
  /// 不算介面變化：`unreachable` 留著，等請求結果決定。
  void interfacesChecked({required bool available}) {
    if (!available) {
      _set(NetworkStatus.noInterface);
    } else if (_status == NetworkStatus.noInterface) {
      _set(NetworkStatus.online);
    }
  }

  /// 系統回報介面改變。仍有介面也算變化（換了網路），回到 `online` 重新判斷。
  void interfacesChanged({required bool available}) =>
      _set(available ? NetworkStatus.online : NetworkStatus.noInterface);

  /// 一次請求的結果。
  void requestFinished(RequestOutcome outcome) {
    switch (outcome) {
      case RequestOutcome.responded:
        _set(NetworkStatus.online);
      case RequestOutcome.networkError:
        if (_status != NetworkStatus.online) return;
        final now = clock.now();
        _failures
          ..removeWhere((at) => now.difference(at) > unreachableWindow)
          ..add(now);
        if (_failures.length >= unreachableFailures) {
          _set(NetworkStatus.unreachable);
        }
    }
  }

  void _set(NetworkStatus next) {
    _failures.clear();
    _status = next;
  }
}

/// App 的網路狀態。網路層擁有它（ADR 0016 §決定 6）：輸入是平台層的介面變化
/// 與 HTTP client 回報的請求結果。
final networkStatusProvider =
    NotifierProvider<NetworkStatusNotifier, NetworkStatus>(
      NetworkStatusNotifier.new,
    );

/// [NetworkStatusMachine] 接上平台層與 HTTP client。建立時查一次介面、聽介面
/// 變化；平台沒有介面的實作時只看請求結果。
final class NetworkStatusNotifier extends Notifier<NetworkStatus> {
  final _machine = NetworkStatusMachine();

  /// 第一次介面檢查（[whenFirstChecked]）。狀態的預設是 `online`，要等它才知道真的有
  /// 沒有網路。
  Future<void> _firstCheck = Future.value();

  /// 建立時查的第一次介面完成（沒有介面實作時已經完成）。
  Future<void> whenFirstChecked() => _firstCheck;

  @override
  NetworkStatus build() {
    final interfaces = ref.watch(networkInterfacesProvider);
    if (interfaces != null) {
      final subscription = interfaces.changes.listen(
        (available) => _update(
          () => _machine.interfacesChanged(available: available),
          'interfaces changed',
        ),
        onError: (Object error, StackTrace stackTrace) =>
            _readFailed(error, stackTrace),
      );
      ref.onDispose(subscription.cancel);
      _firstCheck = recheckInterfaces();
    }
    return _machine.status;
  }

  /// HTTP client 每次送出後回報（[RequestOutcomeSink]）。
  void report(RequestOutcome outcome) =>
      _update(() => _machine.requestFinished(outcome), outcome.name);

  /// 再查一次介面。Android 8 起 App 在背景收不到介面變化，回到前景時呼叫
  /// （`connectivity_plus` 的 README）。
  Future<void> recheckInterfaces() async {
    final interfaces = ref.read(networkInterfacesProvider);
    if (interfaces == null) return;
    final bool available;
    try {
      available = await interfaces.check();
    } on Object catch (error, stackTrace) {
      if (ref.mounted) _readFailed(error, stackTrace);
      return;
    }
    if (!ref.mounted) return;
    _update(
      () => _machine.interfacesChecked(available: available),
      'interfaces checked',
    );
  }

  void _update(void Function() event, String cause) {
    final previous = _machine.status;
    event();
    final next = _machine.status;
    if (next == previous) return;
    ref
        .read(logProvider)
        .info(
          'Network status changed',
          tag: networkStatusLogTag,
          fields: {'from': previous.name, 'to': next.name, 'cause': cause},
        );
    state = next;
  }

  /// 讀不到介面：狀態不動，只看請求結果。
  void _readFailed(Object error, StackTrace stackTrace) => ref
      .read(logProvider)
      .warning(
        'Failed to read network interfaces',
        tag: networkStatusLogTag,
        error: error,
        stackTrace: stackTrace,
      );
}
