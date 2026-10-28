import 'package:fmp/platform/fonts/fonts.dart';

/// macOS：指名系統字型。
///
/// 不指名時預設字型（San Francisco）沒有 CJK 字元，引擎自己挑的 fallback 會混到日文
/// 字型、字重也不一致（同 Windows 的情形，flutter/flutter#103811）。繁中用蘋方-繁，
/// 簡中用蘋方-簡。
const macosFontFallback = FontFallback(
  traditionalChinese: ['PingFang TC'],
  simplifiedChinese: ['PingFang SC'],
);

/// macOS 外觀設定可選的字型：繁中為主（ADR 0035 §決定 5），再加簡中與日文各一個。
const macosFontChoices = ['PingFang TC', 'PingFang SC', 'Hiragino Sans'];
