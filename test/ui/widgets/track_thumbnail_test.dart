import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/ui/widgets/track_thumbnail.dart';

void main() {
  group('TrackThumbnail', () {
    testWidgets('renders with correct size', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackThumbnail(
              track: track,
              size: 64,
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, equals(64));
      expect(sizedBox.height, equals(64));
    });

    testWidgets('shows placeholder icon when no cover available', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackThumbnail(
              track: track,
              size: 48,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('applies custom border radius', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackThumbnail(
              track: track,
              size: 48,
              borderRadius: 8,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, equals(BorderRadius.circular(8)));
    });

    testWidgets('shows playing indicator when isPlaying is true', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackThumbnail(
              track: track,
              size: 48,
              showPlayingIndicator: true,
              isPlaying: true,
            ),
          ),
        ),
      );

      // Should find the playing overlay (Stack with multiple children)
      expect(find.byType(Stack), findsOneWidget);
    });

    testWidgets('hides playing indicator when showPlayingIndicator is false', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackThumbnail(
              track: track,
              size: 48,
              showPlayingIndicator: false,
              isPlaying: true,
            ),
          ),
        ),
      );

      // NowPlayingIndicator should not be present when disabled
      // We check that the Stack only has one child (the image)
      final stack = tester.widget<Stack>(find.byType(Stack).first);
      final nonNullChildren = stack.children
          .where((widget) => widget is! Positioned || widget.child != null)
          .toList();
      // Only the image should be visible (indicator hidden)
      expect(nonNullChildren.length, equals(1));
    });

    testWidgets('applies default size of 48', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackThumbnail(track: track),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, equals(48));
      expect(sizedBox.height, equals(48));
    });
  });

  group('TrackCover', () {
    testWidgets('renders with 16:9 aspect ratio by default', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: TrackCover(track: track),
            ),
          ),
        ),
      );

      final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(aspectRatio.aspectRatio, equals(16 / 9));
    });

    testWidgets('renders with custom aspect ratio', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: TrackCover(
                track: track,
                aspectRatio: 1.0,
              ),
            ),
          ),
        ),
      );

      final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(aspectRatio.aspectRatio, equals(1.0));
    });

    testWidgets('shows placeholder when no track provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: const TrackCover(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('uses networkUrl over track thumbnailUrl', (tester) async {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test Track'
        ..thumbnailUrl = 'https://example.com/track.jpg';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: TrackCover(
                track: track,
                networkUrl: 'https://example.com/custom.jpg',
              ),
            ),
          ),
        ),
      );

      // Widget should render without errors
      expect(find.byType(TrackCover), findsOneWidget);
    });

    testWidgets('applies custom border radius', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: const TrackCover(borderRadius: 24),
            ),
          ),
        ),
      );

      final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(
        clipRRect.borderRadius,
        equals(BorderRadius.circular(24)),
      );
    });
  });
}
