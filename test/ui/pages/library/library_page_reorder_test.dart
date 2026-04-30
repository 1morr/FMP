import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/providers/playlist_provider.dart';
import 'package:fmp/providers/repository_providers.dart';
import 'package:fmp/services/library/playlist_service.dart';
import 'package:fmp/ui/pages/library/library_page.dart';
import 'package:isar/isar.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryPage playlist reorder rollback', () {
    _LibraryPageHarness? cleanupHarness;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {ffi.Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    tearDownAll(() async {
      await cleanupHarness?.disposeResources();
    });

    testWidgets('restores playlist order when reorder persistence fails', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_LibraryPageHarness.create))!;
      cleanupHarness = harness;
      addTearDown(harness.disposeContainer);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(180, 900));
      LocaleSettings.setLocale(AppLocale.en);

      await tester.pumpWidget(
        TranslationProvider(
          child: UncontrolledProviderScope(
            container: harness.container,
            child: const MaterialApp(home: LibraryPage()),
          ),
        ),
      );

      await _pumpUntil(
        tester,
        () => _allPlaylistTitlesPresent(tester),
      );

      expect(_sortButtonIsLeftOfTitle(tester), isTrue);
      expect(_playlistOrder(tester), ['Alpha', 'Bravo', 'Charlie']);

      await tester.tap(find.byIcon(Icons.swap_vert));
      await tester.pump();
      expect(find.byType(ReorderableGridView), findsOneWidget);

      final grid = tester.widget<ReorderableGridView>(
        find.byType(ReorderableGridView),
      );
      grid.onReorder(0, 2);

      await tester.pump();
      expect(
        _playlistOrder(tester),
        ['Bravo', 'Charlie', 'Alpha'],
        reason: 'reorder mode should apply the optimistic local order first',
      );

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(_playlistOrder(tester), ['Alpha', 'Bravo', 'Charlie']);
    });
  });
}

class _FailingReorderPlaylistService extends PlaylistService {
  _FailingReorderPlaylistService({
    required super.playlistRepository,
    required super.trackRepository,
    required super.settingsRepository,
    required super.isar,
  });

  @override
  Future<void> reorderPlaylists(List<Playlist> playlists) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    throw StateError('persist failed');
  }
}

class _StaticPlaylistRepository extends PlaylistRepository {
  _StaticPlaylistRepository(this._playlists, Isar isar) : super(isar);

  final List<Playlist> _playlists;

  @override
  Stream<List<Playlist>> watchAll() {
    return Stream<List<Playlist>>.value(List<Playlist>.from(_playlists));
  }
}

class _LibraryPageHarness {
  _LibraryPageHarness({
    required this.container,
    required this.isar,
    required this.tempDir,
  });

  final ProviderContainer container;
  final Isar isar;
  final Directory tempDir;

  static Future<_LibraryPageHarness> create() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'library_page_reorder_test_',
    );
    final isar = await Isar.open(
      [TrackSchema, PlaylistSchema, PlayQueueSchema, SettingsSchema],
      directory: tempDir.path,
      name: 'library_page_reorder_test',
    );

    final playlists = [
      _buildPlaylist('Alpha', 0),
      _buildPlaylist('Bravo', 1),
      _buildPlaylist('Charlie', 2),
    ];

    await isar.writeTxn(() async {
      await isar.playlists.putAll(playlists);
    });

    final playlistRepository = _StaticPlaylistRepository(playlists, isar);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => isar),
        playlistRepositoryProvider.overrideWith((ref) => playlistRepository),
        playlistServiceProvider.overrideWith(
          (ref) => _FailingReorderPlaylistService(
            playlistRepository: ref.read(playlistRepositoryProvider),
            trackRepository: ref.read(trackRepositoryProvider),
            settingsRepository: ref.read(settingsRepositoryProvider),
            isar: isar,
          ),
        ),
        playlistCoverProvider.overrideWith(
          (ref, playlistId) => const PlaylistCoverData(),
        ),
      ],
    );

    return _LibraryPageHarness(
      container: container,
      isar: isar,
      tempDir: tempDir,
    );
  }

  void disposeContainer() {
    container.dispose();
  }

  Future<void> disposeResources() async {
    if (isar.isOpen) {
      await isar.close(deleteFromDisk: true);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> dispose() async {
    container.dispose();
    await disposeResources();
  }
}

Playlist _buildPlaylist(String name, int sortOrder) {
  return Playlist()
    ..name = name
    ..sortOrder = sortOrder
    ..createdAt = DateTime(2026);
}

List<String> _playlistOrder(WidgetTester tester) {
  final names = ['Alpha', 'Bravo', 'Charlie'];
  final positions = <String, double>{
    for (final name in names) name: tester.getTopLeft(find.text(name)).dy,
  };
  final ordered = positions.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  return ordered.map((entry) => entry.key).toList();
}

bool _sortButtonIsLeftOfTitle(WidgetTester tester) {
  final sortButtonRight = tester
      .getTopRight(find.byIcon(Icons.swap_vert))
      .dx;
  final titleLeft = tester.getTopLeft(find.text(t.library.title)).dx;
  return sortButtonRight <= titleLeft;
}

bool _allPlaylistTitlesPresent(WidgetTester tester) {
  return ['Alpha', 'Bravo', 'Charlie'].every(
    (name) => find.text(name).evaluate().isNotEmpty,
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 125,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) {
      return;
    }
  }

  expect(condition(), isTrue, reason: 'Timed out waiting for test condition');
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packageConfig =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
