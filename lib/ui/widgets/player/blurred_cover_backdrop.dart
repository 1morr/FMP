import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/extensions/track_extensions.dart';
import '../../../data/models/track.dart';
import '../../../providers/download/file_exists_cache.dart';
import '../images/radio_cover_image.dart';
import '../images/track_thumbnail.dart';

/// Track cover blurred backdrop used by the full player surfaces.
class TrackBlurredBackdrop extends ConsumerWidget {
  final Track? currentTrack;
  final ColorScheme colorScheme;
  final double surfaceOverlayAlpha;
  final double surfaceContainerOverlayAlpha;

  const TrackBlurredBackdrop({
    super.key,
    required this.currentTrack,
    required this.colorScheme,
    required this.surfaceOverlayAlpha,
    required this.surfaceContainerOverlayAlpha,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(fileExistsCacheProvider);

    final cache = ref.read(fileExistsCacheProvider.notifier);
    final localCoverPath = currentTrack?.getLocalCoverPath(cache);
    final size = MediaQuery.sizeOf(context);
    final sourceKey = _trackSourceKey(currentTrack, localCoverPath);
    final candidates = TrackCover.imageProviderCandidates(
      context: context,
      localPath: localCoverPath,
      networkUrl: currentTrack?.thumbnailUrl,
      width: size.width,
      height: size.height,
      variant: TrackCoverVariant.backdrop,
    );

    return BlurredCoverBackdrop(
      sourceKey: sourceKey,
      imageCandidates: candidates,
      colorScheme: colorScheme,
      surfaceOverlayAlpha: surfaceOverlayAlpha,
      surfaceContainerOverlayAlpha: surfaceContainerOverlayAlpha,
    );
  }

  String? _trackSourceKey(Track? track, String? localCoverPath) {
    if (track == null) return null;
    if (localCoverPath != null) return 'local:$localCoverPath';

    final thumbnailUrl = track.thumbnailUrl;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return 'network:$thumbnailUrl';
    }

    return null;
  }
}

/// Radio cover blurred backdrop used by the radio player surfaces.
class RadioBlurredBackdrop extends StatelessWidget {
  final String? networkUrl;
  final ColorScheme colorScheme;
  final double surfaceOverlayAlpha;
  final double surfaceContainerOverlayAlpha;

  const RadioBlurredBackdrop({
    super.key,
    required this.networkUrl,
    required this.colorScheme,
    required this.surfaceOverlayAlpha,
    required this.surfaceContainerOverlayAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final sourceKey = networkUrl != null && networkUrl!.isNotEmpty
        ? 'network:$networkUrl'
        : null;
    final candidates = RadioCoverImage.imageProviderCandidates(
      context: context,
      networkUrl: networkUrl,
      width: size.width,
      height: size.height,
      variant: RadioCoverVariant.backdrop,
    );

    return BlurredCoverBackdrop(
      sourceKey: sourceKey,
      imageCandidates: candidates,
      colorScheme: colorScheme,
      surfaceOverlayAlpha: surfaceOverlayAlpha,
      surfaceContainerOverlayAlpha: surfaceContainerOverlayAlpha,
    );
  }
}

/// Blurred image backdrop.
///
/// New cover images are preloaded before replacing the current background so
/// page transitions and playback changes do not flash a placeholder color.
class BlurredCoverBackdrop extends StatefulWidget {
  final String? sourceKey;
  final List<ImageProvider> imageCandidates;
  final ColorScheme colorScheme;
  final double surfaceOverlayAlpha;
  final double surfaceContainerOverlayAlpha;

  const BlurredCoverBackdrop({
    super.key,
    required this.sourceKey,
    required this.imageCandidates,
    required this.colorScheme,
    required this.surfaceOverlayAlpha,
    required this.surfaceContainerOverlayAlpha,
  });

