// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetTrackCollection on Isar {
  IsarCollection<Track> get tracks => this.collection();
}

const TrackSchema = CollectionSchema(
  name: r'Track',
  id: 6244076704169336260,
  properties: {
    r'artist': PropertySchema(id: 0, name: r'artist', type: IsarType.string),
    r'audioUrl': PropertySchema(
      id: 1,
      name: r'audioUrl',
      type: IsarType.string,
    ),
    r'audioUrlExpiry': PropertySchema(
      id: 2,
      name: r'audioUrlExpiry',
      type: IsarType.dateTime,
    ),
    r'bilibiliAid': PropertySchema(
      id: 3,
      name: r'bilibiliAid',
      type: IsarType.long,
    ),
    r'channelId': PropertySchema(
      id: 4,
      name: r'channelId',
      type: IsarType.string,
    ),
    r'cid': PropertySchema(id: 5, name: r'cid', type: IsarType.long),
    r'createdAt': PropertySchema(
      id: 6,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'durationMs': PropertySchema(
      id: 7,
      name: r'durationMs',
      type: IsarType.long,
    ),
    r'formattedDuration': PropertySchema(
      id: 8,
      name: r'formattedDuration',
      type: IsarType.string,
    ),
    r'groupKey': PropertySchema(
      id: 9,
      name: r'groupKey',
      type: IsarType.string,
    ),
    r'hasValidAudioUrl': PropertySchema(
      id: 10,
      name: r'hasValidAudioUrl',
      type: IsarType.bool,
    ),
    r'isAvailable': PropertySchema(
      id: 11,
      name: r'isAvailable',
      type: IsarType.bool,
    ),
    r'isPartOfMultiPage': PropertySchema(
      id: 12,
      name: r'isPartOfMultiPage',
      type: IsarType.bool,
    ),
    r'isVip': PropertySchema(id: 13, name: r'isVip', type: IsarType.bool),
    r'originalSongId': PropertySchema(
      id: 14,
      name: r'originalSongId',
      type: IsarType.string,
    ),
    r'originalSource': PropertySchema(
      id: 15,
      name: r'originalSource',
      type: IsarType.string,
    ),
    r'ownerId': PropertySchema(id: 16, name: r'ownerId', type: IsarType.long),
    r'pageCount': PropertySchema(
      id: 17,
      name: r'pageCount',
      type: IsarType.long,
    ),
    r'pageNum': PropertySchema(id: 18, name: r'pageNum', type: IsarType.long),
    r'parentTitle': PropertySchema(
      id: 19,
      name: r'parentTitle',
      type: IsarType.string,
    ),
    r'playlistInfo': PropertySchema(
      id: 20,
      name: r'playlistInfo',
      type: IsarType.objectList,
      target: r'PlaylistDownloadInfo',
    ),
    r'sourceId': PropertySchema(
      id: 21,
      name: r'sourceId',
      type: IsarType.string,
    ),
    r'sourcePageKey': PropertySchema(
      id: 22,
      name: r'sourcePageKey',
      type: IsarType.string,
    ),
    r'sourceType': PropertySchema(
      id: 23,
      name: r'sourceType',
      type: IsarType.string,
    ),
    r'thumbnailUrl': PropertySchema(
      id: 24,
      name: r'thumbnailUrl',
      type: IsarType.string,
    ),
    r'title': PropertySchema(id: 25, name: r'title', type: IsarType.string),
    r'unavailableReason': PropertySchema(
      id: 26,
      name: r'unavailableReason',
      type: IsarType.string,
    ),
    r'uniqueKey': PropertySchema(
      id: 27,
      name: r'uniqueKey',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 28,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
  },
  estimateSize: _trackEstimateSize,
  serialize: _trackSerialize,
  deserialize: _trackDeserialize,
  deserializeProp: _trackDeserializeProp,
  idName: r'id',
  indexes: {
    r'sourceId': IndexSchema(
      id: 2155220942429093580,
      name: r'sourceId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sourceId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'sourceType': IndexSchema(
      id: 5365578901051110922,
      name: r'sourceType',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sourceType',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'cid': IndexSchema(
      id: 2203098626925536187,
      name: r'cid',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'cid',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'updatedAt': IndexSchema(
      id: -6238191080293565125,
      name: r'updatedAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'updatedAt',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
    r'sourcePageKey_cid': IndexSchema(
      id: -8595702893458351278,
      name: r'sourcePageKey_cid',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sourcePageKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'cid',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {r'PlaylistDownloadInfo': PlaylistDownloadInfoSchema},
  getId: _trackGetId,
  getLinks: _trackGetLinks,
  attach: _trackAttach,
  version: '3.3.2',
);

int _trackEstimateSize(
  Track object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.artist;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.audioUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.channelId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.formattedDuration.length * 3;
  bytesCount += 3 + object.groupKey.length * 3;
  {
    final value = object.originalSongId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.originalSource;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.parentTitle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.playlistInfo.length * 3;
  {
    final offsets = allOffsets[PlaylistDownloadInfo]!;
    for (var i = 0; i < object.playlistInfo.length; i++) {
      final value = object.playlistInfo[i];
      bytesCount += PlaylistDownloadInfoSchema.estimateSize(
        value,
        offsets,
        allOffsets,
      );
    }
  }
  bytesCount += 3 + object.sourceId.length * 3;
  bytesCount += 3 + object.sourcePageKey.length * 3;
  bytesCount += 3 + object.sourceType.length * 3;
  {
    final value = object.thumbnailUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  {
    final value = object.unavailableReason;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.uniqueKey.length * 3;
  return bytesCount;
}

void _trackSerialize(
  Track object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.artist);
  writer.writeString(offsets[1], object.audioUrl);
  writer.writeDateTime(offsets[2], object.audioUrlExpiry);
  writer.writeLong(offsets[3], object.bilibiliAid);
  writer.writeString(offsets[4], object.channelId);
  writer.writeLong(offsets[5], object.cid);
  writer.writeDateTime(offsets[6], object.createdAt);
  writer.writeLong(offsets[7], object.durationMs);
  writer.writeString(offsets[8], object.formattedDuration);
  writer.writeString(offsets[9], object.groupKey);
  writer.writeBool(offsets[10], object.hasValidAudioUrl);
  writer.writeBool(offsets[11], object.isAvailable);
  writer.writeBool(offsets[12], object.isPartOfMultiPage);
  writer.writeBool(offsets[13], object.isVip);
  writer.writeString(offsets[14], object.originalSongId);
  writer.writeString(offsets[15], object.originalSource);
  writer.writeLong(offsets[16], object.ownerId);
  writer.writeLong(offsets[17], object.pageCount);
  writer.writeLong(offsets[18], object.pageNum);
  writer.writeString(offsets[19], object.parentTitle);
  writer.writeObjectList<PlaylistDownloadInfo>(
    offsets[20],
    allOffsets,
    PlaylistDownloadInfoSchema.serialize,
    object.playlistInfo,
  );
  writer.writeString(offsets[21], object.sourceId);
  writer.writeString(offsets[22], object.sourcePageKey);
  writer.writeString(offsets[23], object.sourceType);
  writer.writeString(offsets[24], object.thumbnailUrl);
  writer.writeString(offsets[25], object.title);
  writer.writeString(offsets[26], object.unavailableReason);
  writer.writeString(offsets[27], object.uniqueKey);
  writer.writeDateTime(offsets[28], object.updatedAt);
}

Track _trackDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Track();
  object.artist = reader.readStringOrNull(offsets[0]);
  object.audioUrl = reader.readStringOrNull(offsets[1]);
  object.audioUrlExpiry = reader.readDateTimeOrNull(offsets[2]);
  object.bilibiliAid = reader.readLongOrNull(offsets[3]);
  object.channelId = reader.readStringOrNull(offsets[4]);
  object.cid = reader.readLongOrNull(offsets[5]);
  object.createdAt = reader.readDateTime(offsets[6]);
  object.durationMs = reader.readLongOrNull(offsets[7]);
  object.id = id;
  object.isAvailable = reader.readBool(offsets[11]);
  object.isVip = reader.readBool(offsets[13]);
  object.originalSongId = reader.readStringOrNull(offsets[14]);
  object.originalSource = reader.readStringOrNull(offsets[15]);
  object.ownerId = reader.readLongOrNull(offsets[16]);
  object.pageCount = reader.readLongOrNull(offsets[17]);
  object.pageNum = reader.readLongOrNull(offsets[18]);
  object.parentTitle = reader.readStringOrNull(offsets[19]);
  object.playlistInfo =
      reader.readObjectList<PlaylistDownloadInfo>(
        offsets[20],
        PlaylistDownloadInfoSchema.deserialize,
        allOffsets,
        PlaylistDownloadInfo(),
      ) ??
      [];
  object.sourceId = reader.readString(offsets[21]);
  object.sourceType = reader.readString(offsets[23]);
  object.thumbnailUrl = reader.readStringOrNull(offsets[24]);
  object.title = reader.readString(offsets[25]);
  object.unavailableReason = reader.readStringOrNull(offsets[26]);
  object.updatedAt = reader.readDateTimeOrNull(offsets[28]);
  return object;
}

P _trackDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readDateTime(offset)) as P;
    case 7:
      return (reader.readLongOrNull(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readBool(offset)) as P;
    case 11:
      return (reader.readBool(offset)) as P;
    case 12:
      return (reader.readBool(offset)) as P;
    case 13:
      return (reader.readBool(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readLongOrNull(offset)) as P;
    case 17:
      return (reader.readLongOrNull(offset)) as P;
    case 18:
      return (reader.readLongOrNull(offset)) as P;
    case 19:
      return (reader.readStringOrNull(offset)) as P;
    case 20:
      return (reader.readObjectList<PlaylistDownloadInfo>(
                offset,
                PlaylistDownloadInfoSchema.deserialize,
                allOffsets,
                PlaylistDownloadInfo(),
              ) ??
              [])
          as P;
    case 21:
      return (reader.readString(offset)) as P;
    case 22:
      return (reader.readString(offset)) as P;
    case 23:
      return (reader.readString(offset)) as P;
    case 24:
      return (reader.readStringOrNull(offset)) as P;
    case 25:
      return (reader.readString(offset)) as P;
    case 26:
      return (reader.readStringOrNull(offset)) as P;
    case 27:
      return (reader.readString(offset)) as P;
    case 28:
      return (reader.readDateTimeOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _trackGetId(Track object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _trackGetLinks(Track object) {
  return [];
}

void _trackAttach(IsarCollection<dynamic> col, Id id, Track object) {
  object.id = id;
}

extension TrackQueryWhereSort on QueryBuilder<Track, Track, QWhere> {
  QueryBuilder<Track, Track, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<Track, Track, QAfterWhere> anyCid() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'cid'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhere> anyUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'updatedAt'),
      );
    });
  }
}

extension TrackQueryWhere on QueryBuilder<Track, Track, QWhereClause> {
  QueryBuilder<Track, Track, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<Track, Track, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> idBetween(
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

  QueryBuilder<Track, Track, QAfterWhereClause> sourceIdEqualTo(
    String sourceId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'sourceId', value: [sourceId]),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourceIdNotEqualTo(
    String sourceId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [],
                upper: [sourceId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [sourceId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [sourceId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [],
                upper: [sourceId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourceTypeEqualTo(
    String sourceType,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'sourceType', value: [sourceType]),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourceTypeNotEqualTo(
    String sourceType,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceType',
                lower: [],
                upper: [sourceType],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceType',
                lower: [sourceType],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceType',
                lower: [sourceType],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceType',
                lower: [],
                upper: [sourceType],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'cid', value: [null]),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cid',
          lower: [null],
          includeLower: false,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidEqualTo(int? cid) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'cid', value: [cid]),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidNotEqualTo(int? cid) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cid',
                lower: [],
                upper: [cid],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cid',
                lower: [cid],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cid',
                lower: [cid],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'cid',
                lower: [],
                upper: [cid],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidGreaterThan(
    int? cid, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cid',
          lower: [cid],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidLessThan(
    int? cid, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cid',
          lower: [],
          upper: [cid],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> cidBetween(
    int? lowerCid,
    int? upperCid, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'cid',
          lower: [lowerCid],
          includeLower: includeLower,
          upper: [upperCid],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'updatedAt', value: [null]),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'updatedAt',
          lower: [null],
          includeLower: false,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtEqualTo(
    DateTime? updatedAt,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'updatedAt', value: [updatedAt]),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtNotEqualTo(
    DateTime? updatedAt,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'updatedAt',
                lower: [],
                upper: [updatedAt],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'updatedAt',
                lower: [updatedAt],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'updatedAt',
                lower: [updatedAt],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'updatedAt',
                lower: [],
                upper: [updatedAt],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtGreaterThan(
    DateTime? updatedAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'updatedAt',
          lower: [updatedAt],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtLessThan(
    DateTime? updatedAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'updatedAt',
          lower: [],
          upper: [updatedAt],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> updatedAtBetween(
    DateTime? lowerUpdatedAt,
    DateTime? upperUpdatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'updatedAt',
          lower: [lowerUpdatedAt],
          includeLower: includeLower,
          upper: [upperUpdatedAt],
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourcePageKeyEqualToAnyCid(
    String sourcePageKey,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'sourcePageKey_cid',
          value: [sourcePageKey],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourcePageKeyNotEqualToAnyCid(
    String sourcePageKey,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [],
                upper: [sourcePageKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [sourcePageKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [sourcePageKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [],
                upper: [sourcePageKey],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourcePageKeyEqualToCidIsNull(
    String sourcePageKey,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'sourcePageKey_cid',
          value: [sourcePageKey, null],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause>
  sourcePageKeyEqualToCidIsNotNull(String sourcePageKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sourcePageKey_cid',
          lower: [sourcePageKey, null],
          includeLower: false,
          upper: [sourcePageKey],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourcePageKeyCidEqualTo(
    String sourcePageKey,
    int? cid,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'sourcePageKey_cid',
          value: [sourcePageKey, cid],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause>
  sourcePageKeyEqualToCidNotEqualTo(String sourcePageKey, int? cid) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [sourcePageKey],
                upper: [sourcePageKey, cid],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [sourcePageKey, cid],
                includeLower: false,
                upper: [sourcePageKey],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [sourcePageKey, cid],
                includeLower: false,
                upper: [sourcePageKey],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourcePageKey_cid',
                lower: [sourcePageKey],
                upper: [sourcePageKey, cid],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause>
  sourcePageKeyEqualToCidGreaterThan(
    String sourcePageKey,
    int? cid, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sourcePageKey_cid',
          lower: [sourcePageKey, cid],
          includeLower: include,
          upper: [sourcePageKey],
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourcePageKeyEqualToCidLessThan(
    String sourcePageKey,
    int? cid, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sourcePageKey_cid',
          lower: [sourcePageKey],
          upper: [sourcePageKey, cid],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterWhereClause> sourcePageKeyEqualToCidBetween(
    String sourcePageKey,
    int? lowerCid,
    int? upperCid, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sourcePageKey_cid',
          lower: [sourcePageKey, lowerCid],
          includeLower: includeLower,
          upper: [sourcePageKey, upperCid],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension TrackQueryFilter on QueryBuilder<Track, Track, QFilterCondition> {
  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'artist'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'artist'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'artist',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'artist',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'artist',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'artist',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'artist',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'artist',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'artist',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'artist',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'artist', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> artistIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'artist', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'audioUrl'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'audioUrl'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'audioUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'audioUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'audioUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'audioUrl',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'audioUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'audioUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'audioUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'audioUrl',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'audioUrl', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'audioUrl', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlExpiryIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'audioUrlExpiry'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlExpiryIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'audioUrlExpiry'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlExpiryEqualTo(
    DateTime? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'audioUrlExpiry', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlExpiryGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'audioUrlExpiry',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlExpiryLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'audioUrlExpiry',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> audioUrlExpiryBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'audioUrlExpiry',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> bilibiliAidIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'bilibiliAid'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> bilibiliAidIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'bilibiliAid'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> bilibiliAidEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'bilibiliAid', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> bilibiliAidGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'bilibiliAid',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> bilibiliAidLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'bilibiliAid',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> bilibiliAidBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'bilibiliAid',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'channelId'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'channelId'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'channelId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'channelId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'channelId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'channelId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'channelId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'channelId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'channelId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'channelId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'channelId', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> channelIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'channelId', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> cidIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'cid'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> cidIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'cid'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> cidEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'cid', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> cidGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'cid',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> cidLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'cid',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> cidBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'cid',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> createdAtEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationMsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'durationMs'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationMsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'durationMs'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationMsEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'durationMs', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationMsGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'durationMs',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationMsLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'durationMs',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> durationMsBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'durationMs',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'formattedDuration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition>
  formattedDurationGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'formattedDuration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'formattedDuration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'formattedDuration',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'formattedDuration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'formattedDuration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'formattedDuration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'formattedDuration',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> formattedDurationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'formattedDuration', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition>
  formattedDurationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'formattedDuration', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'groupKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'groupKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'groupKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'groupKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'groupKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'groupKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'groupKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'groupKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'groupKey', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> groupKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'groupKey', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> hasValidAudioUrlEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'hasValidAudioUrl', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> idBetween(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> isAvailableEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isAvailable', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> isPartOfMultiPageEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isPartOfMultiPage', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> isVipEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isVip', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'originalSongId'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'originalSongId'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'originalSongId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'originalSongId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'originalSongId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'originalSongId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'originalSongId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'originalSongId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'originalSongId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'originalSongId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'originalSongId', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSongIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'originalSongId', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'originalSource'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'originalSource'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'originalSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'originalSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'originalSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'originalSource',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'originalSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'originalSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'originalSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'originalSource',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'originalSource', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> originalSourceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'originalSource', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> ownerIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'ownerId'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> ownerIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'ownerId'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> ownerIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'ownerId', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> ownerIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'ownerId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> ownerIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'ownerId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> ownerIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'ownerId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageCountIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'pageCount'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageCountIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'pageCount'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageCountEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'pageCount', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageCountGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'pageCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageCountLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'pageCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageCountBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'pageCount',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageNumIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'pageNum'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageNumIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'pageNum'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageNumEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'pageNum', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageNumGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'pageNum',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageNumLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'pageNum',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> pageNumBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'pageNum',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'parentTitle'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'parentTitle'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'parentTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'parentTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'parentTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'parentTitle',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'parentTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'parentTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'parentTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'parentTitle',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'parentTitle', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> parentTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'parentTitle', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> playlistInfoLengthEqualTo(
    int length,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'playlistInfo', length, true, length, true);
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> playlistInfoIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'playlistInfo', 0, true, 0, true);
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> playlistInfoIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'playlistInfo', 0, false, 999999, true);
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> playlistInfoLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'playlistInfo', 0, true, length, include);
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition>
  playlistInfoLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'playlistInfo', length, include, 999999, true);
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> playlistInfoLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'playlistInfo',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdGreaterThan(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdLessThan(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdBetween(
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
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

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sourceId', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sourceId', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sourcePageKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sourcePageKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sourcePageKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sourcePageKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sourcePageKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sourcePageKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sourcePageKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sourcePageKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sourcePageKey', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourcePageKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sourcePageKey', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sourceType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sourceType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sourceType', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> sourceTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sourceType', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'thumbnailUrl'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'thumbnailUrl'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'thumbnailUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'thumbnailUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'thumbnailUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'thumbnailUrl',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'thumbnailUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'thumbnailUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'thumbnailUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'thumbnailUrl',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'thumbnailUrl', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> thumbnailUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'thumbnailUrl', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'title',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'title',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'title',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'title',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'title',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'title',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'title',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'title',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'title', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'title', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'unavailableReason'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition>
  unavailableReasonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'unavailableReason'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'unavailableReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition>
  unavailableReasonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'unavailableReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'unavailableReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'unavailableReason',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'unavailableReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'unavailableReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'unavailableReason',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'unavailableReason',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> unavailableReasonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'unavailableReason', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition>
  unavailableReasonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'unavailableReason', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'uniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'uniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'uniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'uniqueKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'uniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'uniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'uniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'uniqueKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'uniqueKey', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> uniqueKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'uniqueKey', value: ''),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'updatedAt'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'updatedAt'),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> updatedAtEqualTo(
    DateTime? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAt', value: value),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> updatedAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> updatedAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Track, Track, QAfterFilterCondition> updatedAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension TrackQueryObject on QueryBuilder<Track, Track, QFilterCondition> {
  QueryBuilder<Track, Track, QAfterFilterCondition> playlistInfoElement(
    FilterQuery<PlaylistDownloadInfo> q,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.object(q, r'playlistInfo');
    });
  }
}

extension TrackQueryLinks on QueryBuilder<Track, Track, QFilterCondition> {}

extension TrackQuerySortBy on QueryBuilder<Track, Track, QSortBy> {
  QueryBuilder<Track, Track, QAfterSortBy> sortByArtist() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByArtistDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByAudioUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrl', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByAudioUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrl', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByAudioUrlExpiry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrlExpiry', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByAudioUrlExpiryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrlExpiry', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByBilibiliAid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliAid', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByBilibiliAidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliAid', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByChannelId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'channelId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByChannelIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'channelId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByCid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cid', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByCidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cid', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByDurationMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByFormattedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByFormattedDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByGroupKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'groupKey', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByGroupKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'groupKey', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByHasValidAudioUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidAudioUrl', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByHasValidAudioUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidAudioUrl', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByIsAvailable() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAvailable', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByIsAvailableDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAvailable', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByIsPartOfMultiPage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPartOfMultiPage', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByIsPartOfMultiPageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPartOfMultiPage', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByIsVip() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isVip', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByIsVipDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isVip', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByOriginalSongId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSongId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByOriginalSongIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSongId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByOriginalSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSource', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByOriginalSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSource', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByOwnerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByOwnerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByPageCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageCount', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByPageCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageCount', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByPageNum() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageNum', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByPageNumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageNum', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByParentTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentTitle', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByParentTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentTitle', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySourceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySourceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySourcePageKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourcePageKey', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySourcePageKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourcePageKey', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortBySourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByThumbnailUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnailUrl', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByThumbnailUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnailUrl', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByUnavailableReason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unavailableReason', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByUnavailableReasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unavailableReason', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByUniqueKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uniqueKey', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByUniqueKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uniqueKey', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension TrackQuerySortThenBy on QueryBuilder<Track, Track, QSortThenBy> {
  QueryBuilder<Track, Track, QAfterSortBy> thenByArtist() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByArtistDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'artist', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByAudioUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrl', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByAudioUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrl', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByAudioUrlExpiry() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrlExpiry', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByAudioUrlExpiryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'audioUrlExpiry', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByBilibiliAid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliAid', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByBilibiliAidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bilibiliAid', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByChannelId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'channelId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByChannelIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'channelId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByCid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cid', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByCidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'cid', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByDurationMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByFormattedDuration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByFormattedDurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedDuration', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByGroupKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'groupKey', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByGroupKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'groupKey', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByHasValidAudioUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidAudioUrl', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByHasValidAudioUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasValidAudioUrl', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIsAvailable() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAvailable', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIsAvailableDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAvailable', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIsPartOfMultiPage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPartOfMultiPage', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIsPartOfMultiPageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPartOfMultiPage', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIsVip() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isVip', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByIsVipDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isVip', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByOriginalSongId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSongId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByOriginalSongIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSongId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByOriginalSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSource', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByOriginalSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalSource', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByOwnerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByOwnerIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByPageCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageCount', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByPageCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageCount', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByPageNum() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageNum', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByPageNumDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageNum', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByParentTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentTitle', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByParentTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentTitle', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySourceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySourceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySourcePageKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourcePageKey', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySourcePageKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourcePageKey', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenBySourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceType', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByThumbnailUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnailUrl', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByThumbnailUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'thumbnailUrl', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByUnavailableReason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unavailableReason', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByUnavailableReasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'unavailableReason', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByUniqueKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uniqueKey', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByUniqueKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'uniqueKey', Sort.desc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Track, Track, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension TrackQueryWhereDistinct on QueryBuilder<Track, Track, QDistinct> {
  QueryBuilder<Track, Track, QDistinct> distinctByArtist({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'artist', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByAudioUrl({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'audioUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByAudioUrlExpiry() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'audioUrlExpiry');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByBilibiliAid() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bilibiliAid');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByChannelId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'channelId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByCid() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'cid');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'durationMs');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByFormattedDuration({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'formattedDuration',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByGroupKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'groupKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByHasValidAudioUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasValidAudioUrl');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByIsAvailable() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isAvailable');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByIsPartOfMultiPage() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isPartOfMultiPage');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByIsVip() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isVip');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByOriginalSongId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'originalSongId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByOriginalSource({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'originalSource',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByOwnerId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ownerId');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByPageCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pageCount');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByPageNum() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pageNum');
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByParentTitle({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'parentTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctBySourceId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctBySourcePageKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'sourcePageKey',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctBySourceType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByThumbnailUrl({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'thumbnailUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByTitle({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByUnavailableReason({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'unavailableReason',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByUniqueKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'uniqueKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Track, Track, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension TrackQueryProperty on QueryBuilder<Track, Track, QQueryProperty> {
  QueryBuilder<Track, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> artistProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'artist');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> audioUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'audioUrl');
    });
  }

  QueryBuilder<Track, DateTime?, QQueryOperations> audioUrlExpiryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'audioUrlExpiry');
    });
  }

  QueryBuilder<Track, int?, QQueryOperations> bilibiliAidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bilibiliAid');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> channelIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'channelId');
    });
  }

  QueryBuilder<Track, int?, QQueryOperations> cidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'cid');
    });
  }

  QueryBuilder<Track, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Track, int?, QQueryOperations> durationMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'durationMs');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> formattedDurationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'formattedDuration');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> groupKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'groupKey');
    });
  }

  QueryBuilder<Track, bool, QQueryOperations> hasValidAudioUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasValidAudioUrl');
    });
  }

  QueryBuilder<Track, bool, QQueryOperations> isAvailableProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isAvailable');
    });
  }

  QueryBuilder<Track, bool, QQueryOperations> isPartOfMultiPageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isPartOfMultiPage');
    });
  }

  QueryBuilder<Track, bool, QQueryOperations> isVipProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isVip');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> originalSongIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originalSongId');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> originalSourceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originalSource');
    });
  }

  QueryBuilder<Track, int?, QQueryOperations> ownerIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ownerId');
    });
  }

  QueryBuilder<Track, int?, QQueryOperations> pageCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pageCount');
    });
  }

  QueryBuilder<Track, int?, QQueryOperations> pageNumProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pageNum');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> parentTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'parentTitle');
    });
  }

  QueryBuilder<Track, List<PlaylistDownloadInfo>, QQueryOperations>
  playlistInfoProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'playlistInfo');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> sourceIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceId');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> sourcePageKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourcePageKey');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> sourceTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceType');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> thumbnailUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'thumbnailUrl');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<Track, String?, QQueryOperations> unavailableReasonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'unavailableReason');
    });
  }

  QueryBuilder<Track, String, QQueryOperations> uniqueKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'uniqueKey');
    });
  }

  QueryBuilder<Track, DateTime?, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}

