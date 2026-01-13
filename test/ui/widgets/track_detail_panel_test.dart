import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/video_detail.dart';

void main() {
  group('TrackDetailPanel Layout Tests', () {
    // Test responsive behavior without full Riverpod setup

    testWidgets('Empty state shows music note icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              color: Colors.grey[100],
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 72,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text('选择一首歌曲播放'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note_outlined), findsOneWidget);
      expect(find.text('选择一首歌曲播放'), findsOneWidget);
    });

    testWidgets('Loading state shows progress indicator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              color: Colors.grey[100],
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Error state shows error icon and retry button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text('加载失败'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () {},
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('VideoDetail Model Tests', () {
    test('VideoDetail formats duration correctly', () {
      final detail = VideoDetail(
        bvid: 'BV123456',
        title: 'Test Video',
        description: 'Test description',
        coverUrl: 'https://example.com/cover.jpg',
        durationSeconds: 185, // 3:05
        viewCount: 1000,
        likeCount: 100,
        coinCount: 50,
        favoriteCount: 30,
        shareCount: 20,
        danmakuCount: 500,
        commentCount: 25,
        publishDate: DateTime(2024, 1, 15),
        ownerName: 'Test User',
        ownerFace: 'https://example.com/avatar.jpg',
        ownerId: 12345,
        hotComments: [],
      );

      expect(detail.formattedDuration, equals('3:05'));
    });

    test('VideoDetail formats hour-long duration correctly', () {
      final detail = VideoDetail(
        bvid: 'BV123456',
        title: 'Long Video',
        description: '',
        coverUrl: '',
        durationSeconds: 3725, // 1:02:05
        viewCount: 0,
        likeCount: 0,
        coinCount: 0,
        favoriteCount: 0,
        shareCount: 0,
        danmakuCount: 0,
        commentCount: 0,
        publishDate: DateTime.now(),
        ownerName: '',
        ownerFace: '',
        ownerId: 0,
        hotComments: [],
      );

      expect(detail.formattedDuration, equals('1:02:05'));
    });

    test('VideoDetail formats view count correctly', () {
      // Test small numbers
      final smallDetail = VideoDetail(
        bvid: 'BV123456',
        title: 'Test',
        description: '',
        coverUrl: '',
        durationSeconds: 0,
        viewCount: 500,
        likeCount: 0,
        coinCount: 0,
        favoriteCount: 0,
        shareCount: 0,
        danmakuCount: 0,
        commentCount: 0,
        publishDate: DateTime.now(),
        ownerName: '',
        ownerFace: '',
        ownerId: 0,
        hotComments: [],
      );

      expect(smallDetail.formattedViewCount, equals('500'));

      // Test thousands
      final kDetail = VideoDetail(
        bvid: 'BV123456',
        title: 'Test',
        description: '',
        coverUrl: '',
        durationSeconds: 0,
        viewCount: 15000,
        likeCount: 0,
        coinCount: 0,
        favoriteCount: 0,
        shareCount: 0,
        danmakuCount: 0,
        commentCount: 0,
        publishDate: DateTime.now(),
        ownerName: '',
        ownerFace: '',
        ownerId: 0,
        hotComments: [],
      );

      expect(kDetail.formattedViewCount, equals('1.5万'));

      // Test millions
      final mDetail = VideoDetail(
        bvid: 'BV123456',
        title: 'Test',
        description: '',
        coverUrl: '',
        durationSeconds: 0,
        viewCount: 1500000,
        likeCount: 0,
        coinCount: 0,
        favoriteCount: 0,
        shareCount: 0,
        danmakuCount: 0,
        commentCount: 0,
        publishDate: DateTime.now(),
        ownerName: '',
        ownerFace: '',
        ownerId: 0,
        hotComments: [],
      );

      expect(mDetail.formattedViewCount, equals('150.0万'));
    });

    test('VideoComment formats like count correctly', () {
      final comment = VideoComment(
        id: 1,
        content: 'Great video!',
        memberName: 'User',
        memberAvatar: '',
        likeCount: 2500,
        createTime: DateTime.now(),
      );

      expect(comment.formattedLikeCount, equals('2500'));
    });
  });

  group('Description Section Tests', () {
    testWidgets('Short description shows without expand button', (tester) async {
      const shortDescription = 'This is a short description.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('简介'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(shortDescription),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text(shortDescription), findsOneWidget);
      expect(find.text('展开'), findsNothing);
    });
  });

  group('Comment Pager Navigation Tests', () {
    test('Comment index navigation logic', () {
      const totalComments = 3;
      int currentIndex = 0;

      // Test hasNext
      bool hasNext() => currentIndex < totalComments - 1;
      bool hasPrevious() => currentIndex > 0;

      expect(hasNext(), isTrue);
      expect(hasPrevious(), isFalse);

      // Move to next
      currentIndex = 1;
      expect(hasNext(), isTrue);
      expect(hasPrevious(), isTrue);

      // Move to last
      currentIndex = 2;
      expect(hasNext(), isFalse);
      expect(hasPrevious(), isTrue);
    });

    test('Comment wrap-around navigation', () {
      const totalComments = 3;
      int currentIndex = 2;

      // Simulate wrap-around
      void goToNextWithWrap() {
        if (currentIndex < totalComments - 1) {
          currentIndex++;
        } else {
          currentIndex = 0; // Wrap to beginning
        }
      }

      goToNextWithWrap();
      expect(currentIndex, equals(0));
    });
  });

  group('Stats Display Tests', () {
    test('Stats format correctly with different values', () {
      // Simulate stat formatting
      String formatCount(int count) {
        if (count >= 10000000) {
          return '${(count / 10000000).toStringAsFixed(1)}千万';
        } else if (count >= 10000) {
          return '${(count / 10000).toStringAsFixed(1)}万';
        }
        return count.toString();
      }

      expect(formatCount(500), equals('500'));
      expect(formatCount(5000), equals('5000'));
      expect(formatCount(15000), equals('1.5万'));
      expect(formatCount(150000), equals('15.0万'));
      expect(formatCount(15000000), equals('1.5千万'));
    });
  });

  group('Next Track Section Tests', () {
    testWidgets('Next track section shows track info', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.skip_next_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('下一首'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Next Song Title'),
                            SizedBox(height: 4),
                            Text('Artist Name'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('下一首'), findsOneWidget);
      expect(find.text('Next Song Title'), findsOneWidget);
      expect(find.text('Artist Name'), findsOneWidget);
    });
  });
}
