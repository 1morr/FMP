// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'play_queue.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPlayQueueCollection on Isar {
  IsarCollection<PlayQueue> get playQueues => this.collection();
}

const PlayQueueSchema = CollectionSchema(
  name: r'PlayQueue',
  id: -2727102832055268615,
  properties: {
    r'currentIndex': PropertySchema(
      id: 0,
      name: r'currentIndex',
      type: IsarType.long,
    ),
    r'currentTrackId': PropertySchema(
      id: 1,
      name: r'currentTrackId',
      type: IsarType.long,
    ),
    r'hasNext': PropertySchema(id: 2, name: r'hasNext', type: IsarType.bool),
    r'hasPrevious': PropertySchema(
      id: 3,
      name: r'hasPrevious',
      type: IsarType.bool,
    ),
    r'isEmpty': PropertySchema(id: 4, name: r'isEmpty', type: IsarType.bool),
    r'isMixMode': PropertySchema(
      id: 5,
      name: r'isMixMode',
      type: IsarType.bool,
    ),
    r'isNotEmpty': PropertySchema(
      id: 6,
      name: r'isNotEmpty',
      type: IsarType.bool,
    ),
    r'isShuffleEnabled': PropertySchema(
      id: 7,
      name: r'isShuffleEnabled',
      type: IsarType.bool,
    ),
    r'lastPositionMs': PropertySchema(
      id: 8,
      name: r'lastPositionMs',
      type: IsarType.long,
    ),
    r'lastUpdated': PropertySchema(
      id: 9,
      name: r'lastUpdated',
      type: IsarType.dateTime,
    ),
    r'lastVolume': PropertySchema(
      id: 10,
      name: r'lastVolume',
      type: IsarType.double,
    ),
    r'length': PropertySchema(id: 11, name: r'length', type: IsarType.long),
    r'loopMode': PropertySchema(
      id: 12,
      name: r'loopMode',
      type: IsarType.string,
      enumMap: _PlayQueueloopModeEnumValueMap,
    ),
    r'mixPlaylistId': PropertySchema(
      id: 13,
      name: r'mixPlaylistId',
      type: IsarType.string,
    ),
    r'mixSeedVideoId': PropertySchema(
      id: 14,
      name: r'mixSeedVideoId',
      type: IsarType.string,
    ),
    r'mixTitle': PropertySchema(
      id: 15,
      name: r'mixTitle',
      type: IsarType.string,
    ),
    r'originalOrder': PropertySchema(
      id: 16,
      name: r'originalOrder',
      type: IsarType.longList,
    ),
    r'trackIds': PropertySchema(
      id: 17,
      name: r'trackIds',
      type: IsarType.longList,
    ),
  },
  estimateSize: _playQueueEstimateSize,
  serialize: _playQueueSerialize,
  deserialize: _playQueueDeserialize,
  deserializeProp: _playQueueDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _playQueueGetId,
  getLinks: _playQueueGetLinks,
  attach: _playQueueAttach,
  version: '3.3.2',
);

int _playQueueEstimateSize(
  PlayQueue object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.loopMode.name.length * 3;
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
  {
    final value = object.mixTitle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.originalOrder;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  bytesCount += 3 + object.trackIds.length * 8;
  return bytesCount;
}

void _playQueueSerialize(
  PlayQueue object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.currentIndex);
  writer.writeLong(offsets[1], object.currentTrackId);
  writer.writeBool(offsets[2], object.hasNext);
  writer.writeBool(offsets[3], object.hasPrevious);
  writer.writeBool(offsets[4], object.isEmpty);
  writer.writeBool(offsets[5], object.isMixMode);
  writer.writeBool(offsets[6], object.isNotEmpty);
  writer.writeBool(offsets[7], object.isShuffleEnabled);
  writer.writeLong(offsets[8], object.lastPositionMs);
  writer.writeDateTime(offsets[9], object.lastUpdated);
  writer.writeDouble(offsets[10], object.lastVolume);
  writer.writeLong(offsets[11], object.length);
  writer.writeString(offsets[12], object.loopMode.name);
  writer.writeString(offsets[13], object.mixPlaylistId);
  writer.writeString(offsets[14], object.mixSeedVideoId);
  writer.writeString(offsets[15], object.mixTitle);
  writer.writeLongList(offsets[16], object.originalOrder);
  writer.writeLongList(offsets[17], object.trackIds);
}

