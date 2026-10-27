import 'package:material_ui/material_ui.dart';

import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 音源的 chip 列（ADR 0024 §決定 6、ADR 0035 §決定 9）：第一顆是「全部音源」，單選、可橫向捲動，還有內容捲在外面的
/// 那一端以漸層淡出，提示可以捲。
class SourceChips extends StatefulWidget {
  const SourceChips({
    super.key,
    required this.sources,
    required this.allLabel,
    required this.selectedId,
    required this.onSelected,
  });

  final List<SourcePlugin> sources;

  /// 第一顆「全部音源」chip 的文字。
  final String allLabel;

  /// 選的音源；`null` 是「全部音源」。
  final String? selectedId;

  /// 點了一顆；`null` 是「全部音源」。
  final ValueChanged<String?> onSelected;

  @override
  State<SourceChips> createState() => _SourceChipsState();
}

class _SourceChipsState extends State<SourceChips> {
  final _scroll = ScrollController();

  /// 開頭／結尾還有內容在畫面外。
  bool _moreBefore = false;
  bool _moreAfter = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateEdges);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _updateEdges() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final before = position.pixels > position.minScrollExtent;
    final after = position.pixels < position.maxScrollExtent;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    final fade = spacing.x6;
    // dstIn 只看 alpha：不透明的地方照畫，透明的地方挖掉。
    final opaque = Theme.of(context).colorScheme.onSurface;
    final clear = opaque.withValues(alpha: 0);
    return NotificationListener<ScrollMetricsNotification>(
      // 第一次排版與視窗改變寬度時，捲動範圍才確定。
      onNotification: (_) {
        _updateEdges();
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final edge = bounds.width == 0 ? 0.0 : fade / bounds.width;
          return LinearGradient(
            colors: [
              if (_moreBefore) clear else opaque,
              opaque,
              opaque,
              if (_moreAfter) clear else opaque,
            ],
            stops: [0, edge, 1 - edge, 1],
          ).createShader(bounds);
        },
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: spacing.x4),
          child: Row(
            children: [
              ChoiceChip(
                label: Text(widget.allLabel),
                selected: widget.selectedId == null,
                onSelected: (_) => widget.onSelected(null),
              ),
              for (final source in widget.sources)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: spacing.x2),
                  child: ChoiceChip(
                    label: Text(source.manifest.name),
                    selected: source.manifest.id == widget.selectedId,
                    onSelected: (_) => widget.onSelected(source.manifest.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
