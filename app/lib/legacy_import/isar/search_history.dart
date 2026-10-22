import 'package:isar_community/isar.dart';

part 'search_history.g.dart';

@collection
class SearchHistory {
  Id id = Isar.autoIncrement;

  @Index()
  late String query;

  @Index()
  DateTime timestamp = DateTime.now();
}
