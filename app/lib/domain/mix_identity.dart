import 'package:flutter/foundation.dart';

/// 一個 Mix（ADR 0028 §決定 4、ADR 0031 §決定 11）：身分是（[pluginId], [mixId]），
/// [title] 顯示在佇列頁，[cursor] 是插件的不透明字串，`null` 表示這個 Mix 沒有更多
/// （下一次補歌改以佇列最後一首當種子開新的一批）。
///
/// 放在 `domain/`：佇列持久化時資料層要存它（`player_state` 的 `mix_*`）。
@immutable
final class MixIdentity {
  const MixIdentity({
    required this.pluginId,
    required this.mixId,
    required this.title,
    this.cursor,
  });

  final String pluginId;
  final String mixId;
  final String title;
  final String? cursor;

  MixIdentity copyWith({
    String? mixId,
    String? title,
    String? cursor,
    bool clearCursor = false,
  }) => MixIdentity(
    pluginId: pluginId,
    mixId: mixId ?? this.mixId,
    title: title ?? this.title,
    cursor: clearCursor ? null : cursor ?? this.cursor,
  );

  @override
  bool operator ==(Object other) =>
      other is MixIdentity &&
      other.pluginId == pluginId &&
      other.mixId == mixId &&
      other.title == title &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(pluginId, mixId, title, cursor);

  @override
  String toString() =>
      'MixIdentity($pluginId:$mixId, title: $title, cursor: $cursor)';
}
