import 'package:flutter_test/flutter_test.dart';
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
}
