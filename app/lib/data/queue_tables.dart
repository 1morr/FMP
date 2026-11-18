import 'package:drift/drift.dart';
import 'package:fmp/domain/queue.dart';

/// 佇列的每個位置（`Queue.entries`），一列一個。曲目 id 存在這裡，改插件的
/// id 格式時要寫資料 migration（brief〈插件〉）。
@DataClassName('QueueEntryRow')
class QueueEntries extends Table {
  /// `QueueEntry.id`。
  IntColumn get entryId => integer()();

  /// 在播放順序的位置，從 0 起。
  IntColumn get playOrder => integer()();

  /// 隨機時在原順序的位置，從 0 起；不隨機時，或隨機時拖動過、用「下一首
  /// 播放」插進來的位置（關掉隨機後不回原位）是 null。
  IntColumn get originalOrder => integer().nullable()();

  TextColumn get pluginId => text()();
  TextColumn get trackId => text()();
  TextColumn get title => text()();
  TextColumn get author => text()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get coverUrl => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {entryId};
}

/// 佇列的其他狀態與進度，只有一列（[id] 是 0）。
@DataClassName('QueueStateRow')
class QueueStates extends Table {
  IntColumn get id => integer()();

  /// 目前那首的 `QueueEntry.id`；沒有目前那首是 null。
  IntColumn get currentEntryId => integer().nullable()();

  /// 下一個加入的位置用的 `QueueEntry.id`。
  IntColumn get nextEntryId => integer()();

  BoolColumn get shuffled => boolean()();
  TextColumn get repeat => textEnum<Repeat>()();

  /// 目前那首播到哪裡（毫秒）。
  IntColumn get positionMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
