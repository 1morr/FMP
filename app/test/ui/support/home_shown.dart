import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:material_ui/material_ui.dart';

/// 首頁是畫面上那一頁（不是被別的目的地或內頁蓋住）。量頁頂的標題列，不量中心：空的首頁
/// 「我的歌單」那排「建立歌單」在上、說明置中在下面剩下的空間（U PR 12），頁面中心落在兩者
/// 之間的空白，什麼都點不到。
final homeShown = find.byType(HomePage).hitTestable(at: Alignment.topCenter);
