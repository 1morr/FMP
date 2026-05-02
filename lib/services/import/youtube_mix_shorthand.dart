const int youtubeMixShorthandMaxSeedLength = 64;
final RegExp _youtubeMixSeedIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

bool looksLikeYouTubeMixShorthand(String input) {
  return input.trim().toLowerCase().startsWith('mix:');
}

String? parseYouTubeMixShorthandSeedId(String input) {
  final trimmed = input.trim();
  if (!looksLikeYouTubeMixShorthand(trimmed)) return null;

  final seedId = trimmed.substring(4).trim();
  if (seedId.isEmpty || seedId.length > youtubeMixShorthandMaxSeedLength) {
    return null;
  }
  if (!_youtubeMixSeedIdPattern.hasMatch(seedId)) return null;
  return seedId;
}

String? normalizeYouTubeMixShorthandUrl(String input) {
  final seedId = parseYouTubeMixShorthandSeedId(input);
  if (seedId == null) return null;
  return 'https://www.youtube.com/watch?v=$seedId&list=RD$seedId';
}
