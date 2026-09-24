import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/image_loading_service.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

/// 1×1 透明 PNG。
final _pngBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _bilibiliCover = 'https://i0.hdslb.com/bfs/archive/cover.jpg';
const _youtubeCover = 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg';
const _neteaseCover = 'https://p1.music.126.net/abc/123.jpg';

/// 目標尺寸刻意不是整數倍，`ceil` 的方向才看得出來。
const _targetDisplaySize = 100.5;
const _devicePixelRatio = 2.0;
const _expectedCacheExtent = 201; // ceil(100.5 × 2.0)

void _useDevicePixelRatio(WidgetTester tester) {
  tester.view.devicePixelRatio = _devicePixelRatio;
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

Future<void> _pumpImage(WidgetTester tester, Widget image) {
  return tester.pumpWidget(
    MaterialApp(
      home: Center(child: SizedBox(width: 64, height: 64, child: image)),
    ),
  );
}

CachedNetworkImage _networkImage(WidgetTester tester) =>
    tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));

void main() {
  group('ImageLoadingService.imageProviderCandidates', () {
    testWidgets('scales every candidate by height only (#107)', (tester) async {
      _useDevicePixelRatio(tester);
      final dir = Directory.systemTemp.createTempSync('fmp_image_candidates');
      addTearDown(() => dir.deleteSync(recursive: true));
      final localPath = '${dir.path}/cover.jpg';
      final context = await _pumpContext(tester);

      final candidates = ImageLoadingService.imageProviderCandidates(
        context: context,
        localPath: localPath,
        networkUrl: _bilibiliCover,
        // 版面寬高刻意給成非方形：它們只管版面，不能流進解碼或磁碟縮放。
        width: 640,
        height: 360,
        targetDisplaySize: _targetDisplaySize,
      );

      // 同時給寬高時，預設的 exact 策略會把 16:9 封面壓成正方形，磁碟縮放則
      // 按寬把它縮到不夠高 —— 只給高度兩邊都保長寬比（issue #107）。
      final local = candidates.first as ResizeImage;
      expect((local.imageProvider as FileImage).file.path, localPath);
      expect(local.height, _expectedCacheExtent);
      expect(local.width, isNull);

      final network = candidates.skip(1).cast<CachedNetworkImageProvider>();
      expect(network, isNotEmpty);
      for (final provider in network) {
        expect(provider.maxHeight, _expectedCacheExtent, reason: provider.url);
        expect(provider.maxWidth, isNull, reason: provider.url);
      }
    });
  });

  group('ImageLoadingService.loadImage network path', () {
    testWidgets('bounds the memory cache by height only (#107)', (
      tester,
    ) async {
      _useDevicePixelRatio(tester);
      await _pumpImage(
        tester,
        ImageLoadingService.loadImage(
          networkUrl: _bilibiliCover,
          placeholder: const SizedBox(),
          width: 64,
          height: 64,
          targetDisplaySize: _targetDisplaySize,
        ),
      );

      final image = _networkImage(tester);
      expect(image.memCacheHeight, _expectedCacheExtent);
      expect(image.memCacheWidth, isNull);
    });

    testWidgets('re-applies the decode bound to the provider it is handed', (
      tester,
    ) async {
      _useDevicePixelRatio(tester);
      await _pumpImage(
        tester,
        ImageLoadingService.loadImage(
          networkUrl: _bilibiliCover,
          placeholder: const SizedBox(),
          targetDisplaySize: _targetDisplaySize,
        ),
      );

      // `CachedNetworkImage` 交給 imageBuilder 的是**未經 resize** 的
      // provider；imageBuilder 不自己包回去，memCacheHeight 對畫面上的圖
      // 就完全無效。
      final loaded = MemoryImage(_pngBytes);
      final built =
          _networkImage(tester).imageBuilder!(
                tester.element(find.byType(CachedNetworkImage)),
                loaded,
              )
              as Image;

      final resized = built.image as ResizeImage;
      expect(resized.imageProvider, same(loaded));
      expect(resized.height, _expectedCacheExtent);
      expect(resized.width, isNull);
    });

    for (final url in [_bilibiliCover, _youtubeCover, _neteaseCover]) {
      testWidgets('requests $url with the shared image header policy', (
        tester,
      ) async {
        await _pumpImage(
          tester,
          ImageLoadingService.loadImage(
            networkUrl: url,
            placeholder: const SizedBox(),
            targetDisplaySize: _targetDisplaySize,
          ),
        );

        final expected = SourceHttpPolicy.imageHeadersForUrl(url);
        expect(expected, isNotNull);
        expect(_networkImage(tester).httpHeaders, expected);
      });
    }

    testWidgets('lets caller headers replace the policy headers', (
      tester,
    ) async {
      const headers = {'Referer': 'https://live.example.test/'};
      await _pumpImage(
        tester,
        ImageLoadingService.loadImage(
          networkUrl: _bilibiliCover,
          placeholder: const SizedBox(),
          targetDisplaySize: _targetDisplaySize,
          headers: headers,
        ),
      );

      expect(_networkImage(tester).httpHeaders, headers);
    });
  });

  group('ImageLoadingService.loadImage local path', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fmp_image_local');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Widget local(String path, {String? networkUrl}) =>
        ImageLoadingService.loadImage(
          localPath: path,
          networkUrl: networkUrl,
          placeholder: const SizedBox(key: Key('placeholder')),
          targetDisplaySize: _targetDisplaySize,
          fadeInDuration: Duration.zero,
        );

    /// 在測試區外先把本機封面解碼進 ImageCache。
    ///
    /// 在 fake async 區裡開始的真 I/O 只有 `tester.pump` 才推得動，在
    /// `runAsync` 裡等它會卡死；先在真事件迴圈裡載好，widget 解析時就是
    /// 同步的快取命中。`precacheImageCandidates` 和 `loadImage` 建出同一個
    /// provider key，所以快取的正是 widget 要的那一個。
    Future<void> decodeAhead(WidgetTester tester, String path) async {
      await _pumpImage(tester, const SizedBox());
      final context = tester.element(find.byType(Center));
      final loaded = await tester.runAsync(
        () => ImageLoadingService.precacheImageCandidates(
          context: context,
          localPath: path,
          targetDisplaySize: _targetDisplaySize,
        ),
      );
      expect(loaded, isNotNull, reason: 'the test cover must decode');
    }

    Finder localImage(String path) => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is ResizeImage &&
          ((widget.image as ResizeImage).imageProvider as FileImage)
                  .file
                  .path ==
              path,
    );

    testWidgets('decodes local covers by height only', (tester) async {
      _useDevicePixelRatio(tester);
      final path = '${dir.path}/cover.png';
      File(path).writeAsBytesSync(_pngBytes);
      await decodeAhead(tester, path);

      await _pumpImage(tester, local(path));

      final resized =
          tester.widget<Image>(localImage(path)).image as ResizeImage;
      expect(resized.height, _expectedCacheExtent);
      expect(resized.width, isNull);
    });

    testWidgets('shows the new cover after a failed one is replaced', (
      tester,
    ) async {
      final missing = '${dir.path}/missing.png';
      final present = '${dir.path}/present.png';
      File(present).writeAsBytesSync(_pngBytes);
      await decodeAhead(tester, present);

      // 本機檔讀不到時退到網路圖；CachedNetworkImage 出現就代表已經進了
      // 錯誤分支，和「還在載入」的佔位符分得開。
      await _pumpImage(tester, local(missing, networkUrl: _bilibiliCover));
      await _pumpFramesUntil(
        tester,
        () => find.byType(CachedNetworkImage).evaluate().isNotEmpty,
        reason: 'the missing local cover to fall back to the network',
      );

      // 同一個位置換 provider：失敗狀態必須清掉，並對新 provider 重新訂閱，
      // 否則錯誤分支會一直留著。
      await _pumpImage(tester, local(present, networkUrl: _bilibiliCover));

      expect(localImage(present), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  });
}

/// 讓 fake async 區裡開始的真 I/O 前進，直到 [condition] 成立。
///
/// `pumpUntil` 推不動 widget 樹：這裡每一輪先在真事件迴圈裡讓出一小段，讓
/// I/O 回來，再用 `tester.pump` 把排進 fake 區的接續和重建跑掉。期限是牆鐘
/// 時間，不是輪數。
Future<void> _pumpFramesUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('timed out after $timeout waiting: $reason');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}
