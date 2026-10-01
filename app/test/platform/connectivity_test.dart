import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/connectivity/connectivity_plus_interfaces.dart';

void main() {
  late List<ConnectivityResult> current;
  late StreamController<List<ConnectivityResult>> changes;
  late ConnectivityPlusInterfaces interfaces;

  setUp(() {
    current = [ConnectivityResult.wifi];
    // broadcast：沒人聽時 close() 也會完成（tearDown 等它）。
    changes = StreamController.broadcast();
    addTearDown(changes.close);
    interfaces = ConnectivityPlusInterfaces(
      check: () async => current,
      changes: () => changes.stream,
    );
  });

  test('only `none` means there is no interface', () async {
    for (final (results, expected) in [
      ([ConnectivityResult.none], false),
      ([ConnectivityResult.wifi], true),
      ([ConnectivityResult.mobile], true),
      ([ConnectivityResult.ethernet, ConnectivityResult.vpn], true),
      ([ConnectivityResult.other], true),
    ]) {
      current = results;
      expect(await interfaces.check(), expected, reason: '$results');
    }
  });

  test('every change is passed on, even between two kinds of interface', () {
    // 換了網路（Wi-Fi → 行動網路）也是一次變化：網路層據此離開 unreachable。
    expect(interfaces.changes, emitsInOrder([true, true, false, true]));
    changes
      ..add([ConnectivityResult.wifi])
      ..add([ConnectivityResult.mobile])
      ..add([ConnectivityResult.none])
      ..add([ConnectivityResult.ethernet]);
  });
}
