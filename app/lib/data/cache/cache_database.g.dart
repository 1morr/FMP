// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class $CacheEntriesTableTable extends CacheEntriesTable
    with TableInfo<$CacheEntriesTableTable, CacheEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CacheCategory, String> category =
      GeneratedColumn<String>(
        'category',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CacheCategory>(
        $CacheEntriesTableTable.$convertercategory,
      );
  static const VerificationMeta _pluginIdMeta = const VerificationMeta(
    'pluginId',
  );
  @override
  late final GeneratedColumn<String> pluginId = GeneratedColumn<String>(
    'plugin_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastAccess =
      GeneratedColumn<int>(
        'last_access',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($CacheEntriesTableTable.$converterlastAccess);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> validUntil =
      GeneratedColumn<int>(
        'valid_until',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($CacheEntriesTableTable.$convertervalidUntil);
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    key,
    category,
    pluginId,
    relativePath,
    sizeBytes,
    lastAccess,
    validUntil,
    etag,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('plugin_id')) {
      context.handle(
        _pluginIdMeta,
        pluginId.isAcceptableOrUnknown(data['plugin_id']!, _pluginIdMeta),
      );
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {category, pluginId, key},
  ];
  @override
  CacheEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      category: $CacheEntriesTableTable.$convertercategory.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}category'],
        )!,
      ),
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      lastAccess: $CacheEntriesTableTable.$converterlastAccess.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_access'],
        )!,
      ),
      validUntil: $CacheEntriesTableTable.$convertervalidUntil.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}valid_until'],
        )!,
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
    );
  }

  @override
  $CacheEntriesTableTable createAlias(String alias) {
    return $CacheEntriesTableTable(attachedDatabase, alias);
  }

  static TypeConverter<CacheCategory, String> $convertercategory =
      const CacheCategoryConverter();
  static TypeConverter<DateTime, int> $converterlastAccess =
      const EpochMillisecondsConverter();
  static TypeConverter<DateTime, int> $convertervalidUntil =
      const EpochMillisecondsConverter();
}

class CacheEntryRow extends DataClass implements Insertable<CacheEntryRow> {
  /// `flutter_cache_manager` 的 `CacheObject.id` 是 int。
  final int id;
  final String key;
  final CacheCategory category;
  final String? pluginId;

  /// 相對 `fmp_cache/files/` 的檔名。
  final String relativePath;
  final int sizeBytes;

  /// 最後一次讀或寫（UTC epoch 毫秒）；淘汰依它由舊到新。
  final DateTime lastAccess;

