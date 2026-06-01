import 'package:flutter/material.dart';

import '../../../services/lyrics/lyrics_window_style.dart';
import '../controls/color_palette_button.dart';
import '../controls/switch_expansion_tile.dart';

class LyricsStyleDialogStrings {
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

  const LyricsStyleDialogStrings({
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
  static const dialogKey = ValueKey('lyrics-style-dialog');
  static const contentKey = ValueKey('lyrics-style-dialog-content');
  static const inactiveOpacitySliderKey =
      ValueKey('lyrics-style-inactive-opacity-slider');
  static const resetButtonKey = ValueKey('lyrics-style-reset-button');

  final LyricsWindowStyle initialStyle;
  final LyricsStyleDialogStrings strings;
  final ValueChanged<LyricsWindowStyle> onChanged;
  final VoidCallback onReset;

  const LyricsStyleDialog({
    super.key,
    required this.initialStyle,
    required this.strings,
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
          closeLabel: widget.strings.close,
          color: color,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _sliderSetting({
    Key? key,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
            key: key,
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
    final strings = widget.strings;
    final windowSize = MediaQuery.sizeOf(context);
    final horizontalInset = windowSize.width < 400 ? 12.0 : 24.0;
    final verticalInset = windowSize.height < 360 ? 12.0 : 24.0;
    final contentWidth =
        (windowSize.width - horizontalInset * 2 - 48).clamp(240.0, 400.0);
    final contentMaxHeight =
        (windowSize.height - verticalInset * 2 - 156).clamp(120.0, 420.0);

    return AlertDialog(
      key: LyricsStyleDialog.dialogKey,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      title: Row(
        children: [
          const Icon(Icons.palette_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              strings.styleSettings,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: contentMaxHeight.toDouble()),
        child: SizedBox(
          key: LyricsStyleDialog.contentKey,
          width: contentWidth.toDouble(),
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
                    label: strings.textColor,
                    color: _style.textColor,
                    onChanged: (color) => _update(
                      _style.copyWith(textColor: color),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _colorSetting(
                    label: strings.secondaryTextColor,
                    color: _style.secondaryTextColor,
                    onChanged: (color) => _update(
                      _style.copyWith(secondaryTextColor: color),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _sliderSetting(
                    key: LyricsStyleDialog.inactiveOpacitySliderKey,
                    label: strings.inactiveOpacity,
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
                    title: strings.outline,
                    expanded: _outlineExpanded,
                    enabled: _style.outlineEnabled,
                    onExpanded: (value) =>
                        setState(() => _outlineExpanded = value),
                    onEnabledChanged: (value) => _update(
                      _style.copyWith(outlineEnabled: value),
                    ),
                    children: [
                      _colorSetting(
                        label: strings.outlineColor,
                        color: _style.outlineColor,
                        onChanged: (color) => _update(
                          _style.copyWith(outlineColor: color),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sliderSetting(
                        label: strings.outlineWidth,
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
                    title: strings.shadow,
                    expanded: _shadowExpanded,
                    enabled: _style.shadowEnabled,
                    onExpanded: (value) =>
                        setState(() => _shadowExpanded = value),
                    onEnabledChanged: (value) => _update(
                      _style.copyWith(shadowEnabled: value),
                    ),
                    children: [
                      _colorSetting(
                        label: strings.shadowColor,
                        color: _style.shadowColor,
                        onChanged: (color) => _update(
                          _style.copyWith(shadowColor: color),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sliderSetting(
                        label: strings.shadowBlur,
                        value: _style.shadowBlurRadius,
                        min: 0,
                        max: 24,
                        divisions: 24,
                        onChanged: (value) => _update(
                          _style.copyWith(shadowBlurRadius: value),
                        ),
                      ),
                      _sliderSetting(
                        label: strings.shadowOffsetX,
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
                        label: strings.shadowOffsetY,
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
      ),
      actions: [
        TextButton.icon(
          key: LyricsStyleDialog.resetButtonKey,
          onPressed: () {
            setState(() {
              _style = LyricsWindowStyle.defaults;
              _outlineExpanded = false;
              _shadowExpanded = false;
            });
            widget.onReset();
          },
          icon: const Icon(Icons.refresh),
          label: Text(strings.resetStyle),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    );
  }
}
