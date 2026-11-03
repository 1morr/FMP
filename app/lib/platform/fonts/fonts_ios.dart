import 'package:fmp/platform/fonts/fonts.dart';

/// iOS：指名系統字型，理由同 macOS（預設 San Francisco 沒有 CJK，引擎挑的 fallback 會混到日文
/// 字型，flutter/flutter#103811）。繁中蘋方-繁，簡中蘋方-簡。
const iosFontFallback = FontFallback(
  traditionalChinese: ['PingFang TC'],
  simplifiedChinese: ['PingFang SC'],
);

/// iOS 外觀設定可選的字型（ADR 0035 §決定 5）。
const iosFontChoices = ['PingFang TC', 'PingFang SC', 'Hiragino Sans'];
