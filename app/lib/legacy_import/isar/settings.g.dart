// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetSettingsCollection on Isar {
  IsarCollection<Settings> get settings => this.collection();
}

const SettingsSchema = CollectionSchema(
  name: r'Settings',
  id: -8656046621518759136,
  properties: {
    r'allowPlainLyricsAutoMatch': PropertySchema(
      id: 0,
      name: r'allowPlainLyricsAutoMatch',
      type: IsarType.bool,
    ),
    r'audioFormatPriority': PropertySchema(
      id: 1,
      name: r'audioFormatPriority',
      type: IsarType.string,
    ),
    r'audioQualityLevelIndex': PropertySchema(
      id: 2,
      name: r'audioQualityLevelIndex',
      type: IsarType.long,
    ),
    r'autoMatchLyrics': PropertySchema(
      id: 3,
      name: r'autoMatchLyrics',
      type: IsarType.bool,
    ),
    r'autoScrollToCurrentTrack': PropertySchema(
      id: 4,
      name: r'autoScrollToCurrentTrack',
      type: IsarType.bool,
    ),
    r'bilibiliStreamPriority': PropertySchema(
      id: 5,
      name: r'bilibiliStreamPriority',
      type: IsarType.string,
    ),
    r'customDownloadDir': PropertySchema(
      id: 6,
      name: r'customDownloadDir',
      type: IsarType.string,
    ),
    r'detailPanelExpanded': PropertySchema(
      id: 7,
      name: r'detailPanelExpanded',
      type: IsarType.bool,
    ),
    r'detailPanelWidth': PropertySchema(
      id: 8,
      name: r'detailPanelWidth',
      type: IsarType.double,
    ),
    r'disabledHomeRankingSources': PropertySchema(
      id: 9,
      name: r'disabledHomeRankingSources',
      type: IsarType.string,
    ),
    r'disabledLyricsSources': PropertySchema(
      id: 10,
      name: r'disabledLyricsSources',
      type: IsarType.string,
    ),
    r'downloadImageOptionIndex': PropertySchema(
      id: 11,
      name: r'downloadImageOptionIndex',
      type: IsarType.long,
    ),
    r'enableGlobalHotkeys': PropertySchema(
      id: 12,
      name: r'enableGlobalHotkeys',
      type: IsarType.bool,
    ),
    r'fontFamily': PropertySchema(
      id: 13,
      name: r'fontFamily',
      type: IsarType.string,
    ),
    r'homeRankingSourcePriority': PropertySchema(
      id: 14,
      name: r'homeRankingSourcePriority',
      type: IsarType.string,
    ),
    r'hotkeyConfig': PropertySchema(
      id: 15,
      name: r'hotkeyConfig',
      type: IsarType.string,
    ),
    r'launchAtStartup': PropertySchema(
      id: 16,
      name: r'launchAtStartup',
      type: IsarType.bool,
    ),
    r'launchMinimized': PropertySchema(
      id: 17,
      name: r'launchMinimized',
      type: IsarType.bool,
    ),
    r'locale': PropertySchema(id: 18, name: r'locale', type: IsarType.string),
    r'lyricsAiEndpoint': PropertySchema(
      id: 19,
      name: r'lyricsAiEndpoint',
      type: IsarType.string,
    ),
    r'lyricsAiModel': PropertySchema(
      id: 20,
      name: r'lyricsAiModel',
      type: IsarType.string,
    ),
    r'lyricsAiTimeoutSeconds': PropertySchema(
      id: 21,
      name: r'lyricsAiTimeoutSeconds',
      type: IsarType.long,
    ),
    r'lyricsAiTitleParsingModeIndex': PropertySchema(
      id: 22,
      name: r'lyricsAiTitleParsingModeIndex',
      type: IsarType.long,
    ),
    r'lyricsDisplayModeIndex': PropertySchema(
      id: 23,
      name: r'lyricsDisplayModeIndex',
      type: IsarType.long,
    ),
    r'lyricsSourcePriority': PropertySchema(
      id: 24,
      name: r'lyricsSourcePriority',
      type: IsarType.string,
    ),
    r'lyricsWindowInactiveTextOpacity': PropertySchema(
      id: 25,
      name: r'lyricsWindowInactiveTextOpacity',
      type: IsarType.double,
    ),
    r'lyricsWindowOutlineColor': PropertySchema(
      id: 26,
      name: r'lyricsWindowOutlineColor',
      type: IsarType.long,
    ),
    r'lyricsWindowOutlineEnabled': PropertySchema(
      id: 27,
      name: r'lyricsWindowOutlineEnabled',
      type: IsarType.bool,
    ),
    r'lyricsWindowOutlineWidth': PropertySchema(
      id: 28,
      name: r'lyricsWindowOutlineWidth',
      type: IsarType.double,
    ),
    r'lyricsWindowSecondaryTextColor': PropertySchema(
      id: 29,
      name: r'lyricsWindowSecondaryTextColor',
      type: IsarType.long,
    ),
    r'lyricsWindowShadowBlurRadius': PropertySchema(
      id: 30,
      name: r'lyricsWindowShadowBlurRadius',
      type: IsarType.double,
    ),
    r'lyricsWindowShadowColor': PropertySchema(
      id: 31,
      name: r'lyricsWindowShadowColor',
      type: IsarType.long,
    ),
    r'lyricsWindowShadowEnabled': PropertySchema(
      id: 32,
      name: r'lyricsWindowShadowEnabled',
      type: IsarType.bool,
    ),
    r'lyricsWindowShadowOffsetX': PropertySchema(
      id: 33,
      name: r'lyricsWindowShadowOffsetX',
      type: IsarType.double,
    ),
    r'lyricsWindowShadowOffsetY': PropertySchema(
      id: 34,
      name: r'lyricsWindowShadowOffsetY',
      type: IsarType.double,
    ),
    r'lyricsWindowTextColor': PropertySchema(
      id: 35,
      name: r'lyricsWindowTextColor',
      type: IsarType.long,
    ),
    r'maxCacheSizeMB': PropertySchema(
      id: 36,
      name: r'maxCacheSizeMB',
      type: IsarType.long,
    ),
    r'maxConcurrentDownloads': PropertySchema(
      id: 37,
      name: r'maxConcurrentDownloads',
      type: IsarType.long,
    ),
    r'maxLyricsCacheFiles': PropertySchema(
      id: 38,
      name: r'maxLyricsCacheFiles',
      type: IsarType.long,
    ),
    r'minimizeToTrayOnClose': PropertySchema(
      id: 39,
      name: r'minimizeToTrayOnClose',
      type: IsarType.bool,
    ),
    r'neteaseStreamPriority': PropertySchema(
      id: 40,
      name: r'neteaseStreamPriority',
      type: IsarType.string,
    ),
    r'playHistoryLimit': PropertySchema(
      id: 41,
      name: r'playHistoryLimit',
      type: IsarType.long,
    ),
    r'preferredAudioDeviceId': PropertySchema(
      id: 42,
      name: r'preferredAudioDeviceId',
      type: IsarType.string,
    ),
    r'preferredAudioDeviceName': PropertySchema(
      id: 43,
      name: r'preferredAudioDeviceName',
      type: IsarType.string,
    ),
    r'primaryColor': PropertySchema(
      id: 44,
      name: r'primaryColor',
      type: IsarType.long,
    ),
    r'radioRefreshIntervalMinutes': PropertySchema(
      id: 45,
      name: r'radioRefreshIntervalMinutes',
      type: IsarType.long,
    ),
    r'railExpanded': PropertySchema(
      id: 46,
      name: r'railExpanded',
      type: IsarType.bool,
    ),
    r'rankingRefreshIntervalMinutes': PropertySchema(
      id: 47,
      name: r'rankingRefreshIntervalMinutes',
      type: IsarType.long,
    ),
    r'rememberPlaybackPosition': PropertySchema(
      id: 48,
      name: r'rememberPlaybackPosition',
      type: IsarType.bool,
    ),
    r'restartRewindSeconds': PropertySchema(
      id: 49,
      name: r'restartRewindSeconds',
      type: IsarType.long,
    ),
    r'schemaVersion': PropertySchema(
      id: 50,
      name: r'schemaVersion',
      type: IsarType.long,
    ),
    r'sourceSettings': PropertySchema(
      id: 51,
      name: r'sourceSettings',
      type: IsarType.objectList,
      target: r'SourceSettingsEntry',
    ),
    r'tempPlayRewindSeconds': PropertySchema(
      id: 52,
      name: r'tempPlayRewindSeconds',
      type: IsarType.long,
    ),
    r'themeModeIndex': PropertySchema(
      id: 53,
      name: r'themeModeIndex',
      type: IsarType.long,
    ),
    r'useBilibiliAuthForPlay': PropertySchema(
      id: 54,
      name: r'useBilibiliAuthForPlay',
      type: IsarType.bool,
    ),
    r'useNeteaseAuthForPlay': PropertySchema(
      id: 55,
      name: r'useNeteaseAuthForPlay',
      type: IsarType.bool,
    ),
    r'useYoutubeAuthForPlay': PropertySchema(
      id: 56,
      name: r'useYoutubeAuthForPlay',
      type: IsarType.bool,
    ),
    r'youtubeStreamPriority': PropertySchema(
      id: 57,
      name: r'youtubeStreamPriority',
      type: IsarType.string,
    ),
  },
  estimateSize: _settingsEstimateSize,
  serialize: _settingsSerialize,
  deserialize: _settingsDeserialize,
  deserializeProp: _settingsDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {r'SourceSettingsEntry': SourceSettingsEntrySchema},
  getId: _settingsGetId,
  getLinks: _settingsGetLinks,
  attach: _settingsAttach,
  version: '3.3.2',
);

