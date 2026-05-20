import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UI consistency static rules', () {
    test('cover picker grid items expose and receive stable keys', () {
      final source = File(
        'lib/ui/pages/library/widgets/cover_picker_dialog.dart',
      ).readAsStringSync();

      expect(
        RegExp(r'const\s+_CoverGridItem\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(source),
        isTrue,
      );
      expect(
        source.contains('key: ValueKey(track.thumbnailUrl),'),
        isTrue,
      );
    });

    test('import preview alternative rows expose and receive stable keys', () {
      final source = File(
        'lib/ui/pages/library/import_preview_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(r'const\s+_AlternativeTrackTile\s*\(\s*\{\s*super\.key,',
                dotAll: true)
            .hasMatch(source),
        isTrue,
      );
      expect(
        RegExp(
          r"ValueKey\(\s*'alternative-search-\$\{result\.sourceType\.name\}:\$\{result\.sourceId\}:\$\{result\.pageNum\s*\?\?\s*result\.cid\s*\?\?\s*0\}'\s*\)",
          dotAll: true,
        ).hasMatch(source),
        isTrue,
      );
      expect(
        RegExp(
          r"ValueKey\(\s*'alternative-expanded-\$\{altTrack\.sourceType\.name\}:\$\{altTrack\.sourceId\}:\$\{altTrack\.pageNum\s*\?\?\s*altTrack\.cid\s*\?\?\s*0\}'\s*\)",
          dotAll: true,
        ).hasMatch(source),
        isTrue,
      );
    });

    test('known fixed-size image loads pass display-size hints', () {
      final home = File('lib/ui/pages/home/home_page.dart').readAsStringSync();
      final downloaded =
          File('lib/ui/pages/library/downloaded_page.dart').readAsStringSync();
      final downloadedCategory = File(
        'lib/ui/pages/library/downloaded_category_page.dart',
      ).readAsStringSync();
      final coverPicker = File(
        'lib/ui/pages/library/widgets/cover_picker_dialog.dart',
      ).readAsStringSync();
      final trackThumbnail =
          File('lib/ui/widgets/track_thumbnail.dart').readAsStringSync();

      expect(home.contains('targetDisplaySize: 160'), isTrue);
      expect(downloaded.contains('targetDisplaySize: 160'), isTrue);
      expect(downloadedCategory.contains('targetDisplaySize: 240'), isTrue);
      expect(coverPicker.contains('targetDisplaySize: 320'), isTrue);
      expect(
        trackThumbnail
            .contains('targetDisplaySize: highResolution ? 480.0 : 320.0'),
        isTrue,
      );
    });

    test('download path unset text does not use error color', () {
      final source =
          File('lib/ui/pages/settings/settings_page.dart').readAsStringSync();

      final downloadPathTile = RegExp(
        r'class _DownloadPathListTile extends ConsumerWidget \{(?<body>.*?)^///',
        multiLine: true,
        dotAll: true,
      ).firstMatch(source)?.namedGroup('body');

      expect(downloadPathTile, isNotNull);
      expect(downloadPathTile, isNot(contains('colorScheme.error')));
      expect(
        downloadPathTile,
        isNot(contains('Theme.of(context).colorScheme.error')),
      );
    });
  });
}
