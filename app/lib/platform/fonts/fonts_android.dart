import 'package:fmp/platform/fonts/fonts.dart';

/// Android：不指名字型，繁簡字形交給引擎依文字的 locale 挑選。
///
/// 系統的 Noto Sans CJK 在 `/system/etc/fonts.xml` 裡是沒有名稱、只標
/// `lang="zh-Hans"`／`lang="zh-Hant,zh-Bopo"` 的 fallback family；引擎的
/// Android 字型管理器（Skia `SkFontMgr_Android`）只以名稱比對有名稱的
/// family，所以寫 `Noto Sans TC` 對不到任何字型（ADR 0024 §決定 2 的更正）。
/// 文字帶 `zh-Hant` 的 locale 時，模擬器實測拿到繁中字形（2026-09-29）；
/// 來源與實測見 `.trellis/tasks/archive/2026-09/09-29-platform-layer/research/notes.md`。
const androidFontFallback = FontFallback.none;
