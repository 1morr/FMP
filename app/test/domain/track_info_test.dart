import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_info.dart';

void main() {
  group('displayTitle', () {
    const video = TrackInfo(
      sourceTypeId: 'bilibili',
      sourceId: 'BV1',
      title: 'The video',
    );
    const part = TrackInfo(
      sourceTypeId: 'bilibili',
      sourceId: 'BV1',
      cid: 2,
      title: 'Second',
      partIndex: 2,
      parentTitle: 'The video',
    );

    test('a part reads "video title · P2 part title"', () {
      expect(part.displayTitle, 'The video · P2 Second');
      expect(part.partLabel, 'P2 Second');
    });

    test('a part titled with its own number shows the number once', () {
      const numbered = TrackInfo(
        sourceTypeId: 'bilibili',
        sourceId: 'BV1',
        cid: 3,
        title: 'P3',
        partIndex: 3,
        parentTitle: 'The video',
      );

      expect(numbered.partLabel, 'P3');
      expect(numbered.displayTitle, 'The video · P3');
      // 變異：標題只是長得像（P30、別的序號）時照樣加上序號。
      expect(
        const TrackInfo(
          sourceTypeId: 'bilibili',
          sourceId: 'BV1',
          cid: 3,
          title: 'P30',
          partIndex: 3,
        ).partLabel,
        'P3 P30',
      );
      expect(
        const TrackInfo(
          sourceTypeId: 'bilibili',
          sourceId: 'BV1',
          cid: 3,
          title: 'P2',
          partIndex: 3,
        ).partLabel,
        'P3 P2',
      );
    });

    test('a track that is not a part shows its title', () {
      expect(video.displayTitle, 'The video');
      expect(video.partLabel, 'The video');
    });

    test('a part without the video title falls back to the title', () {
      const orphan = TrackInfo(
        sourceTypeId: 'bilibili',
        sourceId: 'BV1',
        cid: 2,
        title: 'Second',
        partIndex: 2,
      );

      expect(orphan.displayTitle, 'Second');
    });

    test('the part fields take part in equality', () {
      expect(part == part, isTrue);
      expect(
        part ==
            const TrackInfo(
              sourceTypeId: 'bilibili',
              sourceId: 'BV1',
              cid: 2,
              title: 'Second',
              partIndex: 3,
              parentTitle: 'The video',
            ),
        isFalse,
      );
      expect(
        part ==
            const TrackInfo(
              sourceTypeId: 'bilibili',
              sourceId: 'BV1',
              cid: 2,
              title: 'Second',
              partIndex: 2,
              parentTitle: 'Another',
            ),
        isFalse,
      );
    });
  });

  // ADR 0016 §決定 4：最接近且不小於顯示尺寸的一張。
  group('pickArtwork', () {
    TrackArtwork art(String name, [int? width]) =>
        TrackArtwork(url: Uri.parse('https://img.example/$name'), width: width);
    String? pick(List<TrackArtwork> artwork, double pixels) =>
        pickArtwork(artwork, pixels)?.url.pathSegments.last;

    test('the smallest one that is big enough', () {
      expect(pick([art('s', 64), art('l', 480), art('m', 160)], 144), 'm');
      expect(pick([art('s', 64), art('m', 144)], 144), 'm');
    });

    test('all too small: one without a width, then the largest', () {
      expect(pick([art('s', 64), art('o'), art('m', 100)], 144), 'o');
      expect(pick([art('s', 64), art('m', 100)], 144), 'm');
    });

    test('a known big-enough one beats one without a width', () {
      expect(pick([art('o'), art('l', 480)], 144), 'l');
    });

    test('nothing to pick', () => expect(pick([], 144), isNull));
  });

  test('the play count is display data, not part of the track', () {
    const counted = TrackInfo(
      sourceTypeId: 'bilibili',
      sourceId: 'BV1',
      title: 'Song',
      viewCount: 46000000,
    );
    const stored = TrackInfo(
      sourceTypeId: 'bilibili',
      sourceId: 'BV1',
      title: 'Song',
    );

    expect(counted, stored);
    expect(counted.hashCode, stored.hashCode);
    // 變異：別的顯示欄位不同仍然不相等。
    expect(
      counted,
      isNot(
        const TrackInfo(
          sourceTypeId: 'bilibili',
          sourceId: 'BV1',
          title: 'Other',
          viewCount: 46000000,
        ),
      ),
    );
  });
}
