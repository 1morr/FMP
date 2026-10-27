import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/plugins/source_dto.dart';

void main() {
  test('a track summary becomes a track info field by field', () {
    final summary = TrackSummary(
      sourceTypeId: 'fmp-test',
      sourceId: 'a',
      cid: 7,
      title: 'Song a',
      uploader: 'Someone',
      duration: const Duration(seconds: 61),
      artwork: [
        Artwork(url: Uri.parse('https://img.example/a-small.jpg'), width: 80),
        Artwork(url: Uri.parse('https://img.example/a.jpg')),
      ],
    );

    final info = summary.toTrackInfo();
    expect(
      info,
      TrackInfo(
        sourceTypeId: 'fmp-test',
        sourceId: 'a',
        cid: 7,
        title: 'Song a',
        uploader: 'Someone',
        duration: const Duration(seconds: 61),
        artwork: [
          TrackArtwork(
            url: Uri.parse('https://img.example/a-small.jpg'),
            width: 80,
          ),
          TrackArtwork(url: Uri.parse('https://img.example/a.jpg')),
        ],
      ),
    );
    expect(
      info.key,
      const TrackKeyParts(sourceTypeId: 'fmp-test', sourceId: 'a', cid: 7),
    );
  });

  // 不經 JS 執行環境的解析：optional 欄位 viewCount、TrackDetail.webUrl、LiveRoom.area
  // （ADR 0035 §決定 10；執行環境版在 script_source_plugin_test 等）。
  final hosts = AllowedHosts(['example.test']);

  group('viewCount', () {
    SearchPage page(Object? viewCount, {bool give = true}) =>
        SearchPage.fromJson(
          {
            'items': [
              {'sourceId': 'a', 'title': 'A', if (give) 'viewCount': viewCount},
            ],
            'hasMore': false,
          },
          sourceTypeId: 'fmp-test',
          allowedHosts: hosts,
        );

    test('is kept, zero included, and reaches the track info', () {
      expect(page(12345).items.single.viewCount, 12345);
      expect(page(0).items.single.viewCount, 0);
      expect(page(12345).items.single.toTrackInfo().viewCount, 12345);
    });

    test('missing or null is null', () {
      expect(page(null, give: false).items.single.viewCount, isNull);
      expect(page(null).items.single.viewCount, isNull);
    });

    for (final bad in [-1, 1.5, '12', true]) {
      test('$bad is a FormatException', () {
        expect(() => page(bad), throwsFormatException);
      });
    }
  });

  group('TrackDetail.webUrl', () {
    TrackDetail detail(Object? webUrl) =>
        TrackDetail.fromJson({'webUrl': webUrl}, allowedHosts: hosts);

    test('an allowed https URL is kept', () {
      final value = detail('https://www.example.test/v/1');

      expect(value.webUrl, Uri.parse('https://www.example.test/v/1'));
      expect(value.isEmpty, isFalse);
    });

    test('missing or null is null', () {
      expect(
        TrackDetail.fromJson(<String, Object?>{}, allowedHosts: hosts).webUrl,
        isNull,
      );
      expect(detail(null).webUrl, isNull);
    });

    // 不符的網址只是丟掉（ADR 0035 §決定 10：沒有就不可點），其他欄位照常；
    // 和 Artwork.url 整筆拒收不同。回呼只拿到原因，不拿網址。
    for (final (bad, reason) in [
      ('https://evil.test/v/1', 'hostNotAllowed'),
      ('https://evil-example.test/v/1', 'hostNotAllowed'),
      ('http://example.test/v/1', 'notHttps'),
      ('not a url', 'notHttps'),
      ('https://example.test:x/', 'notHttps'),
    ]) {
      test('$bad is dropped and the rest is kept', () {
        final reasons = <String>[];
        final value = TrackDetail.fromJson(
          {'webUrl': bad, 'album': 'Album'},
          allowedHosts: hosts,
          onWebUrlDropped: reasons.add,
        );

        expect(value.webUrl, isNull);
        expect(value.album, 'Album');
        expect(reasons, [reason]);
      });
    }

    test('an allowed URL does not report a drop', () {
      final reasons = <String>[];
      TrackDetail.fromJson(
        {'webUrl': 'https://example.test/v/1'},
        allowedHosts: hosts,
        onWebUrlDropped: reasons.add,
      );

      expect(reasons, isEmpty);
    });

    test('a non-string is a FormatException', () {
      expect(() => detail(1), throwsFormatException);
    });
  });

  group('LiveRoom.area', () {
    LiveRoom room(Object? area) => LiveRoom.fromJson({
      'roomId': 'r',
      'title': 'T',
      'status': 'live',
      'area': area,
    }, allowedHosts: hosts);

    test('is trimmed', () => expect(room('  Games ').area, 'Games'));

    test('empty, blank or null is null', () {
      expect(room('').area, isNull);
      expect(room('   ').area, isNull);
      expect(room(null).area, isNull);
    });

    test('a non-string is a FormatException', () {
      expect(() => room(3), throwsFormatException);
    });
  });
}
