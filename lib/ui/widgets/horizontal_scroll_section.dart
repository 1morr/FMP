import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/ui_constants.dart';

/// A horizontal scroll section with:
/// - Gradient indicators on edges when more content exists
/// - Arrow navigation buttons on desktop (on hover)
/// - Page-based scrolling with easing animation
/// - Touch scrolling on mobile (no arrows)
class HorizontalScrollSection extends StatefulWidget {
  /// The list of items to display
  final List<Widget> children;

  /// Fixed height of the scroll section
  final double height;

  /// Width of each item (must be consistent for page calculation)
  final double itemWidth;

  /// Spacing between items
  final double itemSpacing;

  /// Padding at start and end of the list
  final double horizontalPadding;

  const HorizontalScrollSection({
    super.key,
    required this.children,
    required this.height,
    required this.itemWidth,
    this.itemSpacing = 12,
    this.horizontalPadding = 16,
  });

  @override
  State<HorizontalScrollSection> createState() =>
      _HorizontalScrollSectionState();
}

class _HorizontalScrollSectionState extends State<HorizontalScrollSection> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovering = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  double? _lastViewportWidth;

  /// Check if we're on a desktop platform (not mobile)
  bool get _isDesktop {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollState);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HorizontalScrollSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When children change, recalculate scroll state after layout
    if (oldWidget.children.length != widget.children.length ||
        oldWidget.itemWidth != widget.itemWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollState();
      });
    }
  }

  void _updateScrollState() {
    if (!mounted || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final canLeft = position.pixels > 0.5; // Small threshold for floating point
    final canRight = position.pixels < position.maxScrollExtent - 0.5;

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  /// Recalculate scroll state when viewport width changes (e.g., window resize)
  void _onViewportWidthChanged(double viewportWidth) {
    if (_lastViewportWidth != viewportWidth) {
      _lastViewportWidth = viewportWidth;
      // Schedule after this frame to ensure layout is complete
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollState();
      });
    }
  }

  /// Calculate how many items fit in visible area
  int _calculateVisibleItemCount(double viewportWidth) {
    final availableWidth = viewportWidth - widget.horizontalPadding * 2;
    final itemWithSpacing = widget.itemWidth + widget.itemSpacing;
    return (availableWidth / itemWithSpacing).floor().clamp(1, widget.children.length);
  }

  /// Scroll by a specific number of items with easing animation
  void _scrollByItems(int itemCount) {
    if (!_scrollController.hasClients) return;

    final itemWithSpacing = widget.itemWidth + widget.itemSpacing;
    final scrollAmount = itemCount * itemWithSpacing;
    final newOffset = (_scrollController.offset + scrollAmount).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      newOffset,
      duration: AnimationDurations.normal,
      curve: Curves.easeOutCubic, // Fast start, slow end
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final visibleItems = _calculateVisibleItemCount(viewportWidth);

        // Detect viewport width change (window resize)
        _onViewportWidthChanged(viewportWidth);

        return MouseRegion(
          onEnter: _isDesktop ? (_) => setState(() => _isHovering = true) : null,
          onExit: _isDesktop ? (_) => setState(() => _isHovering = false) : null,
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                // Main scrollable content with notification listener
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Catch scroll metrics changes (including resize)
                    if (notification is ScrollMetricsNotification) {
                      _updateScrollState();
                    }
                    return false;
                  },
                  child: ScrollConfiguration(
                    behavior: _NoScrollbarScrollBehavior(),
                    child: ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.horizontalPadding,
                      ),
                      physics: _isDesktop
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      itemCount: widget.children.length,
                      separatorBuilder: (context, index) =>
                          SizedBox(width: widget.itemSpacing),
                      itemBuilder: (context, index) => widget.children[index],
                    ),
                  ),
                ),

                // Left gradient indicator
                if (_canScrollLeft)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              colorScheme.surface,
                              colorScheme.surface.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Right gradient indicator
                if (_canScrollRight)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              colorScheme.surface,
                              colorScheme.surface.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Left arrow button (desktop only, on hover)
                if (_isDesktop && _isHovering && _canScrollLeft)
                  Positioned(
                    left: 8,
                    top: 40,
                    child: _ArrowButton(
                      icon: Icons.chevron_left,
                      onPressed: () => _scrollByItems(-visibleItems),
                      colorScheme: colorScheme,
                    ),
                  ),

                // Right arrow button (desktop only, on hover)
                if (_isDesktop && _isHovering && _canScrollRight)
                  Positioned(
                    right: 8,
                    top: 40,
                    child: _ArrowButton(
                      icon: Icons.chevron_right,
                      onPressed: () => _scrollByItems(visibleItems),
                      colorScheme: colorScheme,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Circular arrow button for navigation
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;

  const _ArrowButton({
    required this.icon,
    required this.onPressed,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: colorScheme.surfaceContainerHighest,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 22,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Custom scroll behavior that hides the scrollbar and disables mouse drag on desktop
class _NoScrollbarScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Return child without scrollbar
    return child;
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