PlayQueue _playQueueDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PlayQueue();
  object.currentIndex = reader.readLong(offsets[0]);
  object.id = id;
  object.isMixMode = reader.readBool(offsets[5]);
  object.isShuffleEnabled = reader.readBool(offsets[7]);
  object.lastPositionMs = reader.readLong(offsets[8]);
  object.lastUpdated = reader.readDateTimeOrNull(offsets[9]);
  object.lastVolume = reader.readDouble(offsets[10]);
  object.loopMode =
      _PlayQueueloopModeValueEnumMap[reader.readStringOrNull(offsets[12])] ??
      LoopMode.none;
  object.mixPlaylistId = reader.readStringOrNull(offsets[13]);
  object.mixSeedVideoId = reader.readStringOrNull(offsets[14]);
  object.mixTitle = reader.readStringOrNull(offsets[15]);
  object.originalOrder = reader.readLongList(offsets[16]);
  object.trackIds = reader.readLongList(offsets[17]) ?? [];
  return object;
}

P _playQueueDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readLongOrNull(offset)) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readBool(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 10:
      return (reader.readDouble(offset)) as P;
    case 11:
      return (reader.readLong(offset)) as P;
    case 12:
      return (_PlayQueueloopModeValueEnumMap[reader.readStringOrNull(offset)] ??
              LoopMode.none)
          as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readStringOrNull(offset)) as P;
    case 16:
      return (reader.readLongList(offset)) as P;
    case 17:
      return (reader.readLongList(offset) ?? []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _PlayQueueloopModeEnumValueMap = {
  r'none': r'none',
  r'all': r'all',
  r'one': r'one',
};
const _PlayQueueloopModeValueEnumMap = {
  r'none': LoopMode.none,
  r'all': LoopMode.all,
  r'one': LoopMode.one,
};

Id _playQueueGetId(PlayQueue object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _playQueueGetLinks(PlayQueue object) {
  return [];
}

void _playQueueAttach(IsarCollection<dynamic> col, Id id, PlayQueue object) {
  object.id = id;
}

extension PlayQueueQueryWhereSort
    on QueryBuilder<PlayQueue, PlayQueue, QWhere> {
  QueryBuilder<PlayQueue, PlayQueue, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension PlayQueueQueryWhere
    on QueryBuilder<PlayQueue, PlayQueue, QWhereClause> {
  QueryBuilder<PlayQueue, PlayQueue, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterWhereClause> idBetween(
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

extension PlayQueueQueryFilter
    on QueryBuilder<PlayQueue, PlayQueue, QFilterCondition> {
  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> currentIndexEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'currentIndex', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentIndexGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'currentIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentIndexLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'currentIndex',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> currentIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'currentIndex',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentTrackIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'currentTrackId'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentTrackIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'currentTrackId'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentTrackIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'currentTrackId', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentTrackIdGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'currentTrackId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentTrackIdLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'currentTrackId',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  currentTrackIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'currentTrackId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> hasNextEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'hasNext', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> hasPreviousEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'hasPrevious', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> idBetween(
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> isEmptyEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isEmpty', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> isMixModeEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isMixMode', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> isNotEmptyEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isNotEmpty', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  isShuffleEnabledEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'isShuffleEnabled', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastPositionMsEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastPositionMs', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastPositionMsGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastPositionMs',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastPositionMsLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastPositionMs',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastPositionMsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastPositionMs',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastUpdatedIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastUpdated'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastUpdatedIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastUpdated'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lastUpdatedEqualTo(
    DateTime? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastUpdated', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastUpdatedGreaterThan(DateTime? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastUpdated',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lastUpdatedLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastUpdated',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lastUpdatedBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastUpdated',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lastVolumeEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lastVolume',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  lastVolumeGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastVolume',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lastVolumeLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastVolume',
          value: value,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lastVolumeBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastVolume',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          epsilon: epsilon,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lengthEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'length', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lengthGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'length',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lengthLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'length',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> lengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'length',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeEqualTo(
    LoopMode value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'loopMode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeGreaterThan(
    LoopMode value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'loopMode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeLessThan(
    LoopMode value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'loopMode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeBetween(
    LoopMode lower,
    LoopMode upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'loopMode',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'loopMode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'loopMode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'loopMode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'loopMode',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> loopModeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'loopMode', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  loopModeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'loopMode', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mixPlaylistId'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mixPlaylistId'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdEqualTo(String? value, {bool caseSensitive = true}) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdLessThan(
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdBetween(
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdEndsWith(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mixPlaylistId', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixPlaylistIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mixPlaylistId', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mixSeedVideoId'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mixSeedVideoId'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdEqualTo(String? value, {bool caseSensitive = true}) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdBetween(
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mixSeedVideoId', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixSeedVideoIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mixSeedVideoId', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'mixTitle'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixTitleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'mixTitle'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mixTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mixTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mixTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mixTitle',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mixTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mixTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mixTitle',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mixTitle',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> mixTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mixTitle', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  mixTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mixTitle', value: ''),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'originalOrder'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'originalOrder'),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'originalOrder', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'originalOrder',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'originalOrder',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'originalOrder',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'originalOrder', length, true, length, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'originalOrder', 0, true, 0, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'originalOrder', 0, false, 999999, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'originalOrder', 0, true, length, include);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'originalOrder', length, include, 999999, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  originalOrderLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'originalOrder',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  trackIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'trackIds', value: value),
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
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

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  trackIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', length, true, length, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition> trackIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', 0, true, 0, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  trackIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', 0, false, 999999, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  trackIdsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', 0, true, length, include);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  trackIdsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'trackIds', length, include, 999999, true);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterFilterCondition>
  trackIdsLengthBetween(
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
}

extension PlayQueueQueryObject
    on QueryBuilder<PlayQueue, PlayQueue, QFilterCondition> {}

extension PlayQueueQueryLinks
    on QueryBuilder<PlayQueue, PlayQueue, QFilterCondition> {}

extension PlayQueueQuerySortBy on QueryBuilder<PlayQueue, PlayQueue, QSortBy> {
  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByCurrentIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentIndex', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByCurrentIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentIndex', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByCurrentTrackId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentTrackId', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByCurrentTrackIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentTrackId', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByHasNext() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasNext', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByHasNextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasNext', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByHasPrevious() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasPrevious', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByHasPreviousDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasPrevious', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isEmpty', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsEmptyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isEmpty', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsMixMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMixMode', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsMixModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMixMode', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNotEmpty', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsNotEmptyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNotEmpty', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByIsShuffleEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isShuffleEnabled', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy>
  sortByIsShuffleEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isShuffleEnabled', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLastPositionMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPositionMs', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLastPositionMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPositionMs', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLastUpdated() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdated', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLastUpdatedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdated', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLastVolume() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastVolume', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLastVolumeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastVolume', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLength() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'length', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLengthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'length', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLoopMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loopMode', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByLoopModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loopMode', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByMixPlaylistId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByMixPlaylistIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByMixSeedVideoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByMixSeedVideoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByMixTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixTitle', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> sortByMixTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixTitle', Sort.desc);
    });
  }
}

extension PlayQueueQuerySortThenBy
    on QueryBuilder<PlayQueue, PlayQueue, QSortThenBy> {
  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByCurrentIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentIndex', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByCurrentIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentIndex', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByCurrentTrackId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentTrackId', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByCurrentTrackIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'currentTrackId', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByHasNext() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasNext', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByHasNextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasNext', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByHasPrevious() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasPrevious', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByHasPreviousDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'hasPrevious', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isEmpty', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsEmptyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isEmpty', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsMixMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMixMode', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsMixModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isMixMode', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNotEmpty', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsNotEmptyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isNotEmpty', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByIsShuffleEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isShuffleEnabled', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy>
  thenByIsShuffleEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isShuffleEnabled', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLastPositionMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPositionMs', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLastPositionMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastPositionMs', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLastUpdated() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdated', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLastUpdatedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastUpdated', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLastVolume() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastVolume', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLastVolumeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastVolume', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLength() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'length', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLengthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'length', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLoopMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loopMode', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByLoopModeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'loopMode', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByMixPlaylistId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByMixPlaylistIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixPlaylistId', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByMixSeedVideoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByMixSeedVideoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixSeedVideoId', Sort.desc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByMixTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixTitle', Sort.asc);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QAfterSortBy> thenByMixTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mixTitle', Sort.desc);
    });
  }
}

