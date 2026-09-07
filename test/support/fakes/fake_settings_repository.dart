import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';

import 'fake_isar.dart';

/// 一個記憶體裡的 [SettingsRepository]：`get` 回同一個 [Settings] 實例，
/// `update` 就地改它再回傳。
///
/// 測試因此可以直接讀那個實例斷言，不必再查一次資料庫。建構子拿的是
/// [FakeIsar] —— 每個真的會走到資料庫的成員都被覆寫掉了。
class FakeSettingsRepository extends SettingsRepository {
  FakeSettingsRepository(this.settings) : super(FakeIsar());

  final Settings settings;

  @override
  Future<Settings> get() async => settings;

  @override
  Future<Settings> update(void Function(Settings settings) mutate) async {
    mutate(settings);
    return settings;
  }
}