int _settingsEstimateSize(
  Settings object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.audioFormatPriority.length * 3;
  bytesCount += 3 + object.bilibiliStreamPriority.length * 3;
  {
    final value = object.customDownloadDir;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.disabledHomeRankingSources.length * 3;
  bytesCount += 3 + object.disabledLyricsSources.length * 3;
  {
    final value = object.fontFamily;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.homeRankingSourcePriority.length * 3;
  {
    final value = object.hotkeyConfig;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.locale;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.lyricsAiEndpoint.length * 3;
  bytesCount += 3 + object.lyricsAiModel.length * 3;
  bytesCount += 3 + object.lyricsSourcePriority.length * 3;
  bytesCount += 3 + object.neteaseStreamPriority.length * 3;
  {
    final value = object.preferredAudioDeviceId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.preferredAudioDeviceName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.sourceSettings.length * 3;
  {
    final offsets = allOffsets[SourceSettingsEntry]!;
    for (var i = 0; i < object.sourceSettings.length; i++) {
      final value = object.sourceSettings[i];
      bytesCount += SourceSettingsEntrySchema.estimateSize(
        value,
        offsets,
        allOffsets,
      );
    }
  }
  bytesCount += 3 + object.youtubeStreamPriority.length * 3;
  return bytesCount;
}

void _settingsSerialize(
  Settings object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeBool(offsets[0], object.allowPlainLyricsAutoMatch);
  writer.writeString(offsets[1], object.audioFormatPriority);
  writer.writeLong(offsets[2], object.audioQualityLevelIndex);
  writer.writeBool(offsets[3], object.autoMatchLyrics);
  writer.writeBool(offsets[4], object.autoScrollToCurrentTrack);
  writer.writeString(offsets[5], object.bilibiliStreamPriority);
  writer.writeString(offsets[6], object.customDownloadDir);
  writer.writeBool(offsets[7], object.detailPanelExpanded);
  writer.writeDouble(offsets[8], object.detailPanelWidth);
  writer.writeString(offsets[9], object.disabledHomeRankingSources);
  writer.writeString(offsets[10], object.disabledLyricsSources);
  writer.writeLong(offsets[11], object.downloadImageOptionIndex);
  writer.writeBool(offsets[12], object.enableGlobalHotkeys);
  writer.writeString(offsets[13], object.fontFamily);
  writer.writeString(offsets[14], object.homeRankingSourcePriority);
  writer.writeString(offsets[15], object.hotkeyConfig);
  writer.writeBool(offsets[16], object.launchAtStartup);
  writer.writeBool(offsets[17], object.launchMinimized);
  writer.writeString(offsets[18], object.locale);
  writer.writeString(offsets[19], object.lyricsAiEndpoint);
  writer.writeString(offsets[20], object.lyricsAiModel);
  writer.writeLong(offsets[21], object.lyricsAiTimeoutSeconds);
  writer.writeLong(offsets[22], object.lyricsAiTitleParsingModeIndex);
  writer.writeLong(offsets[23], object.lyricsDisplayModeIndex);
  writer.writeString(offsets[24], object.lyricsSourcePriority);
  writer.writeDouble(offsets[25], object.lyricsWindowInactiveTextOpacity);
  writer.writeLong(offsets[26], object.lyricsWindowOutlineColor);
  writer.writeBool(offsets[27], object.lyricsWindowOutlineEnabled);
  writer.writeDouble(offsets[28], object.lyricsWindowOutlineWidth);
  writer.writeLong(offsets[29], object.lyricsWindowSecondaryTextColor);
  writer.writeDouble(offsets[30], object.lyricsWindowShadowBlurRadius);
  writer.writeLong(offsets[31], object.lyricsWindowShadowColor);
  writer.writeBool(offsets[32], object.lyricsWindowShadowEnabled);
  writer.writeDouble(offsets[33], object.lyricsWindowShadowOffsetX);
  writer.writeDouble(offsets[34], object.lyricsWindowShadowOffsetY);
  writer.writeLong(offsets[35], object.lyricsWindowTextColor);
  writer.writeLong(offsets[36], object.maxCacheSizeMB);
  writer.writeLong(offsets[37], object.maxConcurrentDownloads);
  writer.writeLong(offsets[38], object.maxLyricsCacheFiles);
  writer.writeBool(offsets[39], object.minimizeToTrayOnClose);
  writer.writeString(offsets[40], object.neteaseStreamPriority);
  writer.writeLong(offsets[41], object.playHistoryLimit);
  writer.writeString(offsets[42], object.preferredAudioDeviceId);
  writer.writeString(offsets[43], object.preferredAudioDeviceName);
  writer.writeLong(offsets[44], object.primaryColor);
  writer.writeLong(offsets[45], object.radioRefreshIntervalMinutes);
  writer.writeBool(offsets[46], object.railExpanded);
  writer.writeLong(offsets[47], object.rankingRefreshIntervalMinutes);
  writer.writeBool(offsets[48], object.rememberPlaybackPosition);
  writer.writeLong(offsets[49], object.restartRewindSeconds);
  writer.writeLong(offsets[50], object.schemaVersion);
  writer.writeObjectList<SourceSettingsEntry>(
    offsets[51],
    allOffsets,
    SourceSettingsEntrySchema.serialize,
    object.sourceSettings,
  );
  writer.writeLong(offsets[52], object.tempPlayRewindSeconds);
  writer.writeLong(offsets[53], object.themeModeIndex);
  writer.writeBool(offsets[54], object.useBilibiliAuthForPlay);
  writer.writeBool(offsets[55], object.useNeteaseAuthForPlay);
  writer.writeBool(offsets[56], object.useYoutubeAuthForPlay);
  writer.writeString(offsets[57], object.youtubeStreamPriority);
}

Settings _settingsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Settings();
  object.allowPlainLyricsAutoMatch = reader.readBool(offsets[0]);
  object.audioFormatPriority = reader.readString(offsets[1]);
  object.audioQualityLevelIndex = reader.readLong(offsets[2]);
  object.autoMatchLyrics = reader.readBool(offsets[3]);
  object.autoScrollToCurrentTrack = reader.readBool(offsets[4]);
  object.bilibiliStreamPriority = reader.readString(offsets[5]);
  object.customDownloadDir = reader.readStringOrNull(offsets[6]);
  object.detailPanelExpanded = reader.readBool(offsets[7]);
  object.detailPanelWidth = reader.readDouble(offsets[8]);
  object.disabledHomeRankingSources = reader.readString(offsets[9]);
  object.disabledLyricsSources = reader.readString(offsets[10]);
  object.downloadImageOptionIndex = reader.readLong(offsets[11]);
  object.enableGlobalHotkeys = reader.readBool(offsets[12]);
  object.fontFamily = reader.readStringOrNull(offsets[13]);
  object.homeRankingSourcePriority = reader.readString(offsets[14]);
  object.hotkeyConfig = reader.readStringOrNull(offsets[15]);
  object.id = id;
  object.launchAtStartup = reader.readBool(offsets[16]);
  object.launchMinimized = reader.readBool(offsets[17]);
  object.locale = reader.readStringOrNull(offsets[18]);
  object.lyricsAiEndpoint = reader.readString(offsets[19]);
  object.lyricsAiModel = reader.readString(offsets[20]);
  object.lyricsAiTimeoutSeconds = reader.readLong(offsets[21]);
  object.lyricsAiTitleParsingModeIndex = reader.readLong(offsets[22]);
  object.lyricsDisplayModeIndex = reader.readLong(offsets[23]);
  object.lyricsSourcePriority = reader.readString(offsets[24]);
  object.lyricsWindowInactiveTextOpacity = reader.readDoubleOrNull(offsets[25]);
  object.lyricsWindowOutlineColor = reader.readLongOrNull(offsets[26]);
  object.lyricsWindowOutlineEnabled = reader.readBoolOrNull(offsets[27]);
  object.lyricsWindowOutlineWidth = reader.readDoubleOrNull(offsets[28]);
  object.lyricsWindowSecondaryTextColor = reader.readLongOrNull(offsets[29]);
  object.lyricsWindowShadowBlurRadius = reader.readDoubleOrNull(offsets[30]);
  object.lyricsWindowShadowColor = reader.readLongOrNull(offsets[31]);
  object.lyricsWindowShadowEnabled = reader.readBoolOrNull(offsets[32]);
  object.lyricsWindowShadowOffsetX = reader.readDoubleOrNull(offsets[33]);
  object.lyricsWindowShadowOffsetY = reader.readDoubleOrNull(offsets[34]);
  object.lyricsWindowTextColor = reader.readLongOrNull(offsets[35]);
  object.maxCacheSizeMB = reader.readLong(offsets[36]);
  object.maxConcurrentDownloads = reader.readLong(offsets[37]);
  object.maxLyricsCacheFiles = reader.readLong(offsets[38]);
  object.minimizeToTrayOnClose = reader.readBool(offsets[39]);
  object.neteaseStreamPriority = reader.readString(offsets[40]);
  object.playHistoryLimit = reader.readLong(offsets[41]);
  object.preferredAudioDeviceId = reader.readStringOrNull(offsets[42]);
  object.preferredAudioDeviceName = reader.readStringOrNull(offsets[43]);
  object.primaryColor = reader.readLongOrNull(offsets[44]);
  object.radioRefreshIntervalMinutes = reader.readLong(offsets[45]);
  object.railExpanded = reader.readBool(offsets[46]);
  object.rankingRefreshIntervalMinutes = reader.readLong(offsets[47]);
  object.rememberPlaybackPosition = reader.readBool(offsets[48]);
  object.restartRewindSeconds = reader.readLong(offsets[49]);
  object.schemaVersion = reader.readLong(offsets[50]);
  object.sourceSettings =
      reader.readObjectList<SourceSettingsEntry>(
        offsets[51],
        SourceSettingsEntrySchema.deserialize,
        allOffsets,
        SourceSettingsEntry(),
      ) ??
      [];
  object.tempPlayRewindSeconds = reader.readLong(offsets[52]);
  object.themeModeIndex = reader.readLong(offsets[53]);
  object.useBilibiliAuthForPlay = reader.readBool(offsets[54]);
  object.useNeteaseAuthForPlay = reader.readBool(offsets[55]);
  object.useYoutubeAuthForPlay = reader.readBool(offsets[56]);
  object.youtubeStreamPriority = reader.readString(offsets[57]);
  return object;
}

P _settingsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readBool(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (reader.readDouble(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readLong(offset)) as P;
    case 12:
      return (reader.readBool(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readString(offset)) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readBool(offset)) as P;
    case 17:
      return (reader.readBool(offset)) as P;
    case 18:
      return (reader.readStringOrNull(offset)) as P;
    case 19:
      return (reader.readString(offset)) as P;
    case 20:
      return (reader.readString(offset)) as P;
    case 21:
      return (reader.readLong(offset)) as P;
    case 22:
      return (reader.readLong(offset)) as P;
    case 23:
      return (reader.readLong(offset)) as P;
    case 24:
      return (reader.readString(offset)) as P;
    case 25:
      return (reader.readDoubleOrNull(offset)) as P;
    case 26:
      return (reader.readLongOrNull(offset)) as P;
    case 27:
      return (reader.readBoolOrNull(offset)) as P;
    case 28:
      return (reader.readDoubleOrNull(offset)) as P;
    case 29:
      return (reader.readLongOrNull(offset)) as P;
    case 30:
      return (reader.readDoubleOrNull(offset)) as P;
    case 31:
      return (reader.readLongOrNull(offset)) as P;
    case 32:
      return (reader.readBoolOrNull(offset)) as P;
    case 33:
      return (reader.readDoubleOrNull(offset)) as P;
    case 34:
      return (reader.readDoubleOrNull(offset)) as P;
    case 35:
      return (reader.readLongOrNull(offset)) as P;
    case 36:
      return (reader.readLong(offset)) as P;
    case 37:
      return (reader.readLong(offset)) as P;
    case 38:
      return (reader.readLong(offset)) as P;
    case 39:
      return (reader.readBool(offset)) as P;
    case 40:
      return (reader.readString(offset)) as P;
    case 41:
      return (reader.readLong(offset)) as P;
    case 42:
      return (reader.readStringOrNull(offset)) as P;
    case 43:
      return (reader.readStringOrNull(offset)) as P;
    case 44:
      return (reader.readLongOrNull(offset)) as P;
    case 45:
      return (reader.readLong(offset)) as P;
    case 46:
      return (reader.readBool(offset)) as P;
    case 47:
      return (reader.readLong(offset)) as P;
    case 48:
      return (reader.readBool(offset)) as P;
    case 49:
      return (reader.readLong(offset)) as P;
    case 50:
      return (reader.readLong(offset)) as P;
    case 51:
      return (reader.readObjectList<SourceSettingsEntry>(
                offset,
                SourceSettingsEntrySchema.deserialize,
                allOffsets,
                SourceSettingsEntry(),
              ) ??
              [])
          as P;
    case 52:
      return (reader.readLong(offset)) as P;
    case 53:
      return (reader.readLong(offset)) as P;
    case 54:
      return (reader.readBool(offset)) as P;
    case 55:
      return (reader.readBool(offset)) as P;
    case 56:
      return (reader.readBool(offset)) as P;
    case 57:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _settingsGetId(Settings object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _settingsGetLinks(Settings object) {
  return [];
}

void _settingsAttach(IsarCollection<dynamic> col, Id id, Settings object) {
  object.id = id;
}

extension SettingsQueryWhereSort on QueryBuilder<Settings, Settings, QWhere> {
  QueryBuilder<Settings, Settings, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SettingsQueryWhere on QueryBuilder<Settings, Settings, QWhereClause> {
  QueryBuilder<Settings, Settings, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<Settings, Settings, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Settings, Settings, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension SettingsQueryFilter
    on QueryBuilder<Settings, Settings, QFilterCondition> {
  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  allowPlainLyricsAutoMatchEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'allowPlainLyricsAutoMatch',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'audioFormatPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'audioFormatPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'audioFormatPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'audioFormatPriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'audioFormatPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'audioFormatPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'audioFormatPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'audioFormatPriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'audioFormatPriority', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioFormatPriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'audioFormatPriority',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioQualityLevelIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'audioQualityLevelIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioQualityLevelIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'audioQualityLevelIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioQualityLevelIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'audioQualityLevelIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  audioQualityLevelIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'audioQualityLevelIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  autoMatchLyricsEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'autoMatchLyrics', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  autoScrollToCurrentTrackEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'autoScrollToCurrentTrack',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'bilibiliStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'bilibiliStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'bilibiliStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'bilibiliStreamPriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'bilibiliStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'bilibiliStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'bilibiliStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'bilibiliStreamPriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'bilibiliStreamPriority', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  bilibiliStreamPriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'bilibiliStreamPriority',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'customDownloadDir'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'customDownloadDir'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'customDownloadDir',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'customDownloadDir',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'customDownloadDir',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'customDownloadDir',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'customDownloadDir',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'customDownloadDir',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'customDownloadDir',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'customDownloadDir',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'customDownloadDir', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  customDownloadDirIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'customDownloadDir', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  detailPanelExpandedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'detailPanelExpanded', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  detailPanelWidthEqualTo(double value, {double epsilon = Query.epsilon}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'detailPanelWidth',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  detailPanelWidthGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'detailPanelWidth',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  detailPanelWidthLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'detailPanelWidth',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  detailPanelWidthBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'detailPanelWidth',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'disabledHomeRankingSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'disabledHomeRankingSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'disabledHomeRankingSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'disabledHomeRankingSources',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'disabledHomeRankingSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'disabledHomeRankingSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'disabledHomeRankingSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'disabledHomeRankingSources',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'disabledHomeRankingSources',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledHomeRankingSourcesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'disabledHomeRankingSources',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'disabledLyricsSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'disabledLyricsSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'disabledLyricsSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'disabledLyricsSources',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'disabledLyricsSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'disabledLyricsSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'disabledLyricsSources',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'disabledLyricsSources',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'disabledLyricsSources', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  disabledLyricsSourcesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'disabledLyricsSources',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  downloadImageOptionIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'downloadImageOptionIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  downloadImageOptionIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'downloadImageOptionIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  downloadImageOptionIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'downloadImageOptionIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  downloadImageOptionIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'downloadImageOptionIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  enableGlobalHotkeysEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'enableGlobalHotkeys', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'fontFamily'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  fontFamilyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'fontFamily'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'fontFamily',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'fontFamily',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'fontFamily',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'fontFamily',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'fontFamily',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'fontFamily',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'fontFamily',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'fontFamily',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> fontFamilyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'fontFamily', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  fontFamilyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'fontFamily', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'homeRankingSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'homeRankingSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'homeRankingSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'homeRankingSourcePriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'homeRankingSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'homeRankingSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'homeRankingSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'homeRankingSourcePriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'homeRankingSourcePriority',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  homeRankingSourcePriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'homeRankingSourcePriority',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'hotkeyConfig'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  hotkeyConfigIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'hotkeyConfig'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'hotkeyConfig',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  hotkeyConfigGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'hotkeyConfig',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'hotkeyConfig',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'hotkeyConfig',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  hotkeyConfigStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'hotkeyConfig',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'hotkeyConfig',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'hotkeyConfig',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> hotkeyConfigMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'hotkeyConfig',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  hotkeyConfigIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'hotkeyConfig', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  hotkeyConfigIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'hotkeyConfig', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  launchAtStartupEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'launchAtStartup', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  launchMinimizedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'launchMinimized', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'locale'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'locale'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'locale',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'locale',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'locale',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'locale',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'locale',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'locale',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'locale',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'locale',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'locale', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> localeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'locale', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsAiEndpoint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsAiEndpoint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsAiEndpoint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsAiEndpoint',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'lyricsAiEndpoint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'lyricsAiEndpoint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'lyricsAiEndpoint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'lyricsAiEndpoint',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lyricsAiEndpoint', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiEndpointIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'lyricsAiEndpoint', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> lyricsAiModelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsAiModel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiModelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsAiModel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> lyricsAiModelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsAiModel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> lyricsAiModelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsAiModel',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiModelStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'lyricsAiModel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> lyricsAiModelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'lyricsAiModel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> lyricsAiModelContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'lyricsAiModel',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> lyricsAiModelMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'lyricsAiModel',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiModelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lyricsAiModel', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiModelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'lyricsAiModel', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTimeoutSecondsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsAiTimeoutSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTimeoutSecondsGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsAiTimeoutSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTimeoutSecondsLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsAiTimeoutSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTimeoutSecondsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsAiTimeoutSeconds',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTitleParsingModeIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsAiTitleParsingModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTitleParsingModeIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsAiTitleParsingModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTitleParsingModeIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsAiTitleParsingModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsAiTitleParsingModeIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsAiTitleParsingModeIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsDisplayModeIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsDisplayModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsDisplayModeIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsDisplayModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsDisplayModeIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsDisplayModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsDisplayModeIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsDisplayModeIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsSourcePriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'lyricsSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'lyricsSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'lyricsSourcePriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'lyricsSourcePriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lyricsSourcePriority', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsSourcePriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'lyricsSourcePriority',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowInactiveTextOpacityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(
          property: r'lyricsWindowInactiveTextOpacity',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowInactiveTextOpacityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(
          property: r'lyricsWindowInactiveTextOpacity',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowInactiveTextOpacityEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowInactiveTextOpacity',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowInactiveTextOpacityGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowInactiveTextOpacity',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowInactiveTextOpacityLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowInactiveTextOpacity',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowInactiveTextOpacityBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowInactiveTextOpacity',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineColorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowOutlineColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineColorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowOutlineColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineColorEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowOutlineColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineColorGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowOutlineColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineColorLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowOutlineColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineColorBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowOutlineColor',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineEnabledIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowOutlineEnabled'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineEnabledIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(
          property: r'lyricsWindowOutlineEnabled',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineEnabledEqualTo(bool? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowOutlineEnabled',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineWidthIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowOutlineWidth'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineWidthIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowOutlineWidth'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineWidthEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowOutlineWidth',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineWidthGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowOutlineWidth',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineWidthLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowOutlineWidth',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowOutlineWidthBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowOutlineWidth',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowSecondaryTextColorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(
          property: r'lyricsWindowSecondaryTextColor',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowSecondaryTextColorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(
          property: r'lyricsWindowSecondaryTextColor',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowSecondaryTextColorEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowSecondaryTextColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowSecondaryTextColorGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowSecondaryTextColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowSecondaryTextColorLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowSecondaryTextColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowSecondaryTextColorBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowSecondaryTextColor',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowBlurRadiusIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowShadowBlurRadius'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowBlurRadiusIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(
          property: r'lyricsWindowShadowBlurRadius',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowBlurRadiusEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowShadowBlurRadius',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowBlurRadiusGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowShadowBlurRadius',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowBlurRadiusLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowShadowBlurRadius',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowBlurRadiusBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowShadowBlurRadius',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowColorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowShadowColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowColorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowShadowColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowColorEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowShadowColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowColorGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowShadowColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowColorLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowShadowColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowColorBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowShadowColor',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowEnabledIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowShadowEnabled'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowEnabledIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowShadowEnabled'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowEnabledEqualTo(bool? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowShadowEnabled',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetXIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowShadowOffsetX'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetXIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowShadowOffsetX'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetXEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowShadowOffsetX',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetXGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowShadowOffsetX',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetXLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowShadowOffsetX',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetXBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowShadowOffsetX',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetYIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowShadowOffsetY'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetYIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowShadowOffsetY'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetYEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowShadowOffsetY',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetYGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowShadowOffsetY',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetYLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowShadowOffsetY',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowShadowOffsetYBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowShadowOffsetY',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowTextColorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lyricsWindowTextColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowTextColorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lyricsWindowTextColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowTextColorEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsWindowTextColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowTextColorGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsWindowTextColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowTextColorLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsWindowTextColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  lyricsWindowTextColorBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsWindowTextColor',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> maxCacheSizeMBEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'maxCacheSizeMB', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxCacheSizeMBGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'maxCacheSizeMB',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxCacheSizeMBLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'maxCacheSizeMB',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> maxCacheSizeMBBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'maxCacheSizeMB',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxConcurrentDownloadsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'maxConcurrentDownloads',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxConcurrentDownloadsGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'maxConcurrentDownloads',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxConcurrentDownloadsLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'maxConcurrentDownloads',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxConcurrentDownloadsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'maxConcurrentDownloads',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxLyricsCacheFilesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'maxLyricsCacheFiles', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxLyricsCacheFilesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'maxLyricsCacheFiles',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxLyricsCacheFilesLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'maxLyricsCacheFiles',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  maxLyricsCacheFilesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'maxLyricsCacheFiles',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  minimizeToTrayOnCloseEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'minimizeToTrayOnClose',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'neteaseStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'neteaseStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'neteaseStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'neteaseStreamPriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'neteaseStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'neteaseStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'neteaseStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'neteaseStreamPriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'neteaseStreamPriority', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  neteaseStreamPriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'neteaseStreamPriority',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  playHistoryLimitEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'playHistoryLimit', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  playHistoryLimitGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'playHistoryLimit',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  playHistoryLimitLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'playHistoryLimit',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  playHistoryLimitBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'playHistoryLimit',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'preferredAudioDeviceId'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'preferredAudioDeviceId'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'preferredAudioDeviceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'preferredAudioDeviceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'preferredAudioDeviceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'preferredAudioDeviceId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'preferredAudioDeviceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'preferredAudioDeviceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'preferredAudioDeviceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'preferredAudioDeviceId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'preferredAudioDeviceId', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'preferredAudioDeviceId',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'preferredAudioDeviceName'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'preferredAudioDeviceName'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'preferredAudioDeviceName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'preferredAudioDeviceName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'preferredAudioDeviceName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'preferredAudioDeviceName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'preferredAudioDeviceName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'preferredAudioDeviceName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'preferredAudioDeviceName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'preferredAudioDeviceName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'preferredAudioDeviceName',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  preferredAudioDeviceNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'preferredAudioDeviceName',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> primaryColorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'primaryColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  primaryColorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'primaryColor'),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> primaryColorEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'primaryColor', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  primaryColorGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'primaryColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> primaryColorLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'primaryColor',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> primaryColorBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'primaryColor',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  radioRefreshIntervalMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'radioRefreshIntervalMinutes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  radioRefreshIntervalMinutesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'radioRefreshIntervalMinutes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  radioRefreshIntervalMinutesLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'radioRefreshIntervalMinutes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  radioRefreshIntervalMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'radioRefreshIntervalMinutes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> railExpandedEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'railExpanded', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  rankingRefreshIntervalMinutesEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'rankingRefreshIntervalMinutes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  rankingRefreshIntervalMinutesGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'rankingRefreshIntervalMinutes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  rankingRefreshIntervalMinutesLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'rankingRefreshIntervalMinutes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  rankingRefreshIntervalMinutesBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'rankingRefreshIntervalMinutes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  rememberPlaybackPositionEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'rememberPlaybackPosition',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  restartRewindSecondsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'restartRewindSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  restartRewindSecondsGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'restartRewindSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  restartRewindSecondsLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'restartRewindSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  restartRewindSecondsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'restartRewindSeconds',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> schemaVersionEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'schemaVersion', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  schemaVersionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'schemaVersion',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> schemaVersionLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'schemaVersion',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> schemaVersionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'schemaVersion',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  sourceSettingsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'sourceSettings', length, true, length, true);
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  sourceSettingsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'sourceSettings', 0, true, 0, true);
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  sourceSettingsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'sourceSettings', 0, false, 999999, true);
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  sourceSettingsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'sourceSettings', 0, true, length, include);
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  sourceSettingsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'sourceSettings', length, include, 999999, true);
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  sourceSettingsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'sourceSettings',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  tempPlayRewindSecondsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'tempPlayRewindSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  tempPlayRewindSecondsGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'tempPlayRewindSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  tempPlayRewindSecondsLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'tempPlayRewindSeconds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  tempPlayRewindSecondsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'tempPlayRewindSeconds',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> themeModeIndexEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'themeModeIndex', value: value),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  themeModeIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'themeModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  themeModeIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'themeModeIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition> themeModeIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'themeModeIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  useBilibiliAuthForPlayEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'useBilibiliAuthForPlay',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  useNeteaseAuthForPlayEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'useNeteaseAuthForPlay',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  useYoutubeAuthForPlayEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'useYoutubeAuthForPlay',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'youtubeStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'youtubeStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'youtubeStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'youtubeStreamPriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'youtubeStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'youtubeStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'youtubeStreamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'youtubeStreamPriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'youtubeStreamPriority', value: ''),
      );
    });
  }

  QueryBuilder<Settings, Settings, QAfterFilterCondition>
  youtubeStreamPriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'youtubeStreamPriority',
          value: '',
        ),
      );
    });
  }
}

