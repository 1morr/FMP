import 'package:flutter/material.dart';

import '../../services/lyrics/lyrics_window_style.dart';
import 'color_palette_button.dart';
import 'switch_expansion_tile.dart';

class LyricsStyleDialogLabels {
  final String styleSettings;
  final String textColor;
  final String secondaryTextColor;
  final String inactiveOpacity;
  final String outline;
  final String outlineColor;
  final String outlineWidth;
  final String shadow;
  final String shadowColor;
  final String shadowBlur;
  final String shadowOffsetX;
  final String shadowOffsetY;
  final String resetStyle;
  final String close;

  const LyricsStyleDialogLabels({
    required this.styleSettings,
    required this.textColor,
    required this.secondaryTextColor,
    required this.inactiveOpacity,
    required this.outline,
    required this.outlineColor,
    required this.outlineWidth,
    required this.shadow,
    required this.shadowColor,
    required this.shadowBlur,
    required this.shadowOffsetX,
    required this.shadowOffsetY,
    required this.resetStyle,
    required this.close,
  });
}

class LyricsStyleDialog extends StatefulWidget {
  final LyricsWindowStyle initialStyle;
  final LyricsStyleDialogLabels labels;
  final ValueChanged<LyricsWindowStyle> onChanged;
  final VoidCallback onReset;

  const LyricsStyleDialog({
    super.key,
    required this.initialStyle,
    required this.labels,
    required this.onChanged,
    required this.onReset,
  });

  @override
  State<LyricsStyleDialog> createState() => _LyricsStyleDialogState();
}

class _LyricsStyleDialogState extends State<LyricsStyleDialog> {
  late LyricsWindowStyle _style;
  final _scrollController = ScrollController();
  bool _outlineExpanded = false;
  bool _shadowExpanded = false;

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _update(LyricsWindowStyle style) {
    setState(() => _style = style);
    widget.onChanged(style);
  }

  Widget _colorSetting({
    required String label,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        ColorPaletteButton(
          label: label,
          closeLabel: widget.labels.close,
          color: color,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _sliderSetting({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    String Function(double value)? valueLabel,
  }) {
    final formatted = valueLabel?.call(value) ?? value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Text(
              formatted,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: formatted,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(
        children: [
          const Icon(Icons.palette_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              labels.styleSettings,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 420),
        child: Scrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _colorSetting(
                  label: labels.textColor,
                  color: _style.textColor,
                  onChanged: (color) => _update(
                    _style.copyWith(textColor: color),
                  ),
                ),
                const SizedBox(height: 10),
                _colorSetting(
                  label: labels.secondaryTextColor,
                  color: _style.secondaryTextColor,
                  onChanged: (color) => _update(
                    _style.copyWith(secondaryTextColor: color),
                  ),
                ),
                const SizedBox(height: 10),
                _sliderSetting(
                  label: labels.inactiveOpacity,
                  value: _style.inactiveOpacity,
                  min: 0.15,
                  max: 1,
                  divisions: 17,
                  valueLabel: (value) => '${(value * 100).round()}%',
                  onChanged: (value) => _update(
                    _style.copyWith(inactiveOpacity: value),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchExpansionTile(
                  title: labels.outline,
                  expanded: _outlineExpanded,
                  enabled: _style.outlineEnabled,
                  onExpanded: (value) =>
                      setState(() => _outlineExpanded = value),
                  onEnabledChanged: (value) => _update(
                    _style.copyWith(outlineEnabled: value),
                  ),
                  children: [
                    _colorSetting(
                      label: labels.outlineColor,
                      color: _style.outlineColor,
                      onChanged: (color) => _update(
                        _style.copyWith(outlineColor: color),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _sliderSetting(
                      label: labels.outlineWidth,
                      value: _style.outlineWidth,
                      min: 0.5,
                      max: 8,
                      divisions: 15,
                      onChanged: (value) => _update(
                        _style.copyWith(outlineWidth: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchExpansionTile(
                  title: labels.shadow,
                  expanded: _shadowExpanded,
                  enabled: _style.shadowEnabled,
                  onExpanded: (value) =>
                      setState(() => _shadowExpanded = value),
                  onEnabledChanged: (value) => _update(
                    _style.copyWith(shadowEnabled: value),
                  ),
                  children: [
                    _colorSetting(
                      label: labels.shadowColor,
                      color: _style.shadowColor,
                      onChanged: (color) => _update(
                        _style.copyWith(shadowColor: color),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _sliderSetting(
                      label: labels.shadowBlur,
                      value: _style.shadowBlurRadius,
                      min: 0,
                      max: 24,
                      divisions: 24,
                      onChanged: (value) => _update(
                        _style.copyWith(shadowBlurRadius: value),
                      ),
                    ),
                    _sliderSetting(
                      label: labels.shadowOffsetX,
                      value: _style.shadowOffset.dx,
                      min: -12,
                      max: 12,
                      divisions: 24,
                      onChanged: (value) => _update(
                        _style.copyWith(
                          shadowOffset: Offset(value, _style.shadowOffset.dy),
                        ),
                      ),
                    ),
                    _sliderSetting(
                      label: labels.shadowOffsetY,
                      value: _style.shadowOffset.dy,
                      min: -12,
                      max: 12,
                      divisions: 24,
                      onChanged: (value) => _update(
                        _style.copyWith(
                          shadowOffset: Offset(_style.shadowOffset.dx, value),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              _style = LyricsWindowStyle.defaults;
              _outlineExpanded = false;
              _shadowExpanded = false;
            });
            widget.onReset();
          },
          icon: const Icon(Icons.refresh),
          label: Text(labels.resetStyle),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(labels.close),
        ),
      ],
    );
  }
}
