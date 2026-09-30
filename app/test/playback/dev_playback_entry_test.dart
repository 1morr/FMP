import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/dev_playback_entry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:yaml/yaml.dart';

import '../plugins/plugin_harness.dart';

void main() {
  group('devPlaybackRequest', () {
    test('the bare flag plays the bundled test plugin', () {
      expect(
        devPlaybackRequest(AppFlavor.dev, ['--other', '--fmp-dev-playback']),
        isEmpty,
      );
    });

    test('each value is a track key, in order', () {
      expect(
        devPlaybackRequest(AppFlavor.dev, [
          '--fmp-dev-playback=bilibili:BV1a',
          '--fmp-dev-plugin=/data/local/tmp/bilibili.js',
          '--fmp-dev-playback=bilibili:BV1b:7',
        ]),
        ['bilibili:BV1a', 'bilibili:BV1b:7'],
      );
    });

    test('is absent without the flag', () {
      expect(
        devPlaybackRequest(AppFlavor.dev, ['--fmp-dev-playbackx']),
        isNull,
      );
    });

    test('prod reads nothing', () {
      expect(
        devPlaybackRequest(AppFlavor.prod, [
          '--fmp-dev-playback',
          '--fmp-dev-playback=bilibili:BV1a',
        ]),
        isNull,
      );
    });
  });

  group('parseDevPlaybackTracks', () {
    test('parses two- and three-part keys', () {
      expect(
        parseDevPlaybackTracks(['bilibili:BV1a', ' bilibili:BV1b:7']),
        const [
          TrackKeyParts(sourceTypeId: 'bilibili', sourceId: 'BV1a'),
          TrackKeyParts(sourceTypeId: 'bilibili', sourceId: 'BV1b', cid: 7),
        ],
      );
    });

    test('rejects a malformed key', () {
      expect(
        () => parseDevPlaybackTracks(['bilibili:BV1a', 'nope']),
        throwsFormatException,
      );
    });
  });

  test('the test tracks resolve in the bundled test plugin', () async {
    expect(devTestPluginAsset, testPluginFile.path);
    final plugin = await PluginHarness().load(
      testPluginFile.readAsStringSync(),
    );
    for (final id in devTestTracks) {
      final candidates = await plugin.resolveStream(
        StreamRequest(
          sourceId: id,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );
      expect(candidates.first.url.scheme, 'asset');
    }
  });

  test('the test plugin is bundled only in the dev flavor', () {
    final assets =
        (loadYaml(File('pubspec.yaml').readAsStringSync())
                as YamlMap)['flutter']['assets']
            as YamlList;
    expect(
      assets,
      contains(
        allOf(
          containsPair('path', 'test/fixtures/plugins/test_plugin/'),
          containsPair('flavors', ['dev']),
        ),
      ),
    );
    expect(
      devTestPluginAsset,
      startsWith('test/fixtures/plugins/test_plugin/'),
    );
  });
}
