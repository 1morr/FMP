import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/settings.dart';

class LyricsWindowLayout {
  const LyricsWindowLayout._();

  static const double titleBarHeight = 48;
  static const double offsetBarHeight = 56;
  static const double defaultContentTopPadding = 20;
  static const double minWindowWidth = 400;
  static const double minWindowHeight = 300;

  static double contentTopInset({
    required bool transparentMode,
    required bool titleBarVisible,
    required bool offsetControlsVisible,
  }) {
    if (transparentMode) return titleBarHeight;
    if (titleBarVisible) return titleBarHeight;
    return 0;
  }
}

class LyricsWindowStyleCommitDebouncer {
  final Duration delay;
  final ValueChanged<LyricsWindowStyle> commit;
  Timer? _timer;
  LyricsWindowStyle? _pendingStyle;

  LyricsWindowStyleCommitDebouncer({
    this.delay = const Duration(milliseconds: 250),
    required this.commit,
  });

  void schedule(LyricsWindowStyle style) {
    _pendingStyle = style;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  void flush() {
    final style = _pendingStyle;
    _pendingStyle = null;
    _timer?.cancel();
    _timer = null;
    if (style != null) {
      commit(style);
    }
  }

  void cancel() {
    _pendingStyle = null;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    cancel();
  }
}

@immutable
class LyricsWindowStyle {
  static const defaults = LyricsWindowStyle(
    textColor: Colors.white,
    secondaryTextColor: Color(0xB3FFFFFF),
    inactiveOpacity: 0.5,
    outlineEnabled: true,
    outlineColor: Colors.black,
    outlineWidth: 1.5,
    shadowEnabled: true,
    shadowColor: Colors.black,
    shadowBlurRadius: 3,
    shadowOffset: Offset.zero,
  );

  final Color textColor;
  final bool textColorCustomized;
  final Color secondaryTextColor;
  final bool secondaryTextColorCustomized;
  final double inactiveOpacity;
  final bool outlineEnabled;
  final Color outlineColor;
  final double outlineWidth;
  final bool shadowEnabled;
  final Color shadowColor;
  final double shadowBlurRadius;
  final Offset shadowOffset;

  const LyricsWindowStyle({
    required this.textColor,
    this.textColorCustomized = false,
    required this.secondaryTextColor,
    this.secondaryTextColorCustomized = false,
    required this.inactiveOpacity,
    required this.outlineEnabled,
    required this.outlineColor,
    required this.outlineWidth,
    required this.shadowEnabled,
    required this.shadowColor,
    required this.shadowBlurRadius,
    required this.shadowOffset,
  });

  factory LyricsWindowStyle.fromSettings(Settings settings) {
    return LyricsWindowStyle(
      textColor: _colorOrDefault(
        settings.lyricsWindowTextColor,
        defaults.textColor,
      ),
      textColorCustomized: settings.lyricsWindowTextColor != null,
      secondaryTextColor: _colorOrDefault(
        settings.lyricsWindowSecondaryTextColor,
        defaults.secondaryTextColor,
      ),
      secondaryTextColorCustomized:
          settings.lyricsWindowSecondaryTextColor != null,
      inactiveOpacity: _clampDouble(
        settings.lyricsWindowInactiveTextOpacity ?? defaults.inactiveOpacity,
        0.15,
        1,
      ),
      outlineEnabled:
          settings.lyricsWindowOutlineEnabled ?? defaults.outlineEnabled,
      outlineColor: _colorOrDefault(
        settings.lyricsWindowOutlineColor,
        defaults.outlineColor,
      ),
      outlineWidth: _clampDouble(
        settings.lyricsWindowOutlineWidth ?? defaults.outlineWidth,
        0.5,
        8,
      ),
      shadowEnabled:
          settings.lyricsWindowShadowEnabled ?? defaults.shadowEnabled,
      shadowColor: _colorOrDefault(
        settings.lyricsWindowShadowColor,
        defaults.shadowColor,
      ),
      shadowBlurRadius: _clampDouble(
        settings.lyricsWindowShadowBlurRadius ?? defaults.shadowBlurRadius,
        0,
        32,
      ),
      shadowOffset: Offset(
        _clampDouble(
            settings.lyricsWindowShadowOffsetX ?? defaults.shadowOffset.dx,
            -24,
            24),
        _clampDouble(
            settings.lyricsWindowShadowOffsetY ?? defaults.shadowOffset.dy,
            -24,
            24),
      ),
    );
  }