extension PlayQueueQueryWhereDistinct
    on QueryBuilder<PlayQueue, PlayQueue, QDistinct> {
  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByCurrentIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'currentIndex');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByCurrentTrackId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'currentTrackId');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByHasNext() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasNext');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByHasPrevious() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'hasPrevious');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isEmpty');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByIsMixMode() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isMixMode');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isNotEmpty');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByIsShuffleEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isShuffleEnabled');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByLastPositionMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastPositionMs');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByLastUpdated() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastUpdated');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByLastVolume() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastVolume');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByLength() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'length');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByLoopMode({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'loopMode', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByMixPlaylistId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'mixPlaylistId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByMixSeedVideoId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'mixSeedVideoId',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByMixTitle({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mixTitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByOriginalOrder() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'originalOrder');
    });
  }

  QueryBuilder<PlayQueue, PlayQueue, QDistinct> distinctByTrackIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'trackIds');
    });
  }
}

extension PlayQueueQueryProperty
    on QueryBuilder<PlayQueue, PlayQueue, QQueryProperty> {
  QueryBuilder<PlayQueue, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PlayQueue, int, QQueryOperations> currentIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'currentIndex');
    });
  }

  QueryBuilder<PlayQueue, int?, QQueryOperations> currentTrackIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'currentTrackId');
    });
  }

  QueryBuilder<PlayQueue, bool, QQueryOperations> hasNextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasNext');
    });
  }

  QueryBuilder<PlayQueue, bool, QQueryOperations> hasPreviousProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'hasPrevious');
    });
  }

  QueryBuilder<PlayQueue, bool, QQueryOperations> isEmptyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isEmpty');
    });
  }

  QueryBuilder<PlayQueue, bool, QQueryOperations> isMixModeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isMixMode');
    });
  }

  QueryBuilder<PlayQueue, bool, QQueryOperations> isNotEmptyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isNotEmpty');
    });
  }

  QueryBuilder<PlayQueue, bool, QQueryOperations> isShuffleEnabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isShuffleEnabled');
    });
  }

  QueryBuilder<PlayQueue, int, QQueryOperations> lastPositionMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastPositionMs');
    });
  }

  QueryBuilder<PlayQueue, DateTime?, QQueryOperations> lastUpdatedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastUpdated');
    });
  }

  QueryBuilder<PlayQueue, double, QQueryOperations> lastVolumeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastVolume');
    });
  }

  QueryBuilder<PlayQueue, int, QQueryOperations> lengthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'length');
    });
  }

  QueryBuilder<PlayQueue, LoopMode, QQueryOperations> loopModeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'loopMode');
    });
  }

  QueryBuilder<PlayQueue, String?, QQueryOperations> mixPlaylistIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mixPlaylistId');
    });
  }

  QueryBuilder<PlayQueue, String?, QQueryOperations> mixSeedVideoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mixSeedVideoId');
    });
  }

  QueryBuilder<PlayQueue, String?, QQueryOperations> mixTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mixTitle');
    });
  }

  QueryBuilder<PlayQueue, List<int>?, QQueryOperations>
  originalOrderProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originalOrder');
    });
  }

  QueryBuilder<PlayQueue, List<int>, QQueryOperations> trackIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trackIds');
    });
  }
}
