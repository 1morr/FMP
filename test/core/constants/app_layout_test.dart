import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/ui_constants.dart';

void main() {
  group('AppLayout.detailPanelWidthFor', () {
    test('keeps a stored width that already fits the ratio', () {
      // 1700 × 0.4 = 680，存下來的 412 遠低於上限，原樣通過。
      expect(AppLayout.detailPanelWidthFor(412, 1700), 412);
    });

    test('caps by the window ratio instead of an absolute pixel limit', () {
      // 這正是舊模型做不到的兩件事：小視窗上 500dp 太寬、大視窗上 500dp 太窄。
      expect(AppLayout.detailPanelWidthFor(500, 1000), 400);
      expect(AppLayout.detailPanelWidthFor(900, 3440), 900);
    });

    test('lifts a stored width that is below the minimum', () {
      expect(AppLayout.detailPanelWidthFor(280, 1700), 320);
    });

    test('the minimum wins when the ratio cannot even reach it', () {
      // 700 × 0.4 = 280 < 320。面板寧可超出比例也不能擠成看不了 —— 版面層
      // 決定要不要顯示面板，這個函式只回答「顯示的話該多寬」。
      expect(AppLayout.detailPanelWidthFor(412, 700), 320);
    });

    test('the model is self-consistent at the expanded lower bound', () {
      // 840 × 0.4 = 336，剛好高於下限 320。
      expect(AppLayout.detailPanelWidthFor(AppLayout.detailPanelDefault, 840),
          336);
    });

    test('falls back to the default when the stored value is not finite', () {
      // Isar 對從未寫過的 double 欄位回 NaN，而 NaN 通不過任何比較。
      expect(AppLayout.detailPanelWidthFor(double.nan, 1700), 412);
      expect(AppLayout.detailPanelWidthFor(double.infinity, 1700), 412);
    });
  });

  test('AppSpacing is the 4/8/12/16/24/32 scale', () {
    expect(
      [
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ],
      [4.0, 8.0, 12.0, 16.0, 24.0, 32.0],
    );
  });
}
