import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// App 層級的「玻璃效果」：所有玻璃一起切換。設定頁接上 drift 之前只在
/// 記憶體裡。
final glassEffectProvider = NotifierProvider<GlassEffect, GlassTier>(
  GlassEffect.new,
);

class GlassEffect extends Notifier<GlassTier> {
  /// 預設「完整」（brief〈介面〉）。
  @override
  GlassTier build() => GlassTier.refract;

  void set(GlassTier tier) => state = tier;
}
