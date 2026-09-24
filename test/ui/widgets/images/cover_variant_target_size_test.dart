import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/ui/widgets/images/playlist_cover_image.dart';
import 'package:fmp/ui/widgets/images/radio_cover_image.dart';
import 'package:fmp/ui/widgets/images/recent_play_cover_image.dart';
import 'package:fmp/ui/widgets/images/track_thumbnail.dart';

void main() {
  // 表格列出每一個值：新增 variant 而沒決定它的檔位時，`values` 的比對會紅。
  test('TrackCoverVariant maps to the highest source tier', () {
    expect(
      {
        for (final variant in TrackCoverVariant.values)
          variant: variant.targetDisplaySize,
      },
      {
        // 模糊背景吃的是整個視窗，不是一張卡片；和 hero 同檔還讓同一張封面的
        // 背景與主圖共用一個磁碟快取條目（issue #107）。
        TrackCoverVariant.backdrop: ImageTargetSizes.highest,
        TrackCoverVariant.hero: ImageTargetSizes.highest,
      },
    );
  });

  test('PlaylistCoverVariant maps each scene to its source tier', () {
    expect(
      {
        for (final variant in PlaylistCoverVariant.values)
          variant: variant.targetDisplaySize,
      },
      {
        PlaylistCoverVariant.compact: ImageTargetSizes.medium,
        PlaylistCoverVariant.card: ImageTargetSizes.high,
        PlaylistCoverVariant.hero: ImageTargetSizes.highest,
      },
    );
  });

  test('RadioCoverVariant maps each scene to its source tier', () {
    expect(
      {
        for (final variant in RadioCoverVariant.values)
          variant: variant.targetDisplaySize,
      },
      {
        // 理由同 TrackCoverVariant.backdrop。
        RadioCoverVariant.backdrop: ImageTargetSizes.highest,
        RadioCoverVariant.compact: ImageTargetSizes.thumbnail,
        RadioCoverVariant.card: ImageTargetSizes.medium,
        RadioCoverVariant.hero: ImageTargetSizes.fullscreen,
        // 全螢幕大屏放大顯示，要超過 hero 的來源尺寸。
        RadioCoverVariant.fullscreenHero: ImageTargetSizes.highest,
      },
    );
  });

  testWidgets('RecentPlayCoverImage loads the medium source tier', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 100,
            child: RecentPlayCoverImage(
              networkUrl: 'https://i0.hdslb.com/bfs/archive/cover.jpg',
            ),
          ),
        ),
      ),
    );

    // DPR 1.0 下解碼高度就是目標尺寸本身。
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheHeight, ImageTargetSizes.medium.ceil());
  });
}