extension SettingsQueryObject
    on QueryBuilder<Settings, Settings, QFilterCondition> {
  QueryBuilder<Settings, Settings, QAfterFilterCondition> sourceSettingsElement(
    FilterQuery<SourceSettingsEntry> q,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'sourceSettings');
    });
  }
}

extension SettingsQueryLinks
    on QueryBuilder<Settings, Settings, QFilterCondition> {}

extension SettingsQuerySortBy on QueryBuilder<Settings, Settings, QSortBy> {
  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAllowPlainLyricsAutoMatch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allowPlainLyricsAutoMatch', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAllowPlainLyricsAutoMatchDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allowPlainLyricsAutoMatch', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByAudioFormatPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioFormatPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAudioFormatPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioFormatPriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAudioQualityLevelIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioQualityLevelIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAudioQualityLevelIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioQualityLevelIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByAutoMatchLyrics() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoMatchLyrics', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByAutoMatchLyricsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoMatchLyrics', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAutoScrollToCurrentTrack() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoScrollToCurrentTrack', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByAutoScrollToCurrentTrackDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoScrollToCurrentTrack', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByBilibiliStreamPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliStreamPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByBilibiliStreamPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliStreamPriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByCustomDownloadDir() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customDownloadDir', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByCustomDownloadDirDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customDownloadDir', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByDetailPanelExpanded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelExpanded', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByDetailPanelExpandedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelExpanded', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByDetailPanelWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelWidth', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByDetailPanelWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelWidth', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByDisabledHomeRankingSources() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledHomeRankingSources', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByDisabledHomeRankingSourcesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledHomeRankingSources', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByDisabledLyricsSources() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledLyricsSources', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByDisabledLyricsSourcesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledLyricsSources', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByDownloadImageOptionIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadImageOptionIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByDownloadImageOptionIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadImageOptionIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByEnableGlobalHotkeys() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enableGlobalHotkeys', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByEnableGlobalHotkeysDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enableGlobalHotkeys', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByFontFamily() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fontFamily', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByFontFamilyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fontFamily', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByHomeRankingSourcePriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeRankingSourcePriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByHomeRankingSourcePriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeRankingSourcePriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByHotkeyConfig() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyConfig', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByHotkeyConfigDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyConfig', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLaunchAtStartup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLaunchAtStartupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLaunchMinimized() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchMinimized', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLaunchMinimizedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchMinimized', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLocale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locale', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLocaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locale', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLyricsAiEndpoint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiEndpoint', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLyricsAiEndpointDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiEndpoint', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLyricsAiModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiModel', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLyricsAiModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiModel', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsAiTimeoutSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTimeoutSeconds', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsAiTimeoutSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTimeoutSeconds', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsAiTitleParsingModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTitleParsingModeIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsAiTitleParsingModeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTitleParsingModeIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsDisplayModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsDisplayModeIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsDisplayModeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsDisplayModeIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLyricsSourcePriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSourcePriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsSourcePriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSourcePriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowInactiveTextOpacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowInactiveTextOpacity', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowInactiveTextOpacityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowInactiveTextOpacity', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowOutlineColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowOutlineColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowOutlineEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineEnabled', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowOutlineEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineEnabled', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowOutlineWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineWidth', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowOutlineWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineWidth', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowSecondaryTextColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowSecondaryTextColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowSecondaryTextColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowSecondaryTextColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowBlurRadius() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowBlurRadius', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowBlurRadiusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowBlurRadius', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowEnabled', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowEnabled', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowOffsetX() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetX', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowOffsetXDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetX', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowOffsetY() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetY', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowShadowOffsetYDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetY', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByLyricsWindowTextColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowTextColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByLyricsWindowTextColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowTextColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByMaxCacheSizeMB() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxCacheSizeMB', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByMaxCacheSizeMBDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxCacheSizeMB', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByMaxConcurrentDownloads() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxConcurrentDownloads', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByMaxConcurrentDownloadsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxConcurrentDownloads', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByMaxLyricsCacheFiles() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxLyricsCacheFiles', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByMaxLyricsCacheFilesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxLyricsCacheFiles', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByMinimizeToTrayOnClose() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTrayOnClose', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByMinimizeToTrayOnCloseDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTrayOnClose', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByNeteaseStreamPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'neteaseStreamPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByNeteaseStreamPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'neteaseStreamPriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByPlayHistoryLimit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'playHistoryLimit', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByPlayHistoryLimitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'playHistoryLimit', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByPreferredAudioDeviceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceId', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByPreferredAudioDeviceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceId', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByPreferredAudioDeviceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceName', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByPreferredAudioDeviceNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceName', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByPrimaryColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primaryColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByPrimaryColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primaryColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRadioRefreshIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'radioRefreshIntervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRadioRefreshIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'radioRefreshIntervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByRailExpanded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'railExpanded', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByRailExpandedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'railExpanded', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRankingRefreshIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rankingRefreshIntervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRankingRefreshIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rankingRefreshIntervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRememberPlaybackPosition() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rememberPlaybackPosition', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRememberPlaybackPositionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rememberPlaybackPosition', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByRestartRewindSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'restartRewindSeconds', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByRestartRewindSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'restartRewindSeconds', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortBySchemaVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'schemaVersion', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortBySchemaVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'schemaVersion', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByTempPlayRewindSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tempPlayRewindSeconds', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByTempPlayRewindSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tempPlayRewindSeconds', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByThemeModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModeIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByThemeModeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModeIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByUseBilibiliAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useBilibiliAuthForPlay', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByUseBilibiliAuthForPlayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useBilibiliAuthForPlay', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByUseNeteaseAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useNeteaseAuthForPlay', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByUseNeteaseAuthForPlayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useNeteaseAuthForPlay', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByUseYoutubeAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useYoutubeAuthForPlay', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByUseYoutubeAuthForPlayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useYoutubeAuthForPlay', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> sortByYoutubeStreamPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'youtubeStreamPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  sortByYoutubeStreamPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'youtubeStreamPriority', Sort.desc);
    });
  }
}

