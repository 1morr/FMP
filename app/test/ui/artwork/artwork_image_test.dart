import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsFlag;

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/plugin_artwork.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// 1×1 的 PNG。
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

/// 只實作 `CachedNetworkImage` 會叫的 `getFileStream`；回應由 [respond] 決定。
final class _FakeCacheManager implements BaseCacheManager {
  _FakeCacheManager(this.respond);

  final Stream<FileResponse> Function(String url) respond;
  final requested = <String>[];

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    requested.add(url);
    return respond(url);
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 一個已經在快取裡的 PNG。
Stream<FileResponse> _cached(String url) {
  final file = MemoryFileSystem().file('/cover.png')..writeAsBytesSync(_png);
  return Stream.value(
    FileInfo(file, FileSource.Cache, DateTime.utc(2100), url),
  );
}

TrackArtwork _art(String name, int width) =>
    TrackArtwork(url: Uri.parse('https://img.example/$name'), width: width);

void main() {
  /// [manager] 是每個插件拿到的 cache manager；[asked] 記下問了哪些插件。
  Future<void> pump(
    WidgetTester tester, {
    required List<TrackArtwork> artwork,
    required BaseCacheManager? manager,
    List<String>? asked,
    double devicePixelRatio = 1,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artworkCacheManagerProvider.overrideWith((ref, pluginId) {
            asked?.add(pluginId);
            return manager;
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(
            Brightness.light,
            fontFamilyFallback: const [],
            textLocale: const Locale('en'),
          ),
          home: Center(
            child: ArtworkImage(
              pluginId: 'fmp-test',
              artwork: artwork,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }

  Finder placeholder() => find.byIcon(Icons.music_note);

  RawImage? shown(WidgetTester tester) {
    final images = find.byType(RawImage);
    return images.evaluate().isEmpty ? null : tester.widget<RawImage>(images);
  }

  testWidgets("loads the chosen artwork through its plugin's cache manager", (
    tester,
  ) async {
    final manager = _FakeCacheManager(_cached);
    final asked = <String>[];

    await pump(
      tester,
      artwork: [_art('small', 32), _art('fit', 120), _art('large', 640)],
      manager: manager,
      asked: asked,
      devicePixelRatio: 2,
    );
    // 讀檔與解碼是真的非同步工作。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(asked, ['fmp-test']);
    expect(manager.requested, ['https://img.example/fit']);
    expect(shown(tester)?.image, isNotNull);
    expect(placeholder(), findsNothing);
  });

  testWidgets('decodes at the display height', (tester) async {
    await pump(
      tester,
      artwork: [_art('fit', 120)],
      manager: _FakeCacheManager(_cached),
      devicePixelRatio: 2,
    );

    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).height, 96);
    expect(provider.width, isNull);
  });

  testWidgets('shows the placeholder while loading and when loading fails', (
    tester,
  ) async {
    final response = StreamController<FileResponse>();
    addTearDown(response.close);
    await pump(
      tester,
      artwork: [_art('fit', 48)],
      manager: _FakeCacheManager((_) => response.stream),
    );
    expect(placeholder(), findsOneWidget);

    response.addError(Exception('HTTP 404'));
    await tester.pump();
    await tester.pump();

    expect(placeholder(), findsOneWidget);
    expect(shown(tester)?.image, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the placeholder when the plugin has no cache manager', (
    tester,
  ) async {
    // 快取庫還沒開好、開不起來，或插件不在清單上。
    await pump(tester, artwork: [_art('fit', 48)], manager: null);

    expect(placeholder(), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('without artwork it does not ask for a cache manager', (
    tester,
  ) async {
    final manager = _FakeCacheManager(_cached);
    final asked = <String>[];

    await pump(tester, artwork: const [], manager: manager, asked: asked);

    expect(placeholder(), findsOneWidget);
    expect(asked, isEmpty);
    expect(manager.requested, isEmpty);
  });

  testWidgets('the artwork is left out of the semantics tree', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      artwork: [_art('fit', 48)],
      manager: _FakeCacheManager(_cached),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    // 封面是裝飾，曲名在旁邊。
    expect(shown(tester)?.image, isNotNull);
    expect(find.semantics.byFlag(SemanticsFlag.isImage), findsNothing);
    semantics.dispose();
  });
}
