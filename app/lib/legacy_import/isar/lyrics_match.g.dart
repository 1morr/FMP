// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyrics_match.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetLyricsMatchCollection on Isar {
  IsarCollection<LyricsMatch> get lyricsMatchs => this.collection();
}

const LyricsMatchSchema = CollectionSchema(
  name: r'LyricsMatch',
  id: -8859306538472564077,
  properties: {
    r'externalId': PropertySchema(
      id: 0,
      name: r'externalId',
      type: IsarType.string,
    ),
    r'lyricsSource': PropertySchema(
      id: 1,
      name: r'lyricsSource',
      type: IsarType.string,
    ),
    r'matchedAt': PropertySchema(
      id: 2,
      name: r'matchedAt',
      type: IsarType.dateTime,
    ),
    r'offsetMs': PropertySchema(id: 3, name: r'offsetMs', type: IsarType.long),
    r'trackUniqueKey': PropertySchema(
      id: 4,
      name: r'trackUniqueKey',
      type: IsarType.string,
    ),
  },
  estimateSize: _lyricsMatchEstimateSize,
  serialize: _lyricsMatchSerialize,
  deserialize: _lyricsMatchDeserialize,
  deserializeProp: _lyricsMatchDeserializeProp,
  idName: r'id',
  indexes: {
    r'trackUniqueKey': IndexSchema(
      id: -1430557820884415850,
      name: r'trackUniqueKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'trackUniqueKey',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},
  getId: _lyricsMatchGetId,
  getLinks: _lyricsMatchGetLinks,
  attach: _lyricsMatchAttach,
  version: '3.3.2',
);

int _lyricsMatchEstimateSize(
  LyricsMatch object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.externalId.length * 3;
  bytesCount += 3 + object.lyricsSource.length * 3;
  bytesCount += 3 + object.trackUniqueKey.length * 3;
  return bytesCount;
}

void _lyricsMatchSerialize(
  LyricsMatch object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.externalId);
  writer.writeString(offsets[1], object.lyricsSource);
  writer.writeDateTime(offsets[2], object.matchedAt);
  writer.writeLong(offsets[3], object.offsetMs);
  writer.writeString(offsets[4], object.trackUniqueKey);
}

LyricsMatch _lyricsMatchDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = LyricsMatch();
  object.externalId = reader.readString(offsets[0]);
  object.id = id;
  object.lyricsSource = reader.readString(offsets[1]);
  object.matchedAt = reader.readDateTime(offsets[2]);
  object.offsetMs = reader.readLong(offsets[3]);
  object.trackUniqueKey = reader.readString(offsets[4]);
  return object;
}

P _lyricsMatchDeserializeProp<P>(
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
      return (reader.readDateTime(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _lyricsMatchGetId(LyricsMatch object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _lyricsMatchGetLinks(LyricsMatch object) {
  return [];
}

void _lyricsMatchAttach(
  IsarCollection<dynamic> col,
  Id id,
  LyricsMatch object,
) {
  object.id = id;
}

extension LyricsMatchByIndex on IsarCollection<LyricsMatch> {
  Future<LyricsMatch?> getByTrackUniqueKey(String trackUniqueKey) {
    return getByIndex(r'trackUniqueKey', [trackUniqueKey]);
  }

  LyricsMatch? getByTrackUniqueKeySync(String trackUniqueKey) {
    return getByIndexSync(r'trackUniqueKey', [trackUniqueKey]);
  }

  Future<bool> deleteByTrackUniqueKey(String trackUniqueKey) {
    return deleteByIndex(r'trackUniqueKey', [trackUniqueKey]);
  }

  bool deleteByTrackUniqueKeySync(String trackUniqueKey) {
    return deleteByIndexSync(r'trackUniqueKey', [trackUniqueKey]);
  }

  Future<List<LyricsMatch?>> getAllByTrackUniqueKey(
    List<String> trackUniqueKeyValues,
  ) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'trackUniqueKey', values);
  }

  List<LyricsMatch?> getAllByTrackUniqueKeySync(
    List<String> trackUniqueKeyValues,
  ) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'trackUniqueKey', values);
  }

  Future<int> deleteAllByTrackUniqueKey(List<String> trackUniqueKeyValues) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'trackUniqueKey', values);
  }

  int deleteAllByTrackUniqueKeySync(List<String> trackUniqueKeyValues) {
    final values = trackUniqueKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'trackUniqueKey', values);
  }

  Future<Id> putByTrackUniqueKey(LyricsMatch object) {
    return putByIndex(r'trackUniqueKey', object);
  }

  Id putByTrackUniqueKeySync(LyricsMatch object, {bool saveLinks = true}) {
    return putByIndexSync(r'trackUniqueKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByTrackUniqueKey(List<LyricsMatch> objects) {
    return putAllByIndex(r'trackUniqueKey', objects);
  }

  List<Id> putAllByTrackUniqueKeySync(
    List<LyricsMatch> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'trackUniqueKey', objects, saveLinks: saveLinks);
  }
}

