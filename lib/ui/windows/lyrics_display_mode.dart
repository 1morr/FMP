import 'package:flutter/material.dart';

/// 歌詞顯示模式：原圖 / 偏好翻譯 / 偏好羅馬拼音。
///
/// [modeIndex] 為跨視窗 IPC 的線傳值（0/1/2），刻意對齊 host 端
/// `LyricsWindowService` 的合約；改變數值須同步兩端。本 enum 取代
/// `lyrics_window.dart` 原本的裸 `int _displayModeIndex` 與散落的 inline
/// switch（C1c），讓循環邏輯與圖示對應可單獨測試。
enum LyricsDisplayMode {
  original(0, Icons.title),
  preferTranslated(1, Icons.translate),
  preferRomaji(2, Icons.abc);

  const LyricsDisplayMode(this.modeIndex, this.icon);

  /// IPC 線傳值（與 host 端合約一致，須為 0..n-1 連續）。
  final int modeIndex;

  /// 工具列圖示。
  final IconData icon;

  /// 由 IPC 線傳值還原為 enum；越界或缺值退回 [original]（寬容解析）。
  static LyricsDisplayMode fromIndex(int? index) {
    for (final mode in values) {
      if (mode.modeIndex == index) return mode;
    }
    return LyricsDisplayMode.original;
  }

  /// 循環切換：original → preferTranslated → preferRomaji → original。
  LyricsDisplayMode get next => fromIndex((modeIndex + 1) % values.length);
}