extension SettingsQuerySortThenBy
    on QueryBuilder<Settings, Settings, QSortThenBy> {
  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAllowPlainLyricsAutoMatch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allowPlainLyricsAutoMatch', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAllowPlainLyricsAutoMatchDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'allowPlainLyricsAutoMatch', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByAudioFormatPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioFormatPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAudioFormatPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioFormatPriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAudioQualityLevelIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioQualityLevelIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAudioQualityLevelIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioQualityLevelIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByAutoMatchLyrics() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoMatchLyrics', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByAutoMatchLyricsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoMatchLyrics', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAutoScrollToCurrentTrack() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoScrollToCurrentTrack', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByAutoScrollToCurrentTrackDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'autoScrollToCurrentTrack', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByBilibiliStreamPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliStreamPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByBilibiliStreamPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliStreamPriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByCustomDownloadDir() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customDownloadDir', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByCustomDownloadDirDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'customDownloadDir', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByDetailPanelExpanded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelExpanded', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByDetailPanelExpandedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelExpanded', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByDetailPanelWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelWidth', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByDetailPanelWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detailPanelWidth', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByDisabledHomeRankingSources() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledHomeRankingSources', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByDisabledHomeRankingSourcesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledHomeRankingSources', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByDisabledLyricsSources() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledLyricsSources', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByDisabledLyricsSourcesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'disabledLyricsSources', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByDownloadImageOptionIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadImageOptionIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByDownloadImageOptionIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'downloadImageOptionIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByEnableGlobalHotkeys() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enableGlobalHotkeys', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByEnableGlobalHotkeysDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enableGlobalHotkeys', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByFontFamily() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fontFamily', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByFontFamilyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'fontFamily', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByHomeRankingSourcePriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeRankingSourcePriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByHomeRankingSourcePriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'homeRankingSourcePriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByHotkeyConfig() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyConfig', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByHotkeyConfigDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hotkeyConfig', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLaunchAtStartup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLaunchAtStartupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchAtStartup', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLaunchMinimized() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchMinimized', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLaunchMinimizedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'launchMinimized', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLocale() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locale', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLocaleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locale', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLyricsAiEndpoint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiEndpoint', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLyricsAiEndpointDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiEndpoint', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLyricsAiModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiModel', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLyricsAiModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiModel', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsAiTimeoutSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTimeoutSeconds', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsAiTimeoutSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTimeoutSeconds', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsAiTitleParsingModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTitleParsingModeIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsAiTitleParsingModeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsAiTitleParsingModeIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsDisplayModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsDisplayModeIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsDisplayModeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsDisplayModeIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLyricsSourcePriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSourcePriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsSourcePriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSourcePriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowInactiveTextOpacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowInactiveTextOpacity', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowInactiveTextOpacityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowInactiveTextOpacity', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowOutlineColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowOutlineColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowOutlineEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineEnabled', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowOutlineEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineEnabled', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowOutlineWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineWidth', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowOutlineWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowOutlineWidth', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowSecondaryTextColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowSecondaryTextColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowSecondaryTextColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowSecondaryTextColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowBlurRadius() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowBlurRadius', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowBlurRadiusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowBlurRadius', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowEnabled', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowEnabled', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowOffsetX() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetX', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowOffsetXDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetX', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowOffsetY() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetY', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowShadowOffsetYDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowShadowOffsetY', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByLyricsWindowTextColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowTextColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByLyricsWindowTextColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsWindowTextColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByMaxCacheSizeMB() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxCacheSizeMB', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByMaxCacheSizeMBDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxCacheSizeMB', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByMaxConcurrentDownloads() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxConcurrentDownloads', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByMaxConcurrentDownloadsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxConcurrentDownloads', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByMaxLyricsCacheFiles() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxLyricsCacheFiles', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByMaxLyricsCacheFilesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxLyricsCacheFiles', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByMinimizeToTrayOnClose() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTrayOnClose', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByMinimizeToTrayOnCloseDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimizeToTrayOnClose', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByNeteaseStreamPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'neteaseStreamPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByNeteaseStreamPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'neteaseStreamPriority', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByPlayHistoryLimit() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'playHistoryLimit', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByPlayHistoryLimitDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'playHistoryLimit', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByPreferredAudioDeviceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceId', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByPreferredAudioDeviceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceId', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByPreferredAudioDeviceName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceName', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByPreferredAudioDeviceNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'preferredAudioDeviceName', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByPrimaryColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primaryColor', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByPrimaryColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'primaryColor', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRadioRefreshIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'radioRefreshIntervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRadioRefreshIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'radioRefreshIntervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByRailExpanded() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'railExpanded', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByRailExpandedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'railExpanded', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRankingRefreshIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rankingRefreshIntervalMinutes', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRankingRefreshIntervalMinutesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rankingRefreshIntervalMinutes', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRememberPlaybackPosition() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rememberPlaybackPosition', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRememberPlaybackPositionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rememberPlaybackPosition', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByRestartRewindSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'restartRewindSeconds', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByRestartRewindSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'restartRewindSeconds', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenBySchemaVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'schemaVersion', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenBySchemaVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'schemaVersion', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByTempPlayRewindSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tempPlayRewindSeconds', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByTempPlayRewindSecondsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tempPlayRewindSeconds', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByThemeModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModeIndex', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByThemeModeIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'themeModeIndex', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByUseBilibiliAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useBilibiliAuthForPlay', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByUseBilibiliAuthForPlayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useBilibiliAuthForPlay', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByUseNeteaseAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useNeteaseAuthForPlay', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByUseNeteaseAuthForPlayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useNeteaseAuthForPlay', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByUseYoutubeAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useYoutubeAuthForPlay', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByUseYoutubeAuthForPlayDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useYoutubeAuthForPlay', Sort.desc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy> thenByYoutubeStreamPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'youtubeStreamPriority', Sort.asc);
    });
  }

  QueryBuilder<Settings, Settings, QAfterSortBy>
  thenByYoutubeStreamPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'youtubeStreamPriority', Sort.desc);
    });
  }
}

