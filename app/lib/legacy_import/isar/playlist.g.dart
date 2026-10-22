// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPlaylistCollection on Isar {
  IsarCollection<Playlist> get playlists => this.collection();
}

const PlaylistSchema = CollectionSchema(
  name: r'Playlist',
  id: 4190497698144499986,
  properties: {
    r'coverUrl': PropertySchema(
      id: 0,
      name: r'coverUrl',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'description': PropertySchema(
      id: 2,
      name: r'description',
      type: IsarType.string,
    ),
    r'hasCustomCover': PropertySchema(
      id: 3,
      name: r'hasCustomCover',
      type: IsarType.bool,
    ),
    r'importSourceType': PropertySchema(
      id: 4,
      name: r'importSourceType',
      type: IsarType.string,
    ),
    r'isImported': PropertySchema(
      id: 5,
      name: r'isImported',
      type: IsarType.bool,
    ),
    r'isMix': PropertySchema(id: 6, name: r'isMix', type: IsarType.bool),
    r'lastRefreshed': PropertySchema(
      id: 7,
      name: r'lastRefreshed',
      type: IsarType.dateTime,
    ),
    r'mixPlaylistId': PropertySchema(
      id: 8,
      name: r'mixPlaylistId',
      type: IsarType.string,
    ),
    r'mixSeedVideoId': PropertySchema(
      id: 9,
      name: r'mixSeedVideoId',
      type: IsarType.string,
    ),
    r'name': PropertySchema(id: 10, name: r'name', type: IsarType.string),
    r'needsRefresh': PropertySchema(
      id: 11,
      name: r'needsRefresh',
      type: IsarType.bool,
    ),
    r'notifyOnUpdate': PropertySchema(
      id: 12,
      name: r'notifyOnUpdate',
      type: IsarType.bool,
    ),
    r'ownerName': PropertySchema(
      id: 13,
      name: r'ownerName',
      type: IsarType.string,
    ),
    r'ownerUserId': PropertySchema(
      id: 14,
      name: r'ownerUserId',
      type: IsarType.string,
    ),
    r'refreshIntervalHours': PropertySchema(
      id: 15,
      name: r'refreshIntervalHours',
      type: IsarType.long,
    ),
    r'sortOrder': PropertySchema(
      id: 16,
      name: r'sortOrder',
      type: IsarType.long,
    ),
    r'sourceUrl': PropertySchema(
      id: 17,
      name: r'sourceUrl',
      type: IsarType.string,
    ),
    r'trackCount': PropertySchema(
      id: 18,
      name: r'trackCount',
      type: IsarType.long,
    ),
    r'trackIds': PropertySchema(
      id: 19,
      name: r'trackIds',
      type: IsarType.longList,
    ),
    r'updatedAt': PropertySchema(
      id: 20,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'useAuthForRefresh': PropertySchema(
      id: 21,
      name: r'useAuthForRefresh',
      type: IsarType.bool,
    ),
  },
  estimateSize: _playlistEstimateSize,
  serialize: _playlistSerialize,
  deserialize: _playlistDeserialize,
  deserializeProp: _playlistDeserializeProp,
  idName: r'id',
  indexes: {
    r'name': IndexSchema(
      id: 879695947855722453,
      name: r'name',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'name',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'sortOrder': IndexSchema(
      id: -1119549396205841918,
      name: r'sortOrder',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sortOrder',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _playlistGetId,
  getLinks: _playlistGetLinks,
  attach: _playlistAttach,
  version: '3.3.2',
);

int _playlistEstimateSize(
  Playlist object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.coverUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.description;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.importSourceType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.mixPlaylistId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.mixSeedVideoId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  {
    final value = object.ownerName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.ownerUserId;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.sourceUrl;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.trackIds.length * 8;
  return bytesCount;
}

void _playlistSerialize(
  Playlist object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.coverUrl);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.description);
  writer.writeBool(offsets[3], object.hasCustomCover);
  writer.writeString(offsets[4], object.importSourceType);
  writer.writeBool(offsets[5], object.isImported);
  writer.writeBool(offsets[6], object.isMix);
  writer.writeDateTime(offsets[7], object.lastRefreshed);
  writer.writeString(offsets[8], object.mixPlaylistId);
  writer.writeString(offsets[9], object.mixSeedVideoId);
  writer.writeString(offsets[10], object.name);
  writer.writeBool(offsets[11], object.needsRefresh);
  writer.writeBool(offsets[12], object.notifyOnUpdate);
  writer.writeString(offsets[13], object.ownerName);
  writer.writeString(offsets[14], object.ownerUserId);
  writer.writeLong(offsets[15], object.refreshIntervalHours);
  writer.writeLong(offsets[16], object.sortOrder);
  writer.writeString(offsets[17], object.sourceUrl);
  writer.writeLong(offsets[18], object.trackCount);
  writer.writeLongList(offsets[19], object.trackIds);
  writer.writeDateTime(offsets[20], object.updatedAt);
  writer.writeBool(offsets[21], object.useAuthForRefresh);
}

Playlist _playlistDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Playlist();
  object.coverUrl = reader.readStringOrNull(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.description = reader.readStringOrNull(offsets[2]);
  object.hasCustomCover = reader.readBool(offsets[3]);
  object.id = id;
  object.importSourceType = reader.readStringOrNull(offsets[4]);
  object.isMix = reader.readBool(offsets[6]);
  object.lastRefreshed = reader.readDateTimeOrNull(offsets[7]);
  object.mixPlaylistId = reader.readStringOrNull(offsets[8]);
  object.mixSeedVideoId = reader.readStringOrNull(offsets[9]);
  object.name = reader.readString(offsets[10]);
  object.notifyOnUpdate = reader.readBool(offsets[12]);
  object.ownerName = reader.readStringOrNull(offsets[13]);
  object.ownerUserId = reader.readStringOrNull(offsets[14]);
  object.refreshIntervalHours = reader.readLongOrNull(offsets[15]);
  object.sortOrder = reader.readLong(offsets[16]);
  object.sourceUrl = reader.readStringOrNull(offsets[17]);
  object.trackIds = reader.readLongList(offsets[19]) ?? [];
  object.updatedAt = reader.readDateTimeOrNull(offsets[20]);
  object.useAuthForRefresh = reader.readBool(offsets[21]);
  return object;
}

P _playlistDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readBool(offset)) as P;
    case 7:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readBool(offset)) as P;
    case 12:
      return (reader.readBool(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readLongOrNull(offset)) as P;
    case 16:
      return (reader.readLong(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    case 18:
      return (reader.readLong(offset)) as P;
    case 19:
      return (reader.readLongList(offset) ?? []) as P;
    case 20:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 21:
      return (reader.readBool(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _playlistGetId(Playlist object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _playlistGetLinks(Playlist object) {
  return [];
}

void _playlistAttach(IsarCollection<dynamic> col, Id id, Playlist object) {
  object.id = id;
}

extension PlaylistByIndex on IsarCollection<Playlist> {
  Future<Playlist?> getByName(String name) {
    return getByIndex(r'name', [name]);
  }

  Playlist? getByNameSync(String name) {
    return getByIndexSync(r'name', [name]);
  }

  Future<bool> deleteByName(String name) {
    return deleteByIndex(r'name', [name]);
  }

  bool deleteByNameSync(String name) {
    return deleteByIndexSync(r'name', [name]);
  }

  Future<List<Playlist?>> getAllByName(List<String> nameValues) {
    final values = nameValues.map((e) => [e]).toList();
    return getAllByIndex(r'name', values);
  }

  List<Playlist?> getAllByNameSync(List<String> nameValues) {
    final values = nameValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'name', values);
  }

  Future<int> deleteAllByName(List<String> nameValues) {
    final values = nameValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'name', values);
  }

  int deleteAllByNameSync(List<String> nameValues) {
    final values = nameValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'name', values);
  }

  Future<Id> putByName(Playlist object) {
    return putByIndex(r'name', object);
  }

  Id putByNameSync(Playlist object, {bool saveLinks = true}) {
    return putByIndexSync(r'name', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByName(List<Playlist> objects) {
    return putAllByIndex(r'name', objects);
  }

  List<Id> putAllByNameSync(List<Playlist> objects, {bool saveLinks = true}) {
    return putAllByIndexSync(r'name', objects, saveLinks: saveLinks);
  }
}

extension PlaylistQueryWhereSort on QueryBuilder<Playlist, Playlist, QWhere> {
  QueryBuilder<Playlist, Playlist, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhere> anySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'sortOrder'),
      );
    });
  }
}

extension PlaylistQueryWhere on QueryBuilder<Playlist, Playlist, QWhereClause> {
  QueryBuilder<Playlist, Playlist, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> idBetween(
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

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> nameEqualTo(String name) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'name', value: [name]),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> nameNotEqualTo(
    String name,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'name',
                lower: [],
                upper: [name],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'name',
                lower: [name],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'name',
                lower: [name],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'name',
                lower: [],
                upper: [name],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> sortOrderEqualTo(
    int sortOrder,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'sortOrder', value: [sortOrder]),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> sortOrderNotEqualTo(
    int sortOrder,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sortOrder',
                lower: [],
                upper: [sortOrder],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sortOrder',
                lower: [sortOrder],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sortOrder',
                lower: [sortOrder],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sortOrder',
                lower: [],
                upper: [sortOrder],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> sortOrderGreaterThan(
    int sortOrder, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sortOrder',
          lower: [sortOrder],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> sortOrderLessThan(
    int sortOrder, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sortOrder',
          lower: [],
          upper: [sortOrder],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterWhereClause> sortOrderBetween(
    int lowerSortOrder,
    int upperSortOrder, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'sortOrder',
          lower: [lowerSortOrder],
          includeLower: includeLower,
          upper: [upperSortOrder],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension PlaylistQueryFilter
    on QueryBuilder<Playlist, Playlist, QFilterCondition> {
  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'coverUrl'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'coverUrl'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'coverUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'coverUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'coverUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'coverUrl',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'coverUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'coverUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'coverUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'coverUrl',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'coverUrl', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> coverUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'coverUrl', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> createdAtEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> createdAtGreaterThan(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'description'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  descriptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'description'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  descriptionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'description',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'description',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'description',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'description', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'description', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> hasCustomCoverEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'hasCustomCover', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> idBetween(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'importSourceType'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'importSourceType'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'importSourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'importSourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'importSourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'importSourceType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'importSourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'importSourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'importSourceType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'importSourceType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'importSourceType', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  importSourceTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'importSourceType', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> isImportedEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isImported', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> isMixEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isMix', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  lastRefreshedIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastRefreshed'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  lastRefreshedIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastRefreshed'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> lastRefreshedEqualTo(
    DateTime? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastRefreshed', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  lastRefreshedGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastRefreshed',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> lastRefreshedLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastRefreshed',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> lastRefreshedBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastRefreshed',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixPlaylistIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mixPlaylistId'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixPlaylistIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mixPlaylistId'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixPlaylistIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mixPlaylistId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixPlaylistIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mixPlaylistId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixPlaylistIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mixPlaylistId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixPlaylistIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mixPlaylistId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixPlaylistIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mixPlaylistId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixPlaylistIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mixPlaylistId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixPlaylistIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mixPlaylistId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixPlaylistIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mixPlaylistId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixPlaylistIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mixPlaylistId', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixPlaylistIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mixPlaylistId', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mixSeedVideoId'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mixSeedVideoId'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixSeedVideoIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mixSeedVideoId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mixSeedVideoId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mixSeedVideoId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixSeedVideoIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mixSeedVideoId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mixSeedVideoId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mixSeedVideoId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mixSeedVideoId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> mixSeedVideoIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mixSeedVideoId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mixSeedVideoId', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  mixSeedVideoIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mixSeedVideoId', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'name',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'name',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> needsRefreshEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'needsRefresh', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> notifyOnUpdateEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'notifyOnUpdate', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'ownerName'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'ownerName'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'ownerName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'ownerName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'ownerName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'ownerName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'ownerName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'ownerName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'ownerName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'ownerName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'ownerName', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  ownerNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'ownerName', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'ownerUserId'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  ownerUserIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'ownerUserId'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'ownerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  ownerUserIdGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'ownerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'ownerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'ownerUserId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'ownerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'ownerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'ownerUserId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'ownerUserId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> ownerUserIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'ownerUserId', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  ownerUserIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'ownerUserId', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  refreshIntervalHoursIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'refreshIntervalHours'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  refreshIntervalHoursIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'refreshIntervalHours'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  refreshIntervalHoursEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'refreshIntervalHours',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  refreshIntervalHoursGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'refreshIntervalHours',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  refreshIntervalHoursLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'refreshIntervalHours',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  refreshIntervalHoursBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'refreshIntervalHours',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sortOrderEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sortOrder', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sortOrderGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sortOrder',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sortOrderLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sortOrder',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sortOrderBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sortOrder',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'sourceUrl'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'sourceUrl'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sourceUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sourceUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sourceUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sourceUrl',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sourceUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sourceUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sourceUrl',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sourceUrl',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> sourceUrlIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sourceUrl', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  sourceUrlIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sourceUrl', value: ''),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackCountEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'trackCount', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'trackCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'trackCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'trackCount',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  trackIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'trackIds', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  trackIdsElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'trackIds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  trackIdsElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'trackIds',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  trackIdsElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'trackIds',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackIdsLengthEqualTo(
    int length,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', length, true, length, true);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', 0, true, 0, true);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', 0, false, 999999, true);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  trackIdsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', 0, true, length, include);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  trackIdsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', length, include, 999999, true);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> trackIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'trackIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> updatedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'updatedAt'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> updatedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'updatedAt'),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> updatedAtEqualTo(
    DateTime? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAt', value: value),
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> updatedAtGreaterThan(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> updatedAtLessThan(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition> updatedAtBetween(
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

  QueryBuilder<Playlist, Playlist, QAfterFilterCondition>
  useAuthForRefreshEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'useAuthForRefresh', value: value),
      );
    });
  }
}

extension PlaylistQueryObject
    on QueryBuilder<Playlist, Playlist, QFilterCondition> {}

extension PlaylistQueryLinks
    on QueryBuilder<Playlist, Playlist, QFilterCondition> {}

extension PlaylistQuerySortBy on QueryBuilder<Playlist, Playlist, QSortBy> {
  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByCoverUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverUrl', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByCoverUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverUrl', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByHasCustomCover() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomCover', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByHasCustomCoverDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomCover', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByImportSourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'importSourceType', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByImportSourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'importSourceType', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByIsImported() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isImported', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByIsImportedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isImported', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByIsMix() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMix', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByIsMixDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMix', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByLastRefreshed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRefreshed', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByLastRefreshedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRefreshed', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByMixPlaylistId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByMixPlaylistIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByMixSeedVideoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByMixSeedVideoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByNeedsRefresh() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'needsRefresh', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByNeedsRefreshDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'needsRefresh', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByNotifyOnUpdate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notifyOnUpdate', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByNotifyOnUpdateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notifyOnUpdate', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByOwnerName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerName', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByOwnerNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerName', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByOwnerUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserId', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByOwnerUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserId', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByRefreshIntervalHours() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'refreshIntervalHours', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy>
  sortByRefreshIntervalHoursDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'refreshIntervalHours', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortBySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortBySortOrderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortBySourceUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortBySourceUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByTrackCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackCount', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByTrackCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackCount', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByUseAuthForRefresh() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useAuthForRefresh', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> sortByUseAuthForRefreshDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useAuthForRefresh', Sort.desc);
    });
  }
}

extension PlaylistQuerySortThenBy
    on QueryBuilder<Playlist, Playlist, QSortThenBy> {
  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByCoverUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverUrl', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByCoverUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverUrl', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByHasCustomCover() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomCover', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByHasCustomCoverDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasCustomCover', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByImportSourceType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'importSourceType', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByImportSourceTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'importSourceType', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByIsImported() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isImported', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByIsImportedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isImported', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByIsMix() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMix', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByIsMixDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMix', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByLastRefreshed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRefreshed', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByLastRefreshedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRefreshed', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByMixPlaylistId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByMixPlaylistIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByMixSeedVideoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByMixSeedVideoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByNeedsRefresh() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'needsRefresh', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByNeedsRefreshDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'needsRefresh', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByNotifyOnUpdate() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notifyOnUpdate', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByNotifyOnUpdateDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'notifyOnUpdate', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByOwnerName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerName', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByOwnerNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerName', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByOwnerUserId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserId', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByOwnerUserIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserId', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByRefreshIntervalHours() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'refreshIntervalHours', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy>
  thenByRefreshIntervalHoursDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'refreshIntervalHours', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenBySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenBySortOrderDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sortOrder', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenBySourceUrl() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenBySourceUrlDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceUrl', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByTrackCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackCount', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByTrackCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackCount', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByUseAuthForRefresh() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useAuthForRefresh', Sort.asc);
    });
  }

  QueryBuilder<Playlist, Playlist, QAfterSortBy> thenByUseAuthForRefreshDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'useAuthForRefresh', Sort.desc);
    });
  }
}

