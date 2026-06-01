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

    test('known image loads use named display-size targets', () {
      final home = File('lib/ui/pages/home/home_page.dart').readAsStringSync();
      final downloaded =
          File('lib/ui/pages/library/downloaded_page.dart').readAsStringSync();
      final downloadedCategory = File(
        'lib/ui/pages/library/downloaded_category_page.dart',
      ).readAsStringSync();
      final coverPicker = File(
        'lib/ui/pages/library/widgets/cover_picker_dialog.dart',
      ).readAsStringSync();
      final createPlaylist = File(
        'lib/ui/pages/library/widgets/create_playlist_dialog.dart',
      ).readAsStringSync();
      final library = File(
        'lib/ui/pages/library/library_page.dart',
      ).readAsStringSync();
      final playlistDetail = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();
      final radioPage =
          File('lib/ui/pages/radio/radio_page.dart').readAsStringSync();
      final trackThumbnail =
          File('lib/ui/widgets/images/track_thumbnail.dart').readAsStringSync();
      final recentPlayCover =
          File('lib/ui/widgets/images/recent_play_cover_image.dart')
              .readAsStringSync();
      final playlistCover =
          File('lib/ui/widgets/images/playlist_cover_image.dart')
              .readAsStringSync();
      final radioCover = File('lib/ui/widgets/images/radio_cover_image.dart')
          .readAsStringSync();
      final imageService = File('lib/core/services/image_loading_service.dart')
          .readAsStringSync();
      final radioMiniPlayer =
          File('lib/ui/widgets/radio/radio_mini_player.dart')
              .readAsStringSync();
      final radioPlayer =
          File('lib/ui/pages/radio/radio_player_page.dart').readAsStringSync();
      final playerPage =
          File('lib/ui/pages/player/player_page.dart').readAsStringSync();
      final trackDetailPanel =
          File('lib/ui/widgets/panels/track_detail_panel.dart').readAsStringSync();
      final searchPage =
          File('lib/ui/pages/search/search_page.dart').readAsStringSync();
      final addToPlaylist = File(
        'lib/ui/widgets/dialogs/add_to_playlist_dialog.dart',
      ).readAsStringSync();
      final remotePlaylist = File(
        'lib/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart',
      ).readAsStringSync();
      final accountPlaylists = File(
        'lib/ui/pages/settings/widgets/account_playlists_sheet.dart',
      ).readAsStringSync();

      expect(
        home,
        contains('RecentPlayCoverImage('),
      );
      expect(
        home,
        contains('variant: PlaylistCoverVariant.card'),
      );
      expect(
        home,
        contains('variant: RadioCoverVariant.card'),
      );
      expect(
        downloaded,
        contains('variant: PlaylistCoverVariant.card'),
      );
      expect(
        downloadedCategory,
        contains('variant: PlaylistCoverVariant.card'),
      );
      expect(
        coverPicker,
        contains('variant: PlaylistCoverVariant.compact'),
      );
      expect(
        createPlaylist,
        contains('variant: PlaylistCoverVariant.compact'),
      );
      expect(
        library,
        contains('variant: PlaylistCoverVariant.card'),
      );
      expect(
        playlistDetail,
        contains('variant: PlaylistCoverVariant.hero'),
      );
      expect(
        playlistDetail,
        contains('variant: PlaylistCoverVariant.compact'),
      );
      expect(
        radioPage,
        contains('variant: RadioCoverVariant.card'),
      );
      expect(
        radioPlayer,
        contains('variant: RadioCoverVariant.hero'),
      );
      expect(
        radioMiniPlayer,
        contains('variant: RadioCoverVariant.compact'),
      );
      expect(
        playerPage,
        contains('variant: TrackCoverVariant.hero'),
      );
      expect(
        trackDetailPanel,
        contains('variant: TrackCoverVariant.hero'),
      );
      expect(
        searchPage,
        contains('variant: RadioCoverVariant.compact'),
      );
      expect(
        addToPlaylist,
        contains('variant: PlaylistCoverVariant.compact'),
      );
      expect(
        remotePlaylist,
        contains('variant: PlaylistCoverVariant.compact'),
      );
      expect(
        accountPlaylists,
        contains('variant: PlaylistCoverVariant.compact'),
      );
      expect(
        recentPlayCover,
        contains('class RecentPlayCoverImage'),
      );
      expect(
        recentPlayCover,
        contains('targetDisplaySize: ImageTargetSizes.high'),
      );
      expect(
        recentPlayCover,
        isNot(contains('RecentPlayCoverVariant')),
      );
      expect(
        playlistCover,
        contains('return ImageTargetSizes.medium;'),
      );
      expect(
        playlistCover,
        contains('return ImageTargetSizes.high;'),
      );
      expect(
        playlistCover,
        contains('return ImageTargetSizes.highest;'),
      );
      expect(
        radioCover,
        contains('return ImageTargetSizes.medium;'),
      );
      expect(
        radioCover,
        contains('return ImageTargetSizes.high;'),
      );
      expect(
        radioCover,
        contains('return ImageTargetSizes.highest;'),
      );
      expect(trackThumbnail, isNot(contains('TrackCoverQuality')));
      expect(trackThumbnail, contains('enum TrackCoverVariant'));
      expect(trackThumbnail, isNot(contains('TrackCoverVariant.compact')));
      expect(trackThumbnail, contains('return ImageTargetSizes.medium;'));
      expect(trackThumbnail, contains('return ImageTargetSizes.highest;'));
      expect(
          trackThumbnail, isNot(contains('required this.targetDisplaySize')));
      expect(
        trackThumbnail,
        contains('targetDisplaySize: ImageTargetSizes.medium'),
      );
      expect(
        trackThumbnail,
        contains('targetDisplaySize: variant.targetDisplaySize'),
      );
      expect(
        imageService.contains('targetDisplaySize: targetDisplaySize'),
        isTrue,
      );
    });

    test('avatar images use the shared AvatarImage widget', () {
      final avatarWidget = File('lib/ui/widgets/images/avatar_image.dart');
      expect(avatarWidget.existsSync(), isTrue);
      final avatarSource = avatarWidget.readAsStringSync();

      expect(
          avatarSource, contains('class AvatarImage extends StatelessWidget'));
      expect(avatarSource, contains('ImageLoadingService.loadAvatar('));
      expect(
        avatarSource,
        contains('targetDisplaySize: ImageTargetSizes.low'),
      );

      final directAvatarCalls = <String>[];
      final lowTargetsOutsideAvatar = <String>[];
      final files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (normalizedPath.endsWith('/images/avatar_image.dart')) continue;

        final source = file.readAsStringSync();
        if (source.contains('ImageLoadingService.loadAvatar(')) {
          directAvatarCalls.add(file.path);
        }
        if (source.contains('targetDisplaySize: ImageTargetSizes.low')) {
          lowTargetsOutsideAvatar.add(file.path);
        }
      }

      expect(directAvatarCalls, isEmpty);
      expect(lowTargetsOutsideAvatar, isEmpty);
    });

    test('playlist and radio covers use shared semantic image widgets', () {
      final playlistWidget =
          File('lib/ui/widgets/images/playlist_cover_image.dart');
      final radioWidget = File('lib/ui/widgets/images/radio_cover_image.dart');
      expect(playlistWidget.existsSync(), isTrue);
      expect(radioWidget.existsSync(), isTrue);

      final playlistSource = playlistWidget.readAsStringSync();
      final radioSource = radioWidget.readAsStringSync();

      expect(playlistSource, contains('class PlaylistCoverImage'));
      expect(playlistSource, contains('enum PlaylistCoverVariant'));
      expect(
        playlistSource,
        contains('targetDisplaySize: variant.targetDisplaySize'),
      );
      expect(radioSource, contains('class RadioCoverImage'));
      expect(radioSource, contains('enum RadioCoverVariant'));
      expect(
        radioSource,
        contains('targetDisplaySize: variant.targetDisplaySize'),
      );

      final allowedDirectLoadImage = <String>{
        'lib/ui/widgets/images/playlist_cover_image.dart',
        'lib/ui/widgets/images/radio_cover_image.dart',
        'lib/ui/widgets/images/recent_play_cover_image.dart',
        'lib/ui/widgets/images/track_thumbnail.dart',
      };
      final directLoadImage = <String>[];
      final files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (allowedDirectLoadImage.contains(normalizedPath)) continue;
        final source = file.readAsStringSync();
        if (source.contains('ImageLoadingService.loadImage(')) {
          directLoadImage.add(normalizedPath);
        }
      }

      expect(directLoadImage, isEmpty);

      final expectedPlaylistUsers = <String>[
        'lib/ui/pages/home/home_page.dart',
        'lib/ui/pages/library/downloaded_page.dart',
        'lib/ui/pages/library/downloaded_category_page.dart',
        'lib/ui/pages/library/library_page.dart',
        'lib/ui/pages/library/playlist_detail_page.dart',
        'lib/ui/pages/library/widgets/create_playlist_dialog.dart',
        'lib/ui/pages/library/widgets/cover_picker_dialog.dart',
        'lib/ui/widgets/dialogs/add_to_playlist_dialog.dart',
        'lib/ui/widgets/dialogs/remote_playlist_dialog_widgets.dart',
        'lib/ui/pages/settings/widgets/account_playlists_sheet.dart',
      ];

      for (final path in expectedPlaylistUsers) {
        final source = File(path).readAsStringSync();
        expect(source, contains('PlaylistCoverImage('), reason: path);
      }

      final expectedRadioUsers = <String>[
        'lib/ui/pages/home/home_page.dart',
        'lib/ui/pages/radio/radio_page.dart',
        'lib/ui/pages/radio/radio_player_page.dart',
        'lib/ui/pages/search/search_page.dart',
        'lib/ui/widgets/radio/radio_mini_player.dart',
        'lib/ui/widgets/panels/track_detail_panel.dart',
      ];

      for (final path in expectedRadioUsers) {
        final source = File(path).readAsStringSync();
        expect(source, contains('RadioCoverImage('), reason: path);
      }
    });

    test('semantic image widgets live under widgets/images', () {
      final imageWidgetPaths = <String>[
        'lib/ui/widgets/images/avatar_image.dart',
        'lib/ui/widgets/images/playlist_cover_image.dart',
        'lib/ui/widgets/images/radio_cover_image.dart',
        'lib/ui/widgets/images/recent_play_cover_image.dart',
        'lib/ui/widgets/images/track_thumbnail.dart',
      ];

      for (final path in imageWidgetPaths) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }

      final rootImageWidgetPaths = <String>[
        'lib/ui/widgets/avatar_image.dart',
        'lib/ui/widgets/playlist_cover_image.dart',
        'lib/ui/widgets/radio_cover_image.dart',
        'lib/ui/widgets/recent_play_cover_image.dart',
        'lib/ui/widgets/track_thumbnail.dart',
      ];

      for (final path in rootImageWidgetPaths) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
    });

    test('shared widgets live under semantic subdirectories', () {
      final rootWidgetFiles = Directory('lib/ui/widgets')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      expect(rootWidgetFiles, isEmpty);

      final expectedDirectories = <String>[
        'lib/ui/widgets/app_bars',
        'lib/ui/widgets/controls',
        'lib/ui/widgets/dialogs',
        'lib/ui/widgets/feedback',
        'lib/ui/widgets/images',
        'lib/ui/widgets/indicators',
        'lib/ui/widgets/layout',
        'lib/ui/widgets/lyrics',
        'lib/ui/widgets/menus',
        'lib/ui/widgets/panels',
        'lib/ui/widgets/player',
        'lib/ui/widgets/radio',
        'lib/ui/widgets/track_group',
      ];

      for (final path in expectedDirectories) {
        expect(Directory(path).existsSync(), isTrue, reason: path);
      }
    });

    test('semantic image helpers are the only UI ImageLoadingService callers',
        () {
      final allowedCallers = <String>{
        'lib/ui/widgets/images/avatar_image.dart',
        'lib/ui/widgets/images/playlist_cover_image.dart',
        'lib/ui/widgets/images/radio_cover_image.dart',
        'lib/ui/widgets/images/recent_play_cover_image.dart',
        'lib/ui/widgets/images/track_thumbnail.dart',
      };
      final directCallers = <String>[];
      final files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (allowedCallers.contains(normalizedPath)) continue;

        final source = file.readAsStringSync();
        final hasDirectCall = source
                .contains('ImageLoadingService.loadImage(') ||
            source.contains('ImageLoadingService.loadAvatar(') ||
            source.contains('ImageLoadingService.imageProviderCandidates(') ||
            source.contains('ImageLoadingService.precacheImageCandidates(');

        if (hasDirectCall) directCallers.add(normalizedPath);
      }

      expect(directCallers, isEmpty);
    });

    test(
        'image loading applies decode-size hints to local and target-sized images',
        () {
      final source = File(
        'lib/core/services/image_loading_service.dart',
      ).readAsStringSync();
      final thumbnailUtils = File(
        'lib/core/utils/thumbnail_url_utils.dart',
      ).readAsStringSync();

      expect(source, contains('ResizeImage('));
      expect(source, contains('MediaQuery.devicePixelRatioOf(context)'));
      expect(source, isNot(contains('_urlCandidateDevicePixelRatio')));
      expect(source, contains('_networkImageCacheKey'));
      expect(source, contains('cacheExtent: memCacheExtent'));
      expect(source, contains('final cacheExtent = _cacheExtent('));
      expect(source, contains('maxWidth: cacheExtent'));
      expect(source, contains('maxHeight: cacheExtent'));
      expect(source, contains('targetDisplaySize: targetDisplaySize'));
      expect(thumbnailUtils, isNot(contains('devicePixelRatio')));
      expect(
        source,
        isNot(contains('targetDisplaySize ?? width')),
      );
      expect(
        source,
        isNot(contains('targetDisplaySize ?? height')),
      );
      expect(
        source,
        isNot(contains('widget.targetDisplaySize ?? widget.width')),
      );
      expect(
        source,
        isNot(contains('widget.targetDisplaySize ?? widget.height')),
      );
      expect(
        source,
        contains('required double targetDisplaySize'),
      );
    });

    test('UI image-loading calls pass explicit targetDisplaySize', () {
      final files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final missingTargets = <String>[];

      for (final file in files) {
        final source = file.readAsStringSync();
        var searchFrom = 0;
        while (true) {
          final callStarts = [
            source.indexOf('ImageLoadingService.loadImage(', searchFrom),
            source.indexOf('ImageLoadingService.loadAvatar(', searchFrom),
            source.indexOf(
              'ImageLoadingService.imageProviderCandidates(',
              searchFrom,
            ),
            source.indexOf(
              'ImageLoadingService.precacheImageCandidates(',
              searchFrom,
            ),
          ].where((index) => index >= 0).toList()
            ..sort();
          if (callStarts.isEmpty) break;

          final callStart = callStarts.first;
          if (callStart < 0) break;

          var depth = 0;
          var callEnd = callStart;
          for (var i = callStart; i < source.length; i++) {
            final char = source[i];
            if (char == '(') depth++;
            if (char == ')') {
              depth--;
              if (depth == 0) {
                callEnd = i;
                break;
              }
            }
          }

          final call = source.substring(callStart, callEnd + 1);
          if (!call.contains('targetDisplaySize:')) {
            final line =
                '\n'.allMatches(source.substring(0, callStart)).length + 1;
            missingTargets.add('${file.path}:$line');
          }
          searchFrom = callEnd + 1;
        }
      }

      expect(missingTargets, isEmpty);
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

    test('queue page reads queue display state from queue providers', () {
      final source =
          File('lib/ui/pages/queue/queue_page.dart').readAsStringSync();

      expect(source, contains('queueStateProvider'));
      expect(
        source,
        isNot(contains('audioControllerProvider.select((s) => s.queue)')),
      );
      expect(
        source,
        isNot(
            contains('audioControllerProvider.select((s) => s.currentIndex)')),
      );
      expect(
        source,
        isNot(
            contains('audioControllerProvider.select((s) => s.queueVersion)')),
      );
    });

    test('home ranking section exposes lightweight loading fallback', () {
      final source =
          File('lib/ui/pages/home/home_page.dart').readAsStringSync();

      expect(source, contains('class HomeRankingsSection'));
      expect(source, contains('CircularProgressIndicator'));
      expect(source, isNot(contains('ForTest')));
    });

    test('search, playlist, and downloaded dynamic rows use stable keys', () {
      final search =
          File('lib/ui/pages/search/search_page.dart').readAsStringSync();
      final playlistDetail = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();
      final downloadedCategory = File(
        'lib/ui/pages/library/downloaded_category_page.dart',
      ).readAsStringSync();

      expect(search, contains("ValueKey('local-group-\${group.groupKey}')"));
      expect(search, contains("ValueKey('live-room-\${room.roomId}')"));
      expect(
        search,
        contains(
            "'page-\${track.sourceType.name}:\${track.sourceId}:\${page.page}'"),
      );
      expect(
        playlistDetail,
        contains("ValueKey('playlist-group-\${group.groupKey}')"),
      );
      expect(
        downloadedCategory,
        contains("ValueKey('downloaded-track-\${_downloadedTrackKey("),
      );
      expect(
        downloadedCategory,
        contains("ValueKey('downloaded-group-\${group.groupKey}')"),
      );
    });

    test('search multi-page rows expose common single track actions', () {
      final source =
          File('lib/ui/pages/search/search_page.dart').readAsStringSync();

      final pageTileBody = _classBody(source, '_PageTile');

      expect(pageTileBody, isNotNull);
      expect(pageTileBody, isNot(contains('includeAddToPlaylist: false')));
      expect(pageTileBody, isNot(contains('includeMatchLyrics: false')));
      expect(pageTileBody, isNot(contains('includeAddToRemote: false')));
      expect(source, contains('TrackActionCoordinator.handleSingle'));
    });

    test('search results cache mixed online tracks per build', () {
      final source =
          File('lib/ui/pages/search/search_page.dart').readAsStringSync();
      final buildResultsBody = _methodBody(source, '_buildSearchResults');

      expect(buildResultsBody, contains('final mixedOnlineTracks ='));
      expect(
        buildResultsBody,
        isNot(contains('state.mixedOnlineTracks[index]')),
      );
      expect(
        buildResultsBody,
        isNot(contains('state.mixedOnlineTracks.length')),
      );
    });

    test('download manager rows expose stable keys', () {
      final source = File(
        'lib/ui/pages/settings/download_manager_page.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('download-section-\${row.title}')"));
      expect(source, contains("ValueKey('download-task-\${row.task!.id}')"));
      expect(
        source,
        contains("ValueKey('download-active-task-\${tasks[index].id}')"),
      );
      expect(source, contains("ValueKey('download-empty-slot-\$index')"));
    });

    test('radio UI watches only audio device and volume fields', () {
      final miniPlayer = File(
        'lib/ui/widgets/radio/radio_mini_player.dart',
      ).readAsStringSync();
      final playerPage = File(
        'lib/ui/pages/radio/radio_player_page.dart',
      ).readAsStringSync();

      for (final source in [miniPlayer, playerPage]) {
        expect(source, isNot(contains('ref.watch(audioControllerProvider);')));
        expect(
          source,
          contains('audioControllerProvider.select((state) => state.volume)'),
        );
        expect(
          source,
          contains(
              'audioControllerProvider.select((state) => state.audioDevices)'),
        );
        expect(
          source,
          contains(
              'audioControllerProvider.select((state) => state.currentAudioDevice)'),
        );
      }
    });

    test('search and playlist pages avoid page-wide selection watches', () {
      final search =
          File('lib/ui/pages/search/search_page.dart').readAsStringSync();
      final playlistDetail = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();

      expect(search, isNot(contains('ref.watch(searchSelectionProvider);')));
      expect(
        search,
        contains('isSelected: state.isSelected(track)'),
      );
      expect(
        search,
        contains(
            'searchSelectionProvider.select((state) => state.isSelectionMode)'),
      );

      expect(
        playlistDetail,
        isNot(contains('ref.watch(playlistDetailSelectionProvider);')),
      );
      expect(
        playlistDetail,
        contains('isSelected: state.isSelected(track)'),
      );
      expect(
        playlistDetail,
        contains(
            'playlistDetailSelectionProvider.select((state) => state.isSelectionMode)'),
      );
    });

    test('silent async UI failures surface errors to users', () {
      final search =
          File('lib/ui/pages/search/search_page.dart').readAsStringSync();
      final downloadPathDialog =
          File('lib/ui/widgets/dialogs/download_path_setup_dialog.dart')
              .readAsStringSync();
      final bilibiliLogin =
          File('lib/ui/pages/settings/bilibili_login_page.dart')
              .readAsStringSync();
      final lyricsSearch = File('lib/ui/pages/lyrics/lyrics_search_sheet.dart')
          .readAsStringSync();

      expect(_methodBody(search, '_loadVideoPages'),
          contains('ToastService.error'));
      expect(_methodBody(downloadPathDialog, '_selectPath'),
          contains('ToastService.error'));
      expect(_methodBody(bilibiliLogin, '_onPageLoaded'),
          contains('ToastService.error'));
      expect(_methodBody(bilibiliLogin, '_startPolling'), contains('onError'));
      expect(_methodBody(lyricsSearch, '_selectResult'), contains('_isSaving'));
      expect(_methodBody(lyricsSearch, '_removeMatch'),
          contains('ToastService.error'));
    });
  });
}

String _classBody(String source, String className) {
  final declaration = RegExp(
    r'class\s+' + RegExp.escape(className) + r'\s+extends\s+[^{]+\{',
  ).firstMatch(source);
  if (declaration == null) {
    throw StateError('Class $className not found');
  }

  final openBrace = source.indexOf('{', declaration.start);
  if (openBrace == -1) {
    throw StateError('Class $className has no body');
  }

  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) {
      return source.substring(openBrace, i + 1);
    }
  }

  throw StateError('Class body did not close');
}

String _methodBody(String source, String methodName) {
  final declaration = RegExp(
    r'(?:Future<[^>]+>|void|Widget)\s+' + RegExp.escape(methodName) + r'\s*\(',
  ).firstMatch(source);
  if (declaration == null) {
    throw StateError('Method $methodName not found');
  }

  final openBrace = source.indexOf('{', declaration.start);
  if (openBrace == -1) {
    throw StateError('Method $methodName has no body');
  }

  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') depth--;
    if (depth == 0) {
      return source.substring(openBrace, i + 1);
    }
  }

  throw StateError('Body did not close');
}
