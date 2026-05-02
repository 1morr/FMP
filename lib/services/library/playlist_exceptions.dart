import 'package:fmp/i18n/strings.g.dart';

class PlaylistNameExistsException implements Exception {
  final String name;
  const PlaylistNameExistsException(this.name);

  @override
  String toString() => t.importSource.playlistNameExists(name: name);
}

class PlaylistNotFoundException implements Exception {
  final int playlistId;
  const PlaylistNotFoundException(this.playlistId);

  @override
  String toString() =>
      t.importSource.playlistIdNotFound(id: playlistId.toString());
}