extension SettingsQueryWhereDistinct
    on QueryBuilder<Settings, Settings, QDistinct> {
  QueryBuilder<Settings, Settings, QDistinct>
  distinctByAllowPlainLyricsAutoMatch() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'allowPlainLyricsAutoMatch');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByAudioFormatPriority({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'audioFormatPriority',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByAudioQualityLevelIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'audioQualityLevelIndex');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByAutoMatchLyrics() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'autoMatchLyrics');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByAutoScrollToCurrentTrack() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'autoScrollToCurrentTrack');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByBilibiliStreamPriority({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'bilibiliStreamPriority',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByCustomDownloadDir({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'customDownloadDir',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByDetailPanelExpanded() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'detailPanelExpanded');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByDetailPanelWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'detailPanelWidth');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByDisabledHomeRankingSources({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'disabledHomeRankingSources',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByDisabledLyricsSources({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'disabledLyricsSources',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByDownloadImageOptionIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'downloadImageOptionIndex');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByEnableGlobalHotkeys() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'enableGlobalHotkeys');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByFontFamily({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'fontFamily', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByHomeRankingSourcePriority({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'homeRankingSourcePriority',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByHotkeyConfig({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hotkeyConfig', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByLaunchAtStartup() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'launchAtStartup');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByLaunchMinimized() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'launchMinimized');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByLocale({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'locale', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByLyricsAiEndpoint({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'lyricsAiEndpoint',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByLyricsAiModel({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'lyricsAiModel',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsAiTimeoutSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsAiTimeoutSeconds');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsAiTitleParsingModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsAiTitleParsingModeIndex');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsDisplayModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsDisplayModeIndex');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByLyricsSourcePriority({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'lyricsSourcePriority',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowInactiveTextOpacity() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowInactiveTextOpacity');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowOutlineColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowOutlineColor');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowOutlineEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowOutlineEnabled');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowOutlineWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowOutlineWidth');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowSecondaryTextColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowSecondaryTextColor');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowShadowBlurRadius() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowShadowBlurRadius');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowShadowColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowShadowColor');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowShadowEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowShadowEnabled');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowShadowOffsetX() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowShadowOffsetX');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowShadowOffsetY() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowShadowOffsetY');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByLyricsWindowTextColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsWindowTextColor');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByMaxCacheSizeMB() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxCacheSizeMB');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByMaxConcurrentDownloads() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxConcurrentDownloads');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByMaxLyricsCacheFiles() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxLyricsCacheFiles');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByMinimizeToTrayOnClose() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'minimizeToTrayOnClose');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByNeteaseStreamPriority({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'neteaseStreamPriority',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByPlayHistoryLimit() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'playHistoryLimit');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByPreferredAudioDeviceId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'preferredAudioDeviceId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByPreferredAudioDeviceName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'preferredAudioDeviceName',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByPrimaryColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'primaryColor');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByRadioRefreshIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'radioRefreshIntervalMinutes');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByRailExpanded() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'railExpanded');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByRankingRefreshIntervalMinutes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rankingRefreshIntervalMinutes');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByRememberPlaybackPosition() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rememberPlaybackPosition');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByRestartRewindSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'restartRewindSeconds');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctBySchemaVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'schemaVersion');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByTempPlayRewindSeconds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tempPlayRewindSeconds');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByThemeModeIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'themeModeIndex');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByUseBilibiliAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'useBilibiliAuthForPlay');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByUseNeteaseAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'useNeteaseAuthForPlay');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct>
  distinctByUseYoutubeAuthForPlay() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'useYoutubeAuthForPlay');
    });
  }

  QueryBuilder<Settings, Settings, QDistinct> distinctByYoutubeStreamPriority({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'youtubeStreamPriority',
        caseSensitive: caseSensitive,
      );
    });
  }
}