  factory LyricsWindowStyle.fromJson(Object? json) {
    if (json is! Map) return defaults;
    final textColorValue = json['textColor'] as int?;
    final secondaryTextColorValue = json['secondaryTextColor'] as int?;
    return LyricsWindowStyle(
      textColor: _colorOrDefault(textColorValue, defaults.textColor),
      textColorCustomized: json['textColorCustomized'] as bool? ??
          (textColorValue != null &&
              Color(textColorValue) != defaults.textColor),
      secondaryTextColor: _colorOrDefault(
        secondaryTextColorValue,
        defaults.secondaryTextColor,
      ),
      secondaryTextColorCustomized: json['secondaryTextColorCustomized']
              as bool? ??
          (secondaryTextColorValue != null &&
              Color(secondaryTextColorValue) != defaults.secondaryTextColor),
      inactiveOpacity: _clampDouble(
        (json['inactiveOpacity'] as num?)?.toDouble() ??
            defaults.inactiveOpacity,
        0.15,
        1,
      ),
      outlineEnabled:
          json['outlineEnabled'] as bool? ?? defaults.outlineEnabled,
      outlineColor: _colorOrDefault(
        json['outlineColor'] as int?,
        defaults.outlineColor,
      ),
      outlineWidth: _clampDouble(
        (json['outlineWidth'] as num?)?.toDouble() ?? defaults.outlineWidth,
        0.5,
        8,
      ),
      shadowEnabled: json['shadowEnabled'] as bool? ?? defaults.shadowEnabled,
      shadowColor: _colorOrDefault(
        json['shadowColor'] as int?,
        defaults.shadowColor,
      ),
      shadowBlurRadius: _clampDouble(
        (json['shadowBlurRadius'] as num?)?.toDouble() ??
            defaults.shadowBlurRadius,
        0,
        32,
      ),
      shadowOffset: Offset(
        _clampDouble(
          (json['shadowOffsetX'] as num?)?.toDouble() ??
              defaults.shadowOffset.dx,
          -24,
          24,
        ),
        _clampDouble(
          (json['shadowOffsetY'] as num?)?.toDouble() ??
              defaults.shadowOffset.dy,
          -24,
          24,
        ),
      ),
    );
  }

  Map<String, Object> toJson() {
    return {
      'textColor': textColor.toARGB32(),
      'textColorCustomized': textColorCustomized,
      'secondaryTextColor': secondaryTextColor.toARGB32(),
      'secondaryTextColorCustomized': secondaryTextColorCustomized,
      'inactiveOpacity': inactiveOpacity,
      'outlineEnabled': outlineEnabled,
      'outlineColor': outlineColor.toARGB32(),
      'outlineWidth': outlineWidth,
      'shadowEnabled': shadowEnabled,
      'shadowColor': shadowColor.toARGB32(),
      'shadowBlurRadius': shadowBlurRadius,
      'shadowOffsetX': shadowOffset.dx,
      'shadowOffsetY': shadowOffset.dy,
    };
  }

  LyricsWindowStyle copyWith({
    Color? textColor,
    bool? textColorCustomized,
    Color? secondaryTextColor,
    bool? secondaryTextColorCustomized,
    double? inactiveOpacity,
    bool? outlineEnabled,
    Color? outlineColor,
    double? outlineWidth,
    bool? shadowEnabled,
    Color? shadowColor,
    double? shadowBlurRadius,
    Offset? shadowOffset,
  }) {
    return LyricsWindowStyle(
      textColor: textColor ?? this.textColor,
      textColorCustomized: textColorCustomized ??
          (textColor != null || this.textColorCustomized),
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      secondaryTextColorCustomized: secondaryTextColorCustomized ??
          (secondaryTextColor != null || this.secondaryTextColorCustomized),
      inactiveOpacity: inactiveOpacity ?? this.inactiveOpacity,
      outlineEnabled: outlineEnabled ?? this.outlineEnabled,
      outlineColor: outlineColor ?? this.outlineColor,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      shadowEnabled: shadowEnabled ?? this.shadowEnabled,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowBlurRadius: shadowBlurRadius ?? this.shadowBlurRadius,
      shadowOffset: shadowOffset ?? this.shadowOffset,
    );
  }

  void applyToSettings(Settings settings) {
    settings.lyricsWindowTextColor =
        hasCustomTextColor ? textColor.toARGB32() : null;
    settings.lyricsWindowSecondaryTextColor =
        hasCustomSecondaryTextColor ? secondaryTextColor.toARGB32() : null;
    settings.lyricsWindowInactiveTextOpacity = inactiveOpacity;
    settings.lyricsWindowOutlineEnabled = outlineEnabled;
    settings.lyricsWindowOutlineColor = outlineColor.toARGB32();
    settings.lyricsWindowOutlineWidth = outlineWidth;
    settings.lyricsWindowShadowEnabled = shadowEnabled;
    settings.lyricsWindowShadowColor = shadowColor.toARGB32();
    settings.lyricsWindowShadowBlurRadius = shadowBlurRadius;
    settings.lyricsWindowShadowOffsetX = shadowOffset.dx;
    settings.lyricsWindowShadowOffsetY = shadowOffset.dy;
  }