// **************************************************************************
// IsarEmbeddedGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

const PlaylistDownloadInfoSchema = Schema(
  name: r'PlaylistDownloadInfo',
  id: 8137279379628381441,
  properties: {
    r'downloadPath': PropertySchema(
      id: 0,
      name: r'downloadPath',
      type: IsarType.string,
    ),
    r'isDownloaded': PropertySchema(
      id: 1,
      name: r'isDownloaded',
      type: IsarType.bool,
    ),
    r'playlistId': PropertySchema(
      id: 2,
      name: r'playlistId',
      type: IsarType.long,
    ),
    r'playlistName': PropertySchema(
      id: 3,
      name: r'playlistName',
      type: IsarType.string,
    ),
  },
  estimateSize: _playlistDownloadInfoEstimateSize,
  serialize: _playlistDownloadInfoSerialize,
  deserialize: _playlistDownloadInfoDeserialize,
  deserializeProp: _playlistDownloadInfoDeserializeProp,
);

int _playlistDownloadInfoEstimateSize(
  PlaylistDownloadInfo object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.downloadPath.length * 3;
  bytesCount += 3 + object.playlistName.length * 3;
  return bytesCount;
}

void _playlistDownloadInfoSerialize(
  PlaylistDownloadInfo object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.downloadPath);
  writer.writeBool(offsets[1], object.isDownloaded);
  writer.writeLong(offsets[2], object.playlistId);
  writer.writeString(offsets[3], object.playlistName);
}

