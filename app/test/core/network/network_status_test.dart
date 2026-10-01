import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';

import '../../support/fake_network_interfaces.dart';

const _online = NetworkStatus.online;
const _noInterface = NetworkStatus.noInterface;
const _unreachable = NetworkStatus.unreachable;
const _responded = RequestOutcome.responded;
const _networkError = RequestOutcome.networkError;

/// 一台已經走到 [status] 的狀態機（失敗紀錄是空的）。
NetworkStatusMachine _machineAt(NetworkStatus status) {
  final machine = NetworkStatusMachine();
  switch (status) {
    case NetworkStatus.online:
      break;
    case NetworkStatus.noInterface:
      machine.interfacesChanged(available: false);
    case NetworkStatus.unreachable:
      for (var i = 0; i < unreachableFailures; i++) {
        machine.requestFinished(_networkError);
      }
  }
  expect(machine.status, status);
  return machine;
}

void main() {
  // design §5.2 的轉換表，一列一組。時間以 fakeAsync 推進（狀態機以 `clock`
  // 讀時間）。
  group('transition table', () {
    group('any → noInterface when the system reports no interface', () {
      for (final from in NetworkStatus.values) {
        test('from ${from.name}, changed or checked', () {
          final changed = _machineAt(from)..interfacesChanged(available: false);
          expect(changed.status, _noInterface);
          final checked = _machineAt(from)..interfacesChecked(available: false);
          expect(checked.status, _noInterface);
        });
      }
    });

    group('noInterface → online when an interface appears or a request gets '
        'a response', () {
      test('changed', () {
        final machine = _machineAt(_noInterface)
          ..interfacesChanged(available: true);
        expect(machine.status, _online);
      });

      test('checked (back in the foreground)', () {
        final machine = _machineAt(_noInterface)
          ..interfacesChecked(available: true);
        expect(machine.status, _online);
      });

      test('a response', () {
        // 回應比系統回報可靠：Windows 在 proxy、VPN 後面會以 NCSI 回報沒有
        // 介面（ADR 0016 §決定 7 的更正）。
        final machine = _machineAt(_noInterface)..requestFinished(_responded);
        expect(machine.status, _online);
      });

      test('failures do not leave it', () {
        // 介面消失前送出的請求晚一點才失敗，不代表別的事。
        final machine = _machineAt(_noInterface);
        for (var i = 0; i <= unreachableFailures; i++) {
          machine.requestFinished(_networkError);
          expect(machine.status, _noInterface);
        }
      });
    });

    group('online → unreachable on the third failure within 30 s', () {
      test('three failures in a row', () {
        fakeAsync((async) {
          final machine = NetworkStatusMachine();
          for (var i = 1; i < unreachableFailures; i++) {
            machine.requestFinished(_networkError);
            async.elapse(const Duration(seconds: 10));
            expect(machine.status, _online, reason: 'after $i failures');
          }
          machine.requestFinished(_networkError);
          expect(machine.status, _unreachable);
        });
      });

      test('the window includes its end: failures at 0, 15 and 30 s', () {
        fakeAsync((async) {
          final machine = NetworkStatusMachine()
            ..requestFinished(_networkError);
          async.elapse(const Duration(seconds: 15));
          machine.requestFinished(_networkError);
          async.elapse(const Duration(seconds: 15));
          machine.requestFinished(_networkError);
          expect(machine.status, _unreachable);
        });
      });

      test('a failure older than 30 s no longer counts', () {
        fakeAsync((async) {
          final machine = NetworkStatusMachine()
            ..requestFinished(_networkError);
          async.elapse(const Duration(seconds: 15));
          machine.requestFinished(_networkError);
          async.elapse(const Duration(seconds: 15, milliseconds: 1));
          machine.requestFinished(_networkError);
          expect(machine.status, _online);
          // 第二、三次仍在窗內，再一次就到了。
          machine.requestFinished(_networkError);
          expect(machine.status, _unreachable);
        });
      });

      test('a response in between starts the count again', () {
        final machine = NetworkStatusMachine()
          ..requestFinished(_networkError)
          ..requestFinished(_networkError)
          ..requestFinished(_responded)
          ..requestFinished(_networkError)
          ..requestFinished(_networkError);
        expect(machine.status, _online);
        machine.requestFinished(_networkError);
        expect(machine.status, _unreachable);
      });

      test('an interface change in between starts the count again', () {
        final machine = NetworkStatusMachine()
          ..requestFinished(_networkError)
          ..requestFinished(_networkError)
          ..interfacesChanged(available: true)
          ..requestFinished(_networkError);
        expect(machine.status, _online);
      });
    });

    group('unreachable → online', () {
      test('on any response', () {
        final machine = _machineAt(_unreachable)..requestFinished(_responded);
        expect(machine.status, _online);
      });

      test('on an interface change', () {
        final machine = _machineAt(_unreachable)
          ..interfacesChanged(available: true);
        expect(machine.status, _online);
      });

      test('and needs three new failures to go back', () {
        final machine = _machineAt(_unreachable)
          ..requestFinished(_responded)
          ..requestFinished(_networkError)
          ..requestFinished(_networkError);
        expect(machine.status, _online);
        machine.requestFinished(_networkError);
        expect(machine.status, _unreachable);
      });
    });

    group('unreachable stays', () {
      test('on more failures', () {
        final machine = _machineAt(_unreachable)
          ..requestFinished(_networkError);
        expect(machine.status, _unreachable);
      });

      test('when a check finds the interface still there', () {
        // 回到前景時查到有介面不是「介面變化」：等請求結果決定。
        final machine = _machineAt(_unreachable)
          ..interfacesChecked(available: true);
        expect(machine.status, _unreachable);
      });
    });

    test('online stays online when a check finds an interface', () {
      final machine = NetworkStatusMachine()
        ..interfacesChecked(available: true);
      expect(machine.status, _online);
    });
  });

  group('networkStatusProvider', () {
    late Log log;

    ProviderContainer containerWith(NetworkInterfaces? interfaces) {
      log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
      final container = ProviderContainer(
        overrides: [
          logProvider.overrideWithValue(log),
          networkInterfacesProvider.overrideWithValue(interfaces),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    List<Map<String, Object?>> changes() => [
      for (final record in log.history)
        if (record.message == 'Network status changed') record.fields,
    ];

    test('follows the interfaces and the request results, with no timer '
        'left behind', () {
      fakeAsync((async) {
        final interfaces = FakeNetworkInterfaces(available: false);
        final container = containerWith(interfaces);
        final seen = <NetworkStatus>[];
        container.listen(
          networkStatusProvider,
          (_, next) => seen.add(next),
          fireImmediately: true,
        );
        final notifier = container.read(networkStatusProvider.notifier);
        async.flushMicrotasks();
        expect(interfaces.checks, 1, reason: 'checked once when built');

        interfaces.change(available: true);
        for (var i = 0; i < unreachableFailures; i++) {
          notifier.report(_networkError);
          async.elapse(const Duration(seconds: 5));
        }
        notifier.report(_responded);
        interfaces.change(available: false);
        notifier.report(_networkError);
        notifier.report(_responded);
        async.flushMicrotasks();

        expect(seen, [
          _online,
          _noInterface,
          _online,
          _unreachable,
          _online,
          _noInterface,
          _online,
        ]);
        expect(changes(), [
          {
            'from': 'online',
            'to': 'noInterface',
            'cause': 'interfaces checked',
          },
          {
            'from': 'noInterface',
            'to': 'online',
            'cause': 'interfaces changed',
          },
          {'from': 'online', 'to': 'unreachable', 'cause': 'networkError'},
          {'from': 'unreachable', 'to': 'online', 'cause': 'responded'},
          {
            'from': 'online',
            'to': 'noInterface',
            'cause': 'interfaces changed',
          },
          {'from': 'noInterface', 'to': 'online', 'cause': 'responded'},
        ]);
        // ADR 0016 §如何確認：沒有計時器輪詢。
        expect(async.pendingTimers, isEmpty);
        expect(async.periodicTimerCount, 0);
      });
    });

    test('rechecking picks up an interface lost in the background', () {
      fakeAsync((async) {
        final interfaces = FakeNetworkInterfaces();
        final container = containerWith(interfaces);
        container.read(networkStatusProvider);
        async.flushMicrotasks();
        expect(container.read(networkStatusProvider), _online);

        interfaces.available = false;
        container.read(networkStatusProvider.notifier).recheckInterfaces();
        async.flushMicrotasks();
        expect(container.read(networkStatusProvider), _noInterface);
        expect(interfaces.checks, 2);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('without the capability only request results count', () {
      final container = containerWith(null);
      final notifier = container.read(networkStatusProvider.notifier);
      for (var i = 0; i < unreachableFailures; i++) {
        notifier.report(_networkError);
      }
      expect(container.read(networkStatusProvider), _unreachable);
    });

    test('a failed check keeps the status and logs a warning', () async {
      final container = containerWith(_ThrowingInterfaces());
      container.read(networkStatusProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(networkStatusProvider), _online);
      final warning = log.history.singleWhere(
        (record) => record.message == 'Failed to read network interfaces',
      );
      expect(warning.level, LogLevel.warning);
      expect(warning.tag, networkStatusLogTag);
    });
  });
}

final class _ThrowingInterfaces implements NetworkInterfaces {
  @override
  Future<bool> check() async => throw StateError('no channel');

  @override
  Stream<bool> get changes => const Stream.empty();
}
