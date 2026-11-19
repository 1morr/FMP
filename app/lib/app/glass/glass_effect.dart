import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/data/settings_store.dart';

/// 玻璃的三級（`docs/design/DESIGN.md`〈三級與平台〉），由低到高排。設定「外觀 ›
/// 玻璃效果」的關閉、輕量、完整依序是 [minimal]、[standard]、[refract]。
enum GlassTier {
  /// 自己畫的實心填色，沒有 backdrop。
  minimal,

  /// 模糊加填色，沒有折射。
  standard,

  /// 折射、模糊與填色。
  refract;

  /// 不高過 [cap] 的一級；[cap] 是 null 時是自己。
  GlassTier atMost(GlassTier? cap) =>
      cap == null || cap.index >= index ? this : cap;
}

/// App 層級的「玻璃效果」（設定「外觀 › 玻璃效果」）：所有玻璃一起切換。
final glassEffectProvider = NotifierProvider<GlassEffect, GlassTier>(
  GlassEffect.new,
);

class GlassEffect extends EnumSetting<GlassTier> {
  @override
  String get key => 'appearance.glass';

  /// 預設「完整」（brief〈介面〉）。
  @override
  GlassTier get fallback => GlassTier.refract;

  @override
  List<GlassTier> get values => GlassTier.values;

  /// 照設定的選項名（完整、輕量、關閉）存，不跟玻璃元件的級名。
  @override
  String encode(GlassTier value) => switch (value) {
    GlassTier.refract => 'full',
    GlassTier.standard => 'lite',
    GlassTier.minimal => 'off',
  };
}
