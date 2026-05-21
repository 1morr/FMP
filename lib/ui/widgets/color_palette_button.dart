import 'package:flutter/material.dart';

class ColorPaletteButton extends StatelessWidget {
  static const paletteKey = ValueKey('color-palette-dialog');
  static const paletteContentKey = ValueKey('color-palette-dialog-content');
  static const saturationValueKey = ValueKey('color-palette-sv');

  final String label;
  final String? closeLabel;
  final Color color;
  final ValueChanged<Color> onChanged;

  const ColorPaletteButton({
    super.key,
    required this.label,
    this.closeLabel,
    required this.color,
    required this.onChanged,
  });

  static String formatColor(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  Future<void> _openPalette(BuildContext context) {
    return ColorPaletteDialog.show(
      context: context,
      label: label,
      closeLabel: closeLabel,
      color: color,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hex = formatColor(color);

    return Tooltip(
      message: label,
      child: OutlinedButton(
        onPressed: () => _openPalette(context),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(112, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ColorSwatch(color: color, size: 18),
            const SizedBox(width: 7),
            Text(
              hex,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ColorPaletteDialog extends StatefulWidget {
  final String label;
  final String? closeLabel;
  final Color color;
  final ValueChanged<Color> onChanged;

  const ColorPaletteDialog({
    super.key,
    required this.label,
    this.closeLabel,
    required this.color,
    required this.onChanged,
  });

  static Future<void> show({
    required BuildContext context,
    required String label,
    String? closeLabel,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) => ColorPaletteDialog(
        label: label,
        closeLabel: closeLabel,
        color: color,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<ColorPaletteDialog> createState() => _ColorPaletteDialogState();
}

class _ColorPaletteDialogState extends State<ColorPaletteDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
  }

  void _update(HSVColor next) {
    setState(() => _hsv = next);
    widget.onChanged(next.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final colorScheme = Theme.of(context).colorScheme;
    final windowSize = MediaQuery.sizeOf(context);
    final horizontalInset = windowSize.width < 320 ? 12.0 : 24.0;
    final verticalInset = windowSize.height < 360 ? 12.0 : 24.0;
    final dialogWidth =
        (windowSize.width - horizontalInset * 2).clamp(212.0, 316.0);
    final dialogMaxHeight =
        (windowSize.height - verticalInset * 2).clamp(180.0, double.infinity);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset, vertical: verticalInset),
      child: ConstrainedBox(
        key: ColorPaletteButton.paletteKey,
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _ColorSwatch(color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  key: ColorPaletteButton.paletteContentKey,
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SaturationValuePicker(
                        hsv: _hsv,
                        onChanged: _update,
                      ),
                      const SizedBox(height: 10),
                      _HuePicker(
                        hue: _hsv.hue,
                        onChanged: (hue) => _update(_hsv.withHue(hue)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.light_mode_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                              ),
                              child: Slider(
                                value: _hsv.value,
                                min: 0,
                                max: 1,
                                onChanged: (value) =>
                                    _update(_hsv.withValue(value)),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 34,
                            child: Text(
                              '${(_hsv.value * 100).round()}%',
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          ColorPaletteButton.formatColor(color),
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      widget.closeLabel ??
                          MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final double size;

  const _ColorSwatch({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  const _SaturationValuePicker({
    required this.hsv,
    required this.onChanged,
  });

  void _handlePointer(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(globalPosition);
    final saturation = (local.dx / box.size.width).clamp(0.0, 1.0);
    final value = (1 - local.dy / box.size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ColorPaletteButton.saturationValueKey,
      onPanDown: (details) => _handlePointer(context, details.globalPosition),
      onPanUpdate: (details) => _handlePointer(context, details.globalPosition),
      child: SizedBox(
        height: 132,
        width: double.infinity,
        child: CustomPaint(
          painter: _SaturationValuePainter(hsv: hsv),
        ),
      ),
    );
  }
}

class _HuePicker extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HuePicker({
    required this.hue,
    required this.onChanged,
  });

  void _handlePointer(BuildContext context, Offset globalPosition) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(globalPosition);
    onChanged((local.dx / box.size.width).clamp(0.0, 1.0) * 360);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (details) => _handlePointer(context, details.globalPosition),
      onPanUpdate: (details) => _handlePointer(context, details.globalPosition),
      child: SizedBox(
        height: 24,
        width: double.infinity,
        child: CustomPaint(
          painter: _HuePainter(hue: hue),
        ),
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  final HSVColor hsv;

  const _SaturationValuePainter({required this.hsv});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    final radius = BorderRadius.circular(8).toRRect(rect);

    canvas.save();
    canvas.clipRRect(radius);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();

    final selector =
        Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(selector, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      selector,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) {
    return oldDelegate.hsv != hsv;
  }
}

class _HuePainter extends CustomPainter {
  static const _hueColors = [
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  final double hue;

  const _HuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = BorderRadius.circular(8).toRRect(rect);

    canvas.save();
    canvas.clipRRect(radius);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(colors: _hueColors).createShader(rect),
    );
    canvas.restore();

    final x = (hue / 360).clamp(0.0, 1.0) * size.width;
    final handleRect = Rect.fromCenter(
      center: Offset(x, size.height / 2),
      width: 5,
      height: size.height + 2,
    );
    canvas.drawRRect(
      BorderRadius.circular(3).toRRect(handleRect),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      BorderRadius.circular(3).toRRect(handleRect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_HuePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}