PlaylistDownloadInfo _playlistDownloadInfoDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PlaylistDownloadInfo();
  object.downloadPath = reader.readString(offsets[0]);
  object.playlistId = reader.readLong(offsets[2]);
  object.playlistName = reader.readString(offsets[3]);
  return object;
}

P _playlistDownloadInfoDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

extension PlaylistDownloadInfoQueryFilter
    on
        QueryBuilder<
          PlaylistDownloadInfo,
          PlaylistDownloadInfo,
          QFilterCondition
        > {
  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'downloadPath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'downloadPath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'downloadPath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'downloadPath',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'downloadPath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'downloadPath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'downloadPath',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'downloadPath',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'downloadPath', value: ''),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  downloadPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'downloadPath', value: ''),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  isDownloadedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isDownloaded', value: value),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'playlistId', value: value),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistIdGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'playlistId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistIdLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'playlistId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'playlistId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'playlistName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'playlistName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'playlistName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'playlistName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'playlistName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'playlistName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'playlistName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'playlistName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'playlistName', value: ''),
      );
    });
  }

  QueryBuilder<
    PlaylistDownloadInfo,
    PlaylistDownloadInfo,
    QAfterFilterCondition
  >
  playlistNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'playlistName', value: ''),
      );
    });
  }
}

extension PlaylistDownloadInfoQueryObject
    on
        QueryBuilder<
          PlaylistDownloadInfo,
          PlaylistDownloadInfo,
          QFilterCondition
        > {}
