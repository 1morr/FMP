/// 曲目（`GLOSSARY.md`）的身分：提供它的插件 id 加曲目 id。佇列、臨時播放、
/// 持久化與系統媒體控制都拿它當鍵；找插件、寫 log 都從它來，不單獨傳
/// 插件 id。
class TrackRef {
  const TrackRef({required this.pluginId, required this.trackId});

  /// 提供這首曲目的插件的 id（manifest 的 `id`）。
  final String pluginId;

  /// 曲目在音源內的識別碼；格式由插件決定，宿主不解讀，只交回同一個插件。
  final String trackId;

  /// log 用的 `<插件 id>/<曲目 id>`。
  String get logId => '$pluginId/$trackId';

  @override
  bool operator ==(Object other) =>
      other is TrackRef &&
      other.pluginId == pluginId &&
      other.trackId == trackId;

  @override
  int get hashCode => Object.hash(pluginId, trackId);

  @override
  String toString() => logId;
}

/// 曲目（`GLOSSARY.md`）：音源上的一首可播放音訊，由 [ref] 確定。
class Track {
  const Track({
    required this.ref,
    required this.title,
    required this.author,
    this.duration,
  });

  final TrackRef ref;

  final String title;

  /// 作者（`GLOSSARY.md`）：曲目在音源上掛名的人或頻道，由插件決定放哪個。
  final String author;

  /// 插件不知道時是 null。
  final Duration? duration;

  @override
  bool operator ==(Object other) =>
      other is Track &&
      other.ref == ref &&
      other.title == title &&
      other.author == author &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(ref, title, author, duration);

  @override
  String toString() => 'Track($ref, $title, $author, $duration)';
}
