import 'package:isar/isar.dart';

part 'search_history.g.dart';

/// 搜索历史实体
@collection
class SearchHistory {
  Id id = Isar.autoIncrement;

  /// 搜索关键词
  @Index()
  late String query;

  /// 搜索时间
  @Index()
  DateTime timestamp = DateTime.now();

  @override
  String toString() => 'SearchHistory(query: $query, timestamp: $timestamp)';
}