  /// 伺服器說這份內容有效到何時（UTC epoch 毫秒）；過了就重新下載。
  final DateTime validUntil;
  final String? etag;
  const CacheEntryRow({
    required this.id,
    required this.key,
    required this.category,
    this.pluginId,
    required this.relativePath,
    required this.sizeBytes,
    required this.lastAccess,
    required this.validUntil,
    this.etag,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['key'] = Variable<String>(key);
    {
      map['category'] = Variable<String>(
        $CacheEntriesTableTable.$convertercategory.toSql(category),
      );
    }
    if (!nullToAbsent || pluginId != null) {
      map['plugin_id'] = Variable<String>(pluginId);
    }
    map['relative_path'] = Variable<String>(relativePath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    {
      map['last_access'] = Variable<int>(
        $CacheEntriesTableTable.$converterlastAccess.toSql(lastAccess),
      );
    }
    {
      map['valid_until'] = Variable<int>(
        $CacheEntriesTableTable.$convertervalidUntil.toSql(validUntil),
      );
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    return map;
  }

  CacheEntriesTableCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesTableCompanion(
      id: Value(id),
      key: Value(key),
      category: Value(category),
      pluginId: pluginId == null && nullToAbsent
          ? const Value.absent()
          : Value(pluginId),
      relativePath: Value(relativePath),
      sizeBytes: Value(sizeBytes),
      lastAccess: Value(lastAccess),
      validUntil: Value(validUntil),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
    );
  }

  factory CacheEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntryRow(
      id: serializer.fromJson<int>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      category: serializer.fromJson<CacheCategory>(json['category']),
      pluginId: serializer.fromJson<String?>(json['pluginId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      lastAccess: serializer.fromJson<DateTime>(json['lastAccess']),
      validUntil: serializer.fromJson<DateTime>(json['validUntil']),
      etag: serializer.fromJson<String?>(json['etag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'key': serializer.toJson<String>(key),
      'category': serializer.toJson<CacheCategory>(category),
      'pluginId': serializer.toJson<String?>(pluginId),
      'relativePath': serializer.toJson<String>(relativePath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'lastAccess': serializer.toJson<DateTime>(lastAccess),
      'validUntil': serializer.toJson<DateTime>(validUntil),
      'etag': serializer.toJson<String?>(etag),
    };
  }

  CacheEntryRow copyWith({
    int? id,
    String? key,
    CacheCategory? category,
    Value<String?> pluginId = const Value.absent(),
    String? relativePath,
    int? sizeBytes,
    DateTime? lastAccess,
    DateTime? validUntil,
    Value<String?> etag = const Value.absent(),
  }) => CacheEntryRow(
    id: id ?? this.id,
    key: key ?? this.key,
    category: category ?? this.category,
    pluginId: pluginId.present ? pluginId.value : this.pluginId,
    relativePath: relativePath ?? this.relativePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    lastAccess: lastAccess ?? this.lastAccess,
    validUntil: validUntil ?? this.validUntil,
    etag: etag.present ? etag.value : this.etag,
  );
  CacheEntryRow copyWithCompanion(CacheEntriesTableCompanion data) {
    return CacheEntryRow(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      category: data.category.present ? data.category.value : this.category,
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      lastAccess: data.lastAccess.present
          ? data.lastAccess.value
          : this.lastAccess,
      validUntil: data.validUntil.present
          ? data.validUntil.value
          : this.validUntil,
      etag: data.etag.present ? data.etag.value : this.etag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntryRow(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('category: $category, ')
          ..write('pluginId: $pluginId, ')
          ..write('relativePath: $relativePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastAccess: $lastAccess, ')
          ..write('validUntil: $validUntil, ')
          ..write('etag: $etag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    key,
    category,
    pluginId,
    relativePath,
    sizeBytes,
    lastAccess,
    validUntil,
    etag,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntryRow &&
          other.id == this.id &&
          other.key == this.key &&
          other.category == this.category &&
          other.pluginId == this.pluginId &&
          other.relativePath == this.relativePath &&
          other.sizeBytes == this.sizeBytes &&
          other.lastAccess == this.lastAccess &&
          other.validUntil == this.validUntil &&
          other.etag == this.etag);
}

class CacheEntriesTableCompanion extends UpdateCompanion<CacheEntryRow> {
  final Value<int> id;
  final Value<String> key;
  final Value<CacheCategory> category;
  final Value<String?> pluginId;
  final Value<String> relativePath;
  final Value<int> sizeBytes;
  final Value<DateTime> lastAccess;
  final Value<DateTime> validUntil;
  final Value<String?> etag;
  const CacheEntriesTableCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.category = const Value.absent(),
    this.pluginId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.lastAccess = const Value.absent(),
    this.validUntil = const Value.absent(),
    this.etag = const Value.absent(),
  });
  CacheEntriesTableCompanion.insert({
    this.id = const Value.absent(),
    required String key,
    required CacheCategory category,
    this.pluginId = const Value.absent(),
    required String relativePath,
    required int sizeBytes,
    required DateTime lastAccess,
    required DateTime validUntil,
    this.etag = const Value.absent(),
  }) : key = Value(key),
       category = Value(category),
       relativePath = Value(relativePath),
       sizeBytes = Value(sizeBytes),
       lastAccess = Value(lastAccess),
       validUntil = Value(validUntil);
  static Insertable<CacheEntryRow> custom({
    Expression<int>? id,
    Expression<String>? key,
    Expression<String>? category,
    Expression<String>? pluginId,
    Expression<String>? relativePath,
    Expression<int>? sizeBytes,
    Expression<int>? lastAccess,
    Expression<int>? validUntil,
    Expression<String>? etag,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (category != null) 'category': category,
      if (pluginId != null) 'plugin_id': pluginId,
      if (relativePath != null) 'relative_path': relativePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (lastAccess != null) 'last_access': lastAccess,
      if (validUntil != null) 'valid_until': validUntil,
      if (etag != null) 'etag': etag,
    });
  }

  CacheEntriesTableCompanion copyWith({
    Value<int>? id,
    Value<String>? key,
    Value<CacheCategory>? category,
    Value<String?>? pluginId,
    Value<String>? relativePath,
    Value<int>? sizeBytes,
    Value<DateTime>? lastAccess,
    Value<DateTime>? validUntil,
    Value<String?>? etag,
  }) {
    return CacheEntriesTableCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      category: category ?? this.category,
      pluginId: pluginId ?? this.pluginId,
      relativePath: relativePath ?? this.relativePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastAccess: lastAccess ?? this.lastAccess,
      validUntil: validUntil ?? this.validUntil,
      etag: etag ?? this.etag,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(
        $CacheEntriesTableTable.$convertercategory.toSql(category.value),
      );
    }
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (lastAccess.present) {
      map['last_access'] = Variable<int>(
        $CacheEntriesTableTable.$converterlastAccess.toSql(lastAccess.value),
      );
    }
    if (validUntil.present) {
      map['valid_until'] = Variable<int>(
        $CacheEntriesTableTable.$convertervalidUntil.toSql(validUntil.value),
      );
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesTableCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('category: $category, ')
          ..write('pluginId: $pluginId, ')
          ..write('relativePath: $relativePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastAccess: $lastAccess, ')
          ..write('validUntil: $validUntil, ')
          ..write('etag: $etag')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  $CacheDatabaseManager get managers => $CacheDatabaseManager(this);
  late final $CacheEntriesTableTable cacheEntriesTable =
      $CacheEntriesTableTable(this);
  late final Index cacheEntriesLastAccess = Index(
    'cache_entries_last_access',
    'CREATE INDEX cache_entries_last_access ON cache_entries (last_access)',
  );
  late final Index cacheEntriesPluginId = Index(
    'cache_entries_plugin_id',
    'CREATE INDEX cache_entries_plugin_id ON cache_entries (plugin_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cacheEntriesTable,
    cacheEntriesLastAccess,
    cacheEntriesPluginId,
  ];
}

typedef $$CacheEntriesTableTableCreateCompanionBuilder =
    CacheEntriesTableCompanion Function({
      Value<int> id,
      required String key,
      required CacheCategory category,
      Value<String?> pluginId,
      required String relativePath,
      required int sizeBytes,
      required DateTime lastAccess,
      required DateTime validUntil,
      Value<String?> etag,
    });
typedef $$CacheEntriesTableTableUpdateCompanionBuilder =
    CacheEntriesTableCompanion Function({
      Value<int> id,
      Value<String> key,
      Value<CacheCategory> category,
      Value<String?> pluginId,
      Value<String> relativePath,
      Value<int> sizeBytes,
      Value<DateTime> lastAccess,
      Value<DateTime> validUntil,
      Value<String?> etag,
    });

class $$CacheEntriesTableTableFilterComposer
    extends Composer<_$CacheDatabase, $CacheEntriesTableTable> {
  $$CacheEntriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CacheCategory, CacheCategory, String>
  get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get lastAccess =>
      $composableBuilder(
        column: $table.lastAccess,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get validUntil =>
      $composableBuilder(
        column: $table.validUntil,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableTableOrderingComposer
    extends Composer<_$CacheDatabase, $CacheEntriesTableTable> {
  $$CacheEntriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccess => $composableBuilder(
    column: $table.lastAccess,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableTableAnnotationComposer
    extends Composer<_$CacheDatabase, $CacheEntriesTableTable> {
  $$CacheEntriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CacheCategory, String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get lastAccess =>
      $composableBuilder(
        column: $table.lastAccess,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime, int> get validUntil =>
      $composableBuilder(
        column: $table.validUntil,
        builder: (column) => column,
      );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);
}

class $$CacheEntriesTableTableTableManager
    extends
        RootTableManager<
          _$CacheDatabase,
          $CacheEntriesTableTable,
          CacheEntryRow,
          $$CacheEntriesTableTableFilterComposer,
          $$CacheEntriesTableTableOrderingComposer,
          $$CacheEntriesTableTableAnnotationComposer,
          $$CacheEntriesTableTableCreateCompanionBuilder,
          $$CacheEntriesTableTableUpdateCompanionBuilder,
          (
            CacheEntryRow,
            BaseReferences<
              _$CacheDatabase,
              $CacheEntriesTableTable,
              CacheEntryRow
            >,
          ),
          CacheEntryRow,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableTableManager(
    _$CacheDatabase db,
    $CacheEntriesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<CacheCategory> category = const Value.absent(),
                Value<String?> pluginId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> lastAccess = const Value.absent(),
                Value<DateTime> validUntil = const Value.absent(),
                Value<String?> etag = const Value.absent(),
              }) => CacheEntriesTableCompanion(
                id: id,
                key: key,
                category: category,
                pluginId: pluginId,
                relativePath: relativePath,
                sizeBytes: sizeBytes,
                lastAccess: lastAccess,
                validUntil: validUntil,
                etag: etag,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String key,
                required CacheCategory category,
                Value<String?> pluginId = const Value.absent(),
                required String relativePath,
                required int sizeBytes,
                required DateTime lastAccess,
                required DateTime validUntil,
                Value<String?> etag = const Value.absent(),
              }) => CacheEntriesTableCompanion.insert(
                id: id,
                key: key,
                category: category,
                pluginId: pluginId,
                relativePath: relativePath,
                sizeBytes: sizeBytes,
                lastAccess: lastAccess,
                validUntil: validUntil,
                etag: etag,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheEntriesTableTable, CacheEntryRow>(table),
                  BaseReferences<
                    _$CacheDatabase,
                    $CacheEntriesTableTable,
                    CacheEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$CacheDatabase,
      $CacheEntriesTableTable,
      CacheEntryRow,
      $$CacheEntriesTableTableFilterComposer,
      $$CacheEntriesTableTableOrderingComposer,
      $$CacheEntriesTableTableAnnotationComposer,
      $$CacheEntriesTableTableCreateCompanionBuilder,
      $$CacheEntriesTableTableUpdateCompanionBuilder,
      (
        CacheEntryRow,
        BaseReferences<_$CacheDatabase, $CacheEntriesTableTable, CacheEntryRow>,
      ),
      CacheEntryRow,
      PrefetchHooks Function()
    >;

class $CacheDatabaseManager {
  final _$CacheDatabase _db;
  $CacheDatabaseManager(this._db);
  $$CacheEntriesTableTableTableManager get cacheEntriesTable =>
      $$CacheEntriesTableTableTableManager(_db, _db.cacheEntriesTable);
}
