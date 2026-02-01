import 'package:isar/isar.dart';
import '../models/radio_station.dart';
import '../models/track.dart';

/// RadioStation 數據倉庫
class RadioRepository {
  final Isar _isar;

  RadioRepository(this._isar);

  /// 獲取所有電台（按排序順序）
  Future<List<RadioStation>> getAll() async {
    return _isar.radioStations.where().sortBySortOrder().findAll();
  }

  /// 根據 ID 獲取電台
  Future<RadioStation?> getById(int id) async {
    return _isar.radioStations.get(id);
  }

  /// 根據 URL 獲取電台
  Future<RadioStation?> getByUrl(String url) async {
    return _isar.radioStations.where().urlEqualTo(url).findFirst();
  }

  /// 根據源 ID 獲取電台
  Future<RadioStation?> getBySourceId(SourceType sourceType, String sourceId) async {
    return _isar.radioStations
        .filter()
        .sourceTypeEqualTo(sourceType)
        .and()
        .sourceIdEqualTo(sourceId)
        .findFirst();
  }

  /// 檢查電台是否已存在（按源類型和源ID）
  Future<bool> exists(SourceType sourceType, String sourceId) async {
    final station = await getBySourceId(sourceType, sourceId);
    return station != null;
  }

  /// 保存電台（新增或更新）
  Future<int> save(RadioStation station) async {
    return _isar.writeTxn(() => _isar.radioStations.put(station));
  }

  /// 批量保存電台
  Future<List<int>> saveAll(List<RadioStation> stations) async {
    return _isar.writeTxn(() => _isar.radioStations.putAll(stations));
  }

  /// 刪除電台
  Future<bool> delete(int id) async {
    return _isar.writeTxn(() => _isar.radioStations.delete(id));
  }

  /// 批量刪除電台
  Future<int> deleteAll(List<int> ids) async {
    return _isar.writeTxn(() => _isar.radioStations.deleteAll(ids));
  }

  /// 更新最後播放時間
  Future<void> updateLastPlayed(int id) async {
    final station = await getById(id);
    if (station != null) {
      station.lastPlayedAt = DateTime.now();
      await save(station);
    }
  }

  /// 切換收藏狀態
  Future<void> toggleFavorite(int id) async {
    final station = await getById(id);
    if (station != null) {
      station.isFavorite = !station.isFavorite;
      await save(station);
    }
  }

  /// 重新排序電台
  Future<void> reorder(List<int> newOrder) async {
    await _isar.writeTxn(() async {
      for (int i = 0; i < newOrder.length; i++) {
        final station = await _isar.radioStations.get(newOrder[i]);
        if (station != null) {
          station.sortOrder = i;
          await _isar.radioStations.put(station);
        }
      }
    });
  }

  /// 獲取下一個排序順序值
  Future<int> getNextSortOrder() async {
    final stations = await getAll();
    if (stations.isEmpty) return 0;
    return stations.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  /// 獲取收藏的電台
  Future<List<RadioStation>> getFavorites() async {
    return _isar.radioStations
        .filter()
        .isFavoriteEqualTo(true)
        .sortBySortOrder()
        .findAll();
  }

  /// 監聽電台列表變化
  Stream<List<RadioStation>> watchAll() {
    return _isar.radioStations
        .where()
        .sortBySortOrder()
        .watch(fireImmediately: true);
  }

  /// 監聽單個電台變化
  Stream<RadioStation?> watchById(int id) {
    return _isar.radioStations.watchObject(id, fireImmediately: true);
  }
}