  static void resetSettings(Settings settings) {
    settings.lyricsWindowTextColor = null;
    settings.lyricsWindowSecondaryTextColor = null;
    settings.lyricsWindowInactiveTextOpacity = null;
    settings.lyricsWindowOutlineEnabled = null;
    settings.lyricsWindowOutlineColor = null;
    settings.lyricsWindowOutlineWidth = null;
    settings.lyricsWindowShadowEnabled = null;
    settings.lyricsWindowShadowColor = null;
    settings.lyricsWindowShadowBlurRadius = null;
    settings.lyricsWindowShadowOffsetX = null;
    settings.lyricsWindowShadowOffsetY = null;
  }

  /// Whether outline/shadow should be painted by the styled text widget.
  ///
  /// The default outline/shadow values are the transparent-window defaults, so
  /// normal mode keeps the theme's plain text unless the user customizes a text
  /// effect. Color and inactive-opacity changes are resolved separately by
  /// [resolveMainColor] and [resolveSecondaryColor].
  bool shouldApplyToText({required bool transparentMode}) {
    if (!_hasEnabledTextEffects) return false;
    return transparentMode || _hasCustomTextEffects;
  }

  bool get _hasEnabledTextEffects {
    return outlineEnabled || shadowEnabled;
  }

  bool get _hasCustomTextEffects {
    return outlineEnabled != defaults.outlineEnabled ||
        outlineColor != defaults.outlineColor ||
        outlineWidth != defaults.outlineWidth ||
        shadowEnabled != defaults.shadowEnabled ||
        shadowColor != defaults.shadowColor ||
        shadowBlurRadius != defaults.shadowBlurRadius ||
        shadowOffset != defaults.shadowOffset;
  }

  bool get hasCustomTextColor {
    return textColorCustomized || textColor != defaults.textColor;
  }

  bool get hasCustomSecondaryTextColor {
    return secondaryTextColorCustomized ||
        secondaryTextColor != defaults.secondaryTextColor;
  }

  Color mainColor({required bool isCurrent}) {
    return isCurrent
        ? textColor
        : _withMultipliedAlpha(textColor, inactiveOpacity);
  }

  Color secondaryColor({required bool isCurrent}) {
    return isCurrent
        ? secondaryTextColor
        : _withMultipliedAlpha(secondaryTextColor, inactiveOpacity * 0.8);
  }

  Color resolveMainColor({
    required bool isCurrent,
    required bool transparentMode,
    required Color fallbackCurrentColor,
    required Color fallbackInactiveColor,
  }) {
    if (transparentMode || hasCustomTextColor) {
      return mainColor(isCurrent: isCurrent);
    }
    if (!isCurrent && inactiveOpacity != defaults.inactiveOpacity) {
      return fallbackCurrentColor.withValues(alpha: inactiveOpacity);
    }
    return isCurrent ? fallbackCurrentColor : fallbackInactiveColor;
  }

  Color resolveSecondaryColor({
    required bool isCurrent,
    required bool transparentMode,
    required Color fallbackCurrentColor,
    required Color fallbackInactiveColor,
  }) {
    if (transparentMode || hasCustomSecondaryTextColor) {
      return secondaryColor(isCurrent: isCurrent);
    }
    if (!isCurrent && inactiveOpacity != defaults.inactiveOpacity) {
      return fallbackCurrentColor.withValues(alpha: inactiveOpacity * 0.8);
    }
    return isCurrent ? fallbackCurrentColor : fallbackInactiveColor;
  }

  List<Shadow>? get shadows {
    if (!shadowEnabled) return null;
    return [
      Shadow(
        color: shadowColor,
        blurRadius: shadowBlurRadius,
        offset: shadowOffset,
      ),
    ];
  }

  @override
  bool operator ==(Object other) {
    return other is LyricsWindowStyle &&
        other.textColor == textColor &&
        other.textColorCustomized == textColorCustomized &&
        other.secondaryTextColor == secondaryTextColor &&
        other.secondaryTextColorCustomized == secondaryTextColorCustomized &&
        other.inactiveOpacity == inactiveOpacity &&
        other.outlineEnabled == outlineEnabled &&
        other.outlineColor == outlineColor &&
        other.outlineWidth == outlineWidth &&
        other.shadowEnabled == shadowEnabled &&
        other.shadowColor == shadowColor &&
        other.shadowBlurRadius == shadowBlurRadius &&
        other.shadowOffset == shadowOffset;
  }

  @override
  int get hashCode => Object.hash(
        textColor,
        textColorCustomized,
        secondaryTextColor,
        secondaryTextColorCustomized,
        inactiveOpacity,
        outlineEnabled,
        outlineColor,
        outlineWidth,
        shadowEnabled,
        shadowColor,
        shadowBlurRadius,
        shadowOffset,
      );
}

Color _colorOrDefault(int? value, Color fallback) {
  return value == null ? fallback : Color(value);
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}

Color _withMultipliedAlpha(Color color, double multiplier) {
  final alpha = ((color.toARGB32() >> 24) & 0xff) / 255.0;
  return color.withValues(
    alpha: (alpha * multiplier).clamp(0.0, 1.0).toDouble(),
  );
}
