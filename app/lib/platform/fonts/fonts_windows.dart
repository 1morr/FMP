import 'package:fmp/platform/fonts/fonts.dart';

/// Windows：指名系統字型。
///
/// 引擎在 Windows 用 DirectWrite 的字型管理器，`fontFamilyFallback` 的名稱
/// 對得到系統字型。不指名時預設字型 `Segoe UI` 沒有 CJK 字元，引擎自己挑的
/// fallback 會混到 `Yu Gothic UI` 等日文字型、字重也不一致
/// （flutter/flutter#103811）。來源與推導見
/// `.trellis/tasks/archive/2026-09/09-29-platform-layer/research/notes.md`。
const windowsFontFallback = FontFallback(
  traditionalChinese: ['Microsoft JhengHei UI', 'Microsoft JhengHei'],
  simplifiedChinese: ['Microsoft YaHei UI', 'Microsoft YaHei'],
);
