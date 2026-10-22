import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/import/import_summary.dart';

void main() {
  const summary = ImportSummary(
    collections: {
      'tracks': CollectionSummary(
        read: 10,
        written: 8,
        skipped: {'duplicateTrack': 1, 'unreferenced': 1},
      ),
      'playlists': CollectionSummary(read: 2, written: 2),
    },
    unimportedSettings: ['fontFamily'],
    reloginPlatforms: ['netease'],
  );

  test('decodes what it encodes', () {
    expect(ImportSummary.decode(summary.encode()), summary);
  });

  test('equal summaries with maps in another order have the same hash', () {
    const reordered = ImportSummary(
      collections: {
        'playlists': CollectionSummary(read: 2, written: 2),
        'tracks': CollectionSummary(
          read: 10,
          written: 8,
          skipped: {'unreferenced': 1, 'duplicateTrack': 1},
        ),
      },
      unimportedSettings: ['fontFamily'],
      reloginPlatforms: ['netease'],
    );

    expect(reordered, summary);
    expect(reordered.hashCode, summary.hashCode);
  });

  test('a different count is not equal', () {
    const other = ImportSummary(
      collections: {
        'tracks': CollectionSummary(
          read: 10,
          written: 8,
          skipped: {'duplicateTrack': 2, 'unreferenced': 1},
        ),
        'playlists': CollectionSummary(read: 2, written: 2),
      },
      unimportedSettings: ['fontFamily'],
      reloginPlatforms: ['netease'],
    );

    expect(other, isNot(summary));
  });
}
