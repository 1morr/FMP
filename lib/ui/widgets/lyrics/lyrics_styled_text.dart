import 'package:flutter/material.dart';

import '../../../services/lyrics/lyrics_window_style.dart';

class LyricsTextStyles {
  const LyricsTextStyles._();

  static TextStyle themeBase(BuildContext context) {
    return Theme.of(context).textTheme.bodyLarge ??
        DefaultTextStyle.of(context).style;
  }

  static TextStyle fromTheme(
    BuildContext context, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return fromBase(
      themeBase(context),
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  static TextStyle fromBase(
    TextStyle base, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return base.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }
}

class LyricsStyledText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final LyricsWindowStyle lyricsStyle;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const LyricsStyledText(
    this.text, {
    super.key,
    required this.style,
    required this.lyricsStyle,
    this.textAlign = TextAlign.center,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final fillStyle = style.copyWith(shadows: lyricsStyle.shadows);

    if (!lyricsStyle.outlineEnabled) {
      return Text(
        text,
        style: fillStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final strokeStyle = style.copyWith(
      color: null,
      shadows: null,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lyricsStyle.outlineWidth
        ..strokeJoin = StrokeJoin.round
        ..color = lyricsStyle.outlineColor,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          style: strokeStyle,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        ),
        Text(
          text,
          style: fillStyle,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        ),
      ],
    );
  }
}
