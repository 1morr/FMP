import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:fmp/domain/appearance.dart';

var _initialized = false;

/// 日期（年月日），依介面語言寫成 `2024年5月17日`、`May 17, 2024`（CLDR 的 `yMMMd`），
/// 顯示在本機時區。
String formatDate(LocaleSetting locale, DateTime date) =>
    _format(locale, DateFormat.yMMMd, date);

/// 日期加時間（`2024年5月17日 14:30`、`May 17, 2024, 2:30 PM`），顯示在本機時區。
String formatDateTime(LocaleSetting locale, DateTime date) =>
    _format(locale, (name) => DateFormat.yMMMd(name).add_jm(), date);

String _format(
  LocaleSetting locale,
  DateFormat Function(String name) format,
  DateTime date,
) {
  if (!_initialized) {
    // 以內建資料初始化，同步完成；回傳的 Future 沒有東西可等。
    initializeDateFormatting();
    _initialized = true;
  }
  return format(switch (locale) {
    LocaleSetting.zhTw => 'zh_TW',
    LocaleSetting.zhCn => 'zh_CN',
    LocaleSetting.en => 'en',
  }).format(date.toLocal());
}
