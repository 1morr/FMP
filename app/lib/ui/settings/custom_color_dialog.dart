import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 自訂主題色對話框（ADR 0035 §決定 5）：色相、飽和度、明度三條滑桿加 HEX 輸入，
/// 兩邊互相同步。回傳選的不透明色，取消為 `null`。
///
/// 自己寫而不用 `flex_color_picker`：App 的主題用 `material_ui` 的 `Theme`，那個套件建在
/// 凍結的 `package:flutter/material.dart` 上，讀不到 App 的主題。
Future<Color?> showCustomColorDialog(BuildContext context, Color initial) =>
    showDialog<Color>(
      context: context,
      builder: (context) => _CustomColorDialog(initial: initial),
    );

/// 六位 HEX（可帶 `#`）轉成不透明色；不合法為 `null`。
Color? parseHexColor(String input) {
  final text = input.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(text)) return null;
  return Color(0xFF000000 | int.parse(text, radix: 16));
}

/// [color] 的六位大寫 HEX（不含 `#`）。
String hexOf(Color color) => (color.toARGB32() & 0xFFFFFF)
    .toRadixString(16)
    .padLeft(6, '0')
    .toUpperCase();

class _CustomColorDialog extends ConsumerStatefulWidget {
  const _CustomColorDialog({required this.initial});

  final Color initial;

  @override
  ConsumerState<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends ConsumerState<_CustomColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: hexOf(widget.initial),
  );
  bool _hexValid = true;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexValid = true;
      _hex.text = hexOf(hsv.toColor());
    });
  }

  void _onHex(String text) {
    final color = parseHexColor(text);
    setState(() {
      _hexValid = color != null;
      if (color != null) _hsv = HSVColor.fromColor(color);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).appearance;
    final spacing = AppTokens.of(context).spacing;
    return AlertDialog(
      title: Text(t.customColorTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: AppLayout.colorPreview,
                  height: AppLayout.colorPreview,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: spacing.x4),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    onChanged: _onHex,
                    maxLength: 7,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                    ],
                    decoration: InputDecoration(
                      labelText: t.customColorHex,
                      prefixText: '#',
                      counterText: '',
                      errorText: _hexValid ? null : t.customColorHexInvalid,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.x4),
            _ChannelSlider(
              label: t.customColorHue,
              value: _hsv.hue,
              max: 360,
              onChanged: (value) => _setHsv(_hsv.withHue(value)),
            ),
            _ChannelSlider(
              label: t.customColorSaturation,
              value: _hsv.saturation,
              max: 1,
              onChanged: (value) => _setHsv(_hsv.withSaturation(value)),
            ),
            _ChannelSlider(
              label: t.customColorBrightness,
              value: _hsv.value,
              max: 1,
              onChanged: (value) => _setHsv(_hsv.withValue(value)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.customColorCancel),
        ),
        FilledButton(
          onPressed: _hexValid
              ? () => Navigator.of(context).pop(_hsv.toColor())
              : null,
          child: Text(t.customColorApply),
        ),
      ],
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelMedium),
        Slider(
          value: value.clamp(0, max),
          max: max,
          // 色相讀度數；飽和度與明度是 0–1，讀成百分比（round 會只剩 0 或 1）。
          semanticFormatterCallback: (value) => max == 1
              ? '$label ${(value * 100).round()}%'
              : '$label ${value.round()}',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