extension PlaylistQueryWhereDistinct
    on QueryBuilder<Playlist, Playlist, QDistinct> {
  QueryBuilder<Playlist, Playlist, QDistinct> distinctByCoverUrl({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'coverUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByDescription({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByHasCustomCover() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasCustomCover');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByImportSourceType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'importSourceType',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByIsImported() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isImported');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByIsMix() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isMix');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByLastRefreshed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastRefreshed');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByMixPlaylistId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'mixPlaylistId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByMixSeedVideoId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'mixSeedVideoId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByNeedsRefresh() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'needsRefresh');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByNotifyOnUpdate() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'notifyOnUpdate');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByOwnerName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ownerName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByOwnerUserId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ownerUserId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByRefreshIntervalHours() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'refreshIntervalHours');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctBySortOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sortOrder');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctBySourceUrl({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceUrl', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByTrackCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'trackCount');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByTrackIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'trackIds');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<Playlist, Playlist, QDistinct> distinctByUseAuthForRefresh() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'useAuthForRefresh');
    });
  }
}

extension PlaylistQueryProperty
    on QueryBuilder<Playlist, Playlist, QQueryProperty> {
  QueryBuilder<Playlist, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> coverUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'coverUrl');
    });
  }

  QueryBuilder<Playlist, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<Playlist, bool, QQueryOperations> hasCustomCoverProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasCustomCover');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> importSourceTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'importSourceType');
    });
  }

  QueryBuilder<Playlist, bool, QQueryOperations> isImportedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isImported');
    });
  }

  QueryBuilder<Playlist, bool, QQueryOperations> isMixProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isMix');
    });
  }

  QueryBuilder<Playlist, DateTime?, QQueryOperations> lastRefreshedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastRefreshed');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> mixPlaylistIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mixPlaylistId');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> mixSeedVideoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mixSeedVideoId');
    });
  }

  QueryBuilder<Playlist, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<Playlist, bool, QQueryOperations> needsRefreshProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'needsRefresh');
    });
  }

  QueryBuilder<Playlist, bool, QQueryOperations> notifyOnUpdateProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'notifyOnUpdate');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> ownerNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ownerName');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> ownerUserIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ownerUserId');
    });
  }

  QueryBuilder<Playlist, int?, QQueryOperations>
  refreshIntervalHoursProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'refreshIntervalHours');
    });
  }

  QueryBuilder<Playlist, int, QQueryOperations> sortOrderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sortOrder');
    });
  }

  QueryBuilder<Playlist, String?, QQueryOperations> sourceUrlProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceUrl');
    });
  }

  QueryBuilder<Playlist, int, QQueryOperations> trackCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trackCount');
    });
  }

  QueryBuilder<Playlist, List<int>, QQueryOperations> trackIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trackIds');
    });
  }

  QueryBuilder<Playlist, DateTime?, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<Playlist, bool, QQueryOperations> useAuthForRefreshProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'useAuthForRefresh');
    });
  }
}
