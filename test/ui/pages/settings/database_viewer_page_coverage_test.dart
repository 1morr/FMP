import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewerPath = 'lib/ui/pages/settings/database_viewer_page.dart';
  const databaseProviderPath = 'lib/providers/database_provider.dart';

  String read(String path) => File(path).readAsStringSync();

  String bracketedBlockAfter(
    String source,
    String anchor,
    String open,
    String close,
  ) {
    final anchorIndex = source.indexOf(anchor);
    if (anchorIndex < 0) {
      fail('Could not find $anchor');
    }

    final start = source.indexOf(open, anchorIndex);
    if (start < 0) {
      fail('Could not find $open after $anchor');
    }

    var depth = 0;
    for (var index = start; index < source.length; index++) {
      final char = source[index];
      if (char == open) {
        depth++;
      } else if (char == close) {
        depth--;
        if (depth == 0) {
          return source.substring(start, index + 1);
        }
      }
    }

    fail('Could not find matching $close after $anchor');
  }

  String isarOpenSchemaList(String provider) {
    return bracketedBlockAfter(provider, 'Isar.open(', '[', ']');
  }

  test('database viewer lists every opened Isar collection', () {
    final provider = read(databaseProviderPath);
    final viewer = read(viewerPath);
    final schemaList = isarOpenSchemaList(provider);
    final collectionsBlock = bracketedBlockAfter(viewer, '_collections =', '[', ']');
    final switchBlock = bracketedBlockAfter(
      viewer,
      'Widget _buildCollectionData(Isar isar)',
      '{',
      '}',
    );
    final schemas = RegExp(r'^\s*([A-Za-z0-9_]+)Schema,', multiLine: true)
        .allMatches(schemaList)
        .map((match) => match.group(1)!)
        .toSet();

    expect(
      schemas,
      containsAll(<String>{
        'Track',
        'Playlist',
        'PlayQueue',
        'Settings',
        'SearchHistory',
        'DownloadTask',
        'PlayHistory',
        'RadioStation',
        'LyricsMatch',
        'LyricsTitleParseCache',
        'Account',
      }),
    );

    for (final collection in schemas) {
      expect(
        collectionsBlock,
        contains("'$collection'"),
        reason: '$collection is missing from _collections',
      );
      expect(
        switchBlock,
        contains("'$collection' => _${collection}ListView(isar: isar)"),
        reason: '$collection is missing from _buildCollectionData',
      );
      expect(
        viewer,
        contains('class _${collection}ListView'),
        reason: '$collection is missing a list view class',
      );
    }
  });

  test('database viewer exposes current model fields and debug getters', () {
    final viewer = read(viewerPath);
    // Intentional hardcoded raw debug field/getter names that the developer
    // database viewer must expose for inspection.
    const expectedTokens = <String>{
      'bilibiliAid',
      'uniqueKey',
      'groupKey',
      'sourceKey',
      'sourcePageKey',
      'formattedDuration',
      'lyricsDisplayModeIndex',
      'lyricsDisplayMode',
      'lyricsSourcePriority',
      'lyricsSourcePriorityList',
      'disabledLyricsSources',
      'disabledLyricsSourcesSet',
      'lyricsAiTitleParsingModeIndex',
      'lyricsAiTitleParsingMode',
      'lyricsAiEndpoint',
      'lyricsAiModel',
      'lyricsAiTimeoutSeconds',
      'rankingRefreshIntervalMinutes',
      'radioRefreshIntervalMinutes',
      'audioFormatPriorityList',
      'youtubeStreamPriorityList',
      'bilibiliStreamPriorityList',
      'neteaseStreamPriorityList',
      'isDownloading',
      'isCompleted',
      'isFailed',
      'isPending',
      'isPaused',
      'isPartOfPlaylist',
      'formattedProgress',
      'trackCount',
      'LyricsTitleParseCache',
      'trackUniqueKey',
      'sourceType',
      'parsedTrackName',
      'parsedArtistName',
      'confidence',
      'createdAt',
      'updatedAt',
      'provider',
      'model',
      'Account',
      'platform',
      'userId',
      'userName',
      'avatarUrl',
      'isLoggedIn',
      'lastRefreshed',
      'loginAt',
      'isVip',
    };

    for (final token in expectedTokens) {
      expect(viewer, contains("'$token'"), reason: '$token is not displayed by the database viewer');
    }
  });
}
