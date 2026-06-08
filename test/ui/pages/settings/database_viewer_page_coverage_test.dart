import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewerPath = 'lib/ui/pages/settings/database_viewer_page.dart';
  const databaseProviderPath = 'lib/providers/database/database_provider.dart';
  const catalogPath = 'lib/providers/database/database_catalog.dart';

  String read(String path) => File(path).readAsStringSync();

  Set<String> schemaNamesFromCatalog(String catalog) {
    return RegExp(r'schema:\s*([A-Za-z0-9_]+)Schema,')
        .allMatches(catalog)
        .map((match) => match.group(1)!)
        .toSet();
  }

  Set<String> collectionNamesFromCatalog(String catalog) {
    return RegExp(r"name:\s*'([^']+)'")
        .allMatches(catalog)
        .map((match) => match.group(1)!)
        .toSet();
  }

  test('database provider opens schemas from the catalog', () {
    final provider = read(databaseProviderPath);

    expect(provider, contains("import 'database_catalog.dart';"));
    expect(
      provider,
      contains(RegExp(r'Isar\.open\(\s*fmpDatabaseSchemas\s*,')),
    );
    expect(
      provider,
      isNot(
          contains('final List<CollectionSchema<dynamic>> fmpDatabaseSchemas')),
    );
    expect(provider, isNot(contains('TrackSchema,')));
    expect(provider, isNot(contains('PlaylistSchema,')));
    expect(provider, isNot(contains('SettingsSchema,')));
  });

  test('database catalog lists every opened Isar collection', () {
    final catalog = read(catalogPath);
    final schemas = schemaNamesFromCatalog(catalog);
    final collections = collectionNamesFromCatalog(catalog);

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

    expect(collections, containsAll(schemas));
    expect(collections.length, schemas.length);
  });

  test('database catalog collection names are unique and Track is default', () {
    final catalog = read(catalogPath);
    final orderedNames = RegExp(r"name:\s*'([^']+)'")
        .allMatches(catalog)
        .map((match) => match.group(1)!)
        .toList();

    expect(orderedNames, isNotEmpty);
    expect(orderedNames.first, 'Track');
    expect(orderedNames.toSet().length, orderedNames.length);
  });

  test('database viewer uses catalog instead of duplicated routing', () {
    final viewer = read(viewerPath);

    expect(viewer, contains('fmpDatabaseCollections'));
    expect(viewer, isNot(contains('final List<String> _collections')));
    expect(viewer, isNot(contains('switch (_selectedCollection')));
    expect(viewer, isNot(contains('class _TrackListView')));
    expect(viewer, isNot(contains('class _SettingsListView')));
  });

  test('database viewer exposes current model fields and debug getters', () {
    final catalog = read(catalogPath);
    const expectedTokens = <String>{
      'bilibiliAid',
      'uniqueKey',
      'groupKey',
      'sourceKey',
      'sourcePageKey',
      'formattedDuration',
      'lyricsDisplayModeIndex',
      'lyricsDisplayMode',
      'allowPlainLyricsAutoMatch',
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
      'homeRankingSourcePriority',
      'homeRankingSourcePriorityList',
      'disabledHomeRankingSources',
      'disabledHomeRankingSourcesSet',
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
      'isNotEmpty',
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
      expect(catalog, contains("'$token'"),
          reason: '$token is not displayed by the database viewer catalog');
    }
  });
}