extension SettingsQueryProperty
    on QueryBuilder<Settings, Settings, QQueryProperty> {
  QueryBuilder<Settings, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  allowPlainLyricsAutoMatchProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'allowPlainLyricsAutoMatch');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  audioFormatPriorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'audioFormatPriority');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  audioQualityLevelIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'audioQualityLevelIndex');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations> autoMatchLyricsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'autoMatchLyrics');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  autoScrollToCurrentTrackProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'autoScrollToCurrentTrack');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  bilibiliStreamPriorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bilibiliStreamPriority');
    });
  }

  QueryBuilder<Settings, String?, QQueryOperations>
  customDownloadDirProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'customDownloadDir');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations> detailPanelExpandedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'detailPanelExpanded');
    });
  }

  QueryBuilder<Settings, double, QQueryOperations> detailPanelWidthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'detailPanelWidth');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  disabledHomeRankingSourcesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'disabledHomeRankingSources');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  disabledLyricsSourcesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'disabledLyricsSources');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  downloadImageOptionIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'downloadImageOptionIndex');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations> enableGlobalHotkeysProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'enableGlobalHotkeys');
    });
  }

  QueryBuilder<Settings, String?, QQueryOperations> fontFamilyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'fontFamily');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  homeRankingSourcePriorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'homeRankingSourcePriority');
    });
  }

  QueryBuilder<Settings, String?, QQueryOperations> hotkeyConfigProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hotkeyConfig');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations> launchAtStartupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'launchAtStartup');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations> launchMinimizedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'launchMinimized');
    });
  }

  QueryBuilder<Settings, String?, QQueryOperations> localeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'locale');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations> lyricsAiEndpointProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsAiEndpoint');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations> lyricsAiModelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsAiModel');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  lyricsAiTimeoutSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsAiTimeoutSeconds');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  lyricsAiTitleParsingModeIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsAiTitleParsingModeIndex');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  lyricsDisplayModeIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsDisplayModeIndex');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  lyricsSourcePriorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsSourcePriority');
    });
  }

  QueryBuilder<Settings, double?, QQueryOperations>
  lyricsWindowInactiveTextOpacityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowInactiveTextOpacity');
    });
  }

  QueryBuilder<Settings, int?, QQueryOperations>
  lyricsWindowOutlineColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowOutlineColor');
    });
  }

  QueryBuilder<Settings, bool?, QQueryOperations>
  lyricsWindowOutlineEnabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowOutlineEnabled');
    });
  }

  QueryBuilder<Settings, double?, QQueryOperations>
  lyricsWindowOutlineWidthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowOutlineWidth');
    });
  }

  QueryBuilder<Settings, int?, QQueryOperations>
  lyricsWindowSecondaryTextColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowSecondaryTextColor');
    });
  }

  QueryBuilder<Settings, double?, QQueryOperations>
  lyricsWindowShadowBlurRadiusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowShadowBlurRadius');
    });
  }

  QueryBuilder<Settings, int?, QQueryOperations>
  lyricsWindowShadowColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowShadowColor');
    });
  }

  QueryBuilder<Settings, bool?, QQueryOperations>
  lyricsWindowShadowEnabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowShadowEnabled');
    });
  }

  QueryBuilder<Settings, double?, QQueryOperations>
  lyricsWindowShadowOffsetXProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowShadowOffsetX');
    });
  }

  QueryBuilder<Settings, double?, QQueryOperations>
  lyricsWindowShadowOffsetYProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowShadowOffsetY');
    });
  }

  QueryBuilder<Settings, int?, QQueryOperations>
  lyricsWindowTextColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsWindowTextColor');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations> maxCacheSizeMBProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxCacheSizeMB');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  maxConcurrentDownloadsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxConcurrentDownloads');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations> maxLyricsCacheFilesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxLyricsCacheFiles');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  minimizeToTrayOnCloseProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'minimizeToTrayOnClose');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  neteaseStreamPriorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'neteaseStreamPriority');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations> playHistoryLimitProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'playHistoryLimit');
    });
  }

  QueryBuilder<Settings, String?, QQueryOperations>
  preferredAudioDeviceIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'preferredAudioDeviceId');
    });
  }

  QueryBuilder<Settings, String?, QQueryOperations>
  preferredAudioDeviceNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'preferredAudioDeviceName');
    });
  }

  QueryBuilder<Settings, int?, QQueryOperations> primaryColorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'primaryColor');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  radioRefreshIntervalMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'radioRefreshIntervalMinutes');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations> railExpandedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'railExpanded');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  rankingRefreshIntervalMinutesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rankingRefreshIntervalMinutes');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  rememberPlaybackPositionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rememberPlaybackPosition');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations> restartRewindSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'restartRewindSeconds');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations> schemaVersionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'schemaVersion');
    });
  }

  QueryBuilder<Settings, List<SourceSettingsEntry>, QQueryOperations>
  sourceSettingsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceSettings');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations>
  tempPlayRewindSecondsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tempPlayRewindSeconds');
    });
  }

  QueryBuilder<Settings, int, QQueryOperations> themeModeIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'themeModeIndex');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  useBilibiliAuthForPlayProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'useBilibiliAuthForPlay');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  useNeteaseAuthForPlayProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'useNeteaseAuthForPlay');
    });
  }

  QueryBuilder<Settings, bool, QQueryOperations>
  useYoutubeAuthForPlayProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'useYoutubeAuthForPlay');
    });
  }

  QueryBuilder<Settings, String, QQueryOperations>
  youtubeStreamPriorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'youtubeStreamPriority');
    });
  }
}

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const SourceSettingsEntrySchema = Schema(
  name: r'SourceSettingsEntry',
  id: -6033692620943448784,
  properties: {
    r'sourceId': PropertySchema(
      id: 0,
      name: r'sourceId',
      type: IsarType.string,
    ),
    r'streamPriority': PropertySchema(
      id: 1,
      name: r'streamPriority',
      type: IsarType.string,
    ),
    r'useAuthForPlay': PropertySchema(
      id: 2,
      name: r'useAuthForPlay',
      type: IsarType.bool,
    ),
  },
  estimateSize: _sourceSettingsEntryEstimateSize,
  serialize: _sourceSettingsEntrySerialize,
  deserialize: _sourceSettingsEntryDeserialize,
  deserializeProp: _sourceSettingsEntryDeserializeProp,
);

