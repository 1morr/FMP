/// 曲目（`GLOSSARY.md`）：音源上的一首可播放音訊，由 [source] 和 [id]
/// 確定。
class Track {
  const Track({
    required this.source,
    required this.id,
    required this.title,
    required this.author,
    this.duration,
  });

  /// 提供它的插件的 id。
  final String source;

  /// 曲目在音源內的識別碼；格式由插件決定，宿主不解讀。
  final String id;

  final String title;

  /// 作者（`GLOSSARY.md`）：曲目在音源上掛名的人或頻道，由插件決定放哪個。
  final String author;

  /// 插件不知道時是 null。
  final Duration? duration;

  /// log 用的 `<插件 id>/<曲目 id>`。
  String get logId => '$source/$id';

  @override
  bool operator ==(Object other) =>
      other is Track &&
      other.source == source &&
      other.id == id &&
      other.title == title &&
      other.author == author &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(source, id, title, author, duration);

  @override
  String toString() => 'Track($source, $id, $title, $author, $duration)';
}
