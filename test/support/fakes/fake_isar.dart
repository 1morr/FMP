import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

/// 只為了滿足建構子的 [Isar] 佔位。
///
/// 有些 repository 的建構子要一個 `Isar`，但測試根本不碰資料庫（例如
/// `FakeSettingsRepository` 把每個查詢都覆寫掉了）。真的開一個 Isar 只是讓
/// 測試變慢，而且要負責關掉它。任何真的走到資料庫的呼叫都會拋
/// `NoSuchMethodError` —— 那正是要的：這個替身用不到就不該被碰。
class FakeIsar extends Fake implements Isar {}