int _sourceSettingsEntryEstimateSize(
  SourceSettingsEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.sourceId.length * 3;
  bytesCount += 3 + object.streamPriority.length * 3;
  return bytesCount;
}

void _sourceSettingsEntrySerialize(
  SourceSettingsEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.sourceId);
  writer.writeString(offsets[1], object.streamPriority);
  writer.writeBool(offsets[2], object.useAuthForPlay);
}

SourceSettingsEntry _sourceSettingsEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SourceSettingsEntry();
  object.sourceId = reader.readString(offsets[0]);
  object.streamPriority = reader.readString(offsets[1]);
  object.useAuthForPlay = reader.readBool(offsets[2]);
  return object;
}

P _sourceSettingsEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension SourceSettingsEntryQueryFilter
    on
        QueryBuilder<
          SourceSettingsEntry,
          SourceSettingsEntry,
          QFilterCondition
        > {
  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sourceId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sourceId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sourceId', value: ''),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  sourceIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sourceId', value: ''),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'streamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'streamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'streamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'streamPriority',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'streamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'streamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'streamPriority',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'streamPriority',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'streamPriority', value: ''),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  streamPriorityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'streamPriority', value: ''),
      );
    });
  }

  QueryBuilder<SourceSettingsEntry, SourceSettingsEntry, QAfterFilterCondition>
  useAuthForPlayEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'useAuthForPlay', value: value),
      );
    });
  }
}

extension SourceSettingsEntryQueryObject
    on
        QueryBuilder<
          SourceSettingsEntry,
          SourceSettingsEntry,
          QFilterCondition
        > {}