  @override
  State<BlurredCoverBackdrop> createState() => _BlurredCoverBackdropState();
}

class _BlurredCoverBackdropState extends State<BlurredCoverBackdrop> {
  ImageProvider? _imageProvider;
  final _loadState = BlurredCoverBackdropLoadState();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    _scheduleImageLoad(widget.sourceKey, widget.imageCandidates);

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.colorScheme.surface),
          if (_imageProvider != null)
            AnimatedSwitcher(
              duration: AnimationDurations.normal,
              child: ImageFiltered(
                key: ValueKey(_loadState.loadedKey),
                imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: Image(
                  image: _imageProvider!,
                  fit: BoxFit.cover,
                  width: size.width,
                  height: size.height,
                  gaplessPlayback: true,
                ),
              ),
            ),
          Container(
            color: widget.colorScheme.surface
                .withValues(alpha: widget.surfaceOverlayAlpha),
          ),
          Container(
            color: widget.colorScheme.surfaceContainerHighest
                .withValues(alpha: widget.surfaceContainerOverlayAlpha),
          ),
        ],
      ),
    );
  }

  void _scheduleImageLoad(String? sourceKey, List<ImageProvider> candidates) {
    _loadState.updateDesiredKey(sourceKey);

    if (sourceKey == null || candidates.isEmpty) {
      if (_imageProvider != null || _loadState.loadedKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && sourceKey == _loadState.desiredKey) {
            _clearLoadedImage();
          }
        });
      }
      return;
    }

    if (!_loadState.shouldRequest(
      sourceKey,
      hasCandidates: candidates.isNotEmpty,
    )) {
      return;
    }

    final generation = _loadState.markRequested(sourceKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loadState.isCurrentGeneration(generation)) return;
      _loadImage(generation, sourceKey, candidates);
    });
  }

  Future<void> _loadImage(
    int generation,
    String sourceKey,
    List<ImageProvider> candidates,
  ) async {
    for (final candidate in candidates) {
      if (!mounted || !_loadState.isCurrentGeneration(generation)) return;

      final loaded = await _precacheImage(candidate);
      if (!loaded) {
        continue;
      }

      if (!mounted || !_loadState.isCurrentGeneration(generation)) return;

      setState(() {
        _imageProvider = candidate;
        _loadState.markLoaded(sourceKey, generation);
      });
      return;
    }

    if (!mounted || !_loadState.isCurrentGeneration(generation)) return;
    _loadState.markFailed(sourceKey, generation);
  }

  void _clearLoadedImage() {
    setState(() {
      _imageProvider = null;
      _loadState.clearLoaded();
    });
  }

  Future<bool> _precacheImage(ImageProvider candidate) async {
    var failed = false;
    await precacheImage(
      candidate,
      context,
      onError: (_, __) => failed = true,
    );
    return !failed;
  }
}

@visibleForTesting
class BlurredCoverBackdropLoadState {
  String? loadedKey;
  String? desiredKey;
  String? requestedKey;
  int generation = 0;

  void updateDesiredKey(String? sourceKey) {
    if (sourceKey == desiredKey) return;
    desiredKey = sourceKey;
    requestedKey = null;
    generation++;
  }

  bool shouldRequest(String? sourceKey, {required bool hasCandidates}) {
    if (sourceKey == null || !hasCandidates) return false;
    return sourceKey != loadedKey && sourceKey != requestedKey;
  }

  int markRequested(String sourceKey) {
    requestedKey = sourceKey;
    return generation;
  }

  bool isCurrentGeneration(int requestGeneration) {
    return requestGeneration == generation;
  }

  void markLoaded(String sourceKey, int requestGeneration) {
    if (!isCurrentGeneration(requestGeneration)) return;
    loadedKey = sourceKey;
    requestedKey = null;
  }

  void markFailed(String sourceKey, int requestGeneration) {
    if (!isCurrentGeneration(requestGeneration) || sourceKey != desiredKey) {
      return;
    }
    requestedKey = sourceKey;
  }

  void clearLoaded() {
    loadedKey = null;
    requestedKey = null;
  }
}
