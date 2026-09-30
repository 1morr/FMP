// PROBE ONLY (branch probe/youtubejs): does the plugin runtime allow eval /
// new Function? YouTube.js needs one for player-JS deciphering (signature / n),
// which the VISIONOS path does not use, but other clients would.
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../plugins/plugin_harness.dart';

void main() {
  test('new Function and indirect eval run inside a plugin', () async {
    final harness = PluginHarness();
    final plugin = await harness.load(
      pluginSource('''
export function search() {
  const f = new Function('a', 'b', 'return a + b');
  const e = (0, eval)('6 * 7');
  return { items: [], hasMore: f(1, 2) === 3 && e === 42 };
}
'''),
    );
    final page = await plugin.search(SearchQuery(keyword: 'x'));
    expect(page.hasMore, isTrue);
  });
}