extension LyricsMatchQueryWhereSort
    on QueryBuilder<LyricsMatch, LyricsMatch, QWhere> {
  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension LyricsMatchQueryWhere
    on QueryBuilder<LyricsMatch, LyricsMatch, QWhereClause> {
  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
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

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause> idBetween(
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

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause>
  trackUniqueKeyEqualTo(String trackUniqueKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'trackUniqueKey',
          value: [trackUniqueKey],
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterWhereClause>
  trackUniqueKeyNotEqualTo(String trackUniqueKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'trackUniqueKey',
                lower: [],
                upper: [trackUniqueKey],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'trackUniqueKey',
                lower: [trackUniqueKey],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'trackUniqueKey',
                lower: [trackUniqueKey],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'trackUniqueKey',
                lower: [],
                upper: [trackUniqueKey],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension LyricsMatchQueryFilter
    on QueryBuilder<LyricsMatch, LyricsMatch, QFilterCondition> {
  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'externalId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'externalId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'externalId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'externalId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'externalId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'externalId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'externalId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'externalId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'externalId', value: ''),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  externalIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'externalId', value: ''),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition> idBetween(
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

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lyricsSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lyricsSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lyricsSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lyricsSource',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'lyricsSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'lyricsSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'lyricsSource',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'lyricsSource',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lyricsSource', value: ''),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  lyricsSourceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'lyricsSource', value: ''),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  matchedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'matchedAt', value: value),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  matchedAtGreaterThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'matchedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  matchedAtLessThan(DateTime value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'matchedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  matchedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'matchedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition> offsetMsEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'offsetMs', value: value),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  offsetMsGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'offsetMs',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  offsetMsLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'offsetMs',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition> offsetMsBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'offsetMs',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'trackUniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'trackUniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'trackUniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'trackUniqueKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'trackUniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'trackUniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'trackUniqueKey',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'trackUniqueKey',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'trackUniqueKey', value: ''),
      );
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterFilterCondition>
  trackUniqueKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'trackUniqueKey', value: ''),
      );
    });
  }
}

extension LyricsMatchQueryObject
    on QueryBuilder<LyricsMatch, LyricsMatch, QFilterCondition> {}

extension LyricsMatchQueryLinks
    on QueryBuilder<LyricsMatch, LyricsMatch, QFilterCondition> {}

extension LyricsMatchQuerySortBy
    on QueryBuilder<LyricsMatch, LyricsMatch, QSortBy> {
  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByExternalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'externalId', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByExternalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'externalId', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByLyricsSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSource', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy>
  sortByLyricsSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSource', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByMatchedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedAt', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByMatchedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedAt', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByOffsetMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'offsetMs', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByOffsetMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'offsetMs', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> sortByTrackUniqueKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy>
  sortByTrackUniqueKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.desc);
    });
  }
}

extension LyricsMatchQuerySortThenBy
    on QueryBuilder<LyricsMatch, LyricsMatch, QSortThenBy> {
  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByExternalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'externalId', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByExternalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'externalId', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByLyricsSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSource', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy>
  thenByLyricsSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lyricsSource', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByMatchedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedAt', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByMatchedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedAt', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByOffsetMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'offsetMs', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByOffsetMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'offsetMs', Sort.desc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy> thenByTrackUniqueKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.asc);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QAfterSortBy>
  thenByTrackUniqueKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trackUniqueKey', Sort.desc);
    });
  }
}

extension LyricsMatchQueryWhereDistinct
    on QueryBuilder<LyricsMatch, LyricsMatch, QDistinct> {
  QueryBuilder<LyricsMatch, LyricsMatch, QDistinct> distinctByExternalId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'externalId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QDistinct> distinctByLyricsSource({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lyricsSource', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QDistinct> distinctByMatchedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'matchedAt');
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QDistinct> distinctByOffsetMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'offsetMs');
    });
  }

  QueryBuilder<LyricsMatch, LyricsMatch, QDistinct> distinctByTrackUniqueKey({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'trackUniqueKey',
        caseSensitive: caseSensitive,
      );
    });
  }
}

extension LyricsMatchQueryProperty
    on QueryBuilder<LyricsMatch, LyricsMatch, QQueryProperty> {
  QueryBuilder<LyricsMatch, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<LyricsMatch, String, QQueryOperations> externalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'externalId');
    });
  }

  QueryBuilder<LyricsMatch, String, QQueryOperations> lyricsSourceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lyricsSource');
    });
  }

  QueryBuilder<LyricsMatch, DateTime, QQueryOperations> matchedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'matchedAt');
    });
  }

  QueryBuilder<LyricsMatch, int, QQueryOperations> offsetMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'offsetMs');
    });
  }

  QueryBuilder<LyricsMatch, String, QQueryOperations> trackUniqueKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trackUniqueKey');
    });
  }
}
