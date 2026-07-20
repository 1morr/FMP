import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';

/// 可展开文本区块（支持展开/收起，用于简介/公告等）。
///
/// 音樂/電台 Detail Panel 與行動版資訊彈窗共用；maxLines 統一為 6。
class ExpandableTextSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final String content;
  final int maxLines;

  const ExpandableTextSection({
    super.key,
    required this.icon,
    required this.title,
    required this.content,
    this.maxLines = 6,
  });

  @override
  State<ExpandableTextSection> createState() => _ExpandableTextSectionState();
}

class _ExpandableTextSectionState extends State<ExpandableTextSection> {
  bool _isExpanded = false;
  bool _needsExpansion = false;
  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsExpansion();
    });
  }

  @override
  void didUpdateWidget(ExpandableTextSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _isExpanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkIfNeedsExpansion();
      });
    }
  }

  void _checkIfNeedsExpansion() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
      ),
      maxLines: widget.maxLines,
      textDirection: TextDirection.ltr,
    );

    final renderBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      textPainter.layout(maxWidth: renderBox.size.width);
      if (mounted) {
        setState(() {
          _needsExpansion = textPainter.didExceedMaxLines;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.content,
          key: _textKey,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
          maxLines: _isExpanded ? null : widget.maxLines,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (_needsExpansion)
          Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _isExpanded ? t.trackDetail.collapse : t.trackDetail.expand,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
