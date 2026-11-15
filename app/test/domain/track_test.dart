import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track.dart';

void main() {
  group('TrackRef', () {
    test('equals another ref with the same plugin id and track id', () {
      // 一個 const、一個執行時才建：相等不能靠同一個實例。
      const a = TrackRef(pluginId: 'demo', trackId: 'x1');
      final b = TrackRef(pluginId: 'demo', trackId: ['x', '1'].join());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when either the plugin id or the track id differs', () {
      const ref = TrackRef(pluginId: 'demo', trackId: 'x1');

      expect(ref, isNot(const TrackRef(pluginId: 'other', trackId: 'x1')));
      expect(ref, isNot(const TrackRef(pluginId: 'demo', trackId: 'x2')));
    });

    test('the same track id from two plugins is two map keys', () {
      final plays = <TrackRef, int>{
        const TrackRef(pluginId: 'one', trackId: 'same'): 1,
        const TrackRef(pluginId: 'two', trackId: 'same'): 2,
      };
      plays[TrackRef(pluginId: 'one', trackId: ['sa', 'me'].join())] = 3;

      expect(plays, {
        const TrackRef(pluginId: 'one', trackId: 'same'): 3,
        const TrackRef(pluginId: 'two', trackId: 'same'): 2,
      });
    });

    test('logs as plugin id / track id', () {
      const ref = TrackRef(pluginId: 'demo', trackId: 'BV1xx?p=2');

      expect(ref.logId, 'demo/BV1xx?p=2');
      expect('$ref', 'demo/BV1xx?p=2');
    });
  });
}
