// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AppearanceSettingsTableTable extends AppearanceSettingsTable
    with TableInfo<$AppearanceSettingsTableTable, AppearanceSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppearanceSettingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    check: () => id.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ThemeModeSetting?, String>
  themeMode =
      GeneratedColumn<String>(
        'theme_mode',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<ThemeModeSetting?>(
        $AppearanceSettingsTableTable.$converterthemeModen,
      );
  @override
  late final GeneratedColumnWithTypeConverter<LocaleSetting?, String> locale =
      GeneratedColumn<String>(
        'locale',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<LocaleSetting?>(
        $AppearanceSettingsTableTable.$converterlocalen,
      );
  @override
  List<GeneratedColumn> get $columns => [id, themeMode, locale];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'appearance_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppearanceSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppearanceSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppearanceSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      themeMode: $AppearanceSettingsTableTable.$converterthemeModen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}theme_mode'],
        ),
      ),
      locale: $AppearanceSettingsTableTable.$converterlocalen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}locale'],
        ),
      ),
    );
  }

  @override
  $AppearanceSettingsTableTable createAlias(String alias) {
    return $AppearanceSettingsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<ThemeModeSetting, String> $converterthemeMode =
      const ThemeModeSettingConverter();
  static TypeConverter<ThemeModeSetting?, String?> $converterthemeModen =
      NullAwareTypeConverter.wrap($converterthemeMode);
  static TypeConverter<LocaleSetting, String> $converterlocale =
      const LocaleSettingConverter();
  static TypeConverter<LocaleSetting?, String?> $converterlocalen =
      NullAwareTypeConverter.wrap($converterlocale);
}

class AppearanceSettingsRow extends DataClass
    implements Insertable<AppearanceSettingsRow> {
  /// 固定為 1；CHECK 讓第二列插不進去。
  final int id;
  final ThemeModeSetting? themeMode;
  final LocaleSetting? locale;
  const AppearanceSettingsRow({required this.id, this.themeMode, this.locale});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || themeMode != null) {
      map['theme_mode'] = Variable<String>(
        $AppearanceSettingsTableTable.$converterthemeModen.toSql(themeMode),
      );
    }
    if (!nullToAbsent || locale != null) {
      map['locale'] = Variable<String>(
        $AppearanceSettingsTableTable.$converterlocalen.toSql(locale),
      );
    }
    return map;
  }

  AppearanceSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return AppearanceSettingsTableCompanion(
      id: Value(id),
      themeMode: themeMode == null && nullToAbsent
          ? const Value.absent()
          : Value(themeMode),
      locale: locale == null && nullToAbsent
          ? const Value.absent()
          : Value(locale),
    );
  }

  factory AppearanceSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppearanceSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      themeMode: serializer.fromJson<ThemeModeSetting?>(json['themeMode']),
      locale: serializer.fromJson<LocaleSetting?>(json['locale']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'themeMode': serializer.toJson<ThemeModeSetting?>(themeMode),
      'locale': serializer.toJson<LocaleSetting?>(locale),
    };
  }

  AppearanceSettingsRow copyWith({
    int? id,
    Value<ThemeModeSetting?> themeMode = const Value.absent(),
    Value<LocaleSetting?> locale = const Value.absent(),
  }) => AppearanceSettingsRow(
    id: id ?? this.id,
    themeMode: themeMode.present ? themeMode.value : this.themeMode,
    locale: locale.present ? locale.value : this.locale,
  );
  AppearanceSettingsRow copyWithCompanion(
    AppearanceSettingsTableCompanion data,
  ) {
    return AppearanceSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      locale: data.locale.present ? data.locale.value : this.locale,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppearanceSettingsRow(')
          ..write('id: $id, ')
          ..write('themeMode: $themeMode, ')
          ..write('locale: $locale')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, themeMode, locale);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppearanceSettingsRow &&
          other.id == this.id &&
          other.themeMode == this.themeMode &&
          other.locale == this.locale);
}

class AppearanceSettingsTableCompanion
    extends UpdateCompanion<AppearanceSettingsRow> {
  final Value<int> id;
  final Value<ThemeModeSetting?> themeMode;
  final Value<LocaleSetting?> locale;
  const AppearanceSettingsTableCompanion({
    this.id = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.locale = const Value.absent(),
  });
  AppearanceSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.locale = const Value.absent(),
  });
  static Insertable<AppearanceSettingsRow> custom({
    Expression<int>? id,
    Expression<String>? themeMode,
    Expression<String>? locale,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (themeMode != null) 'theme_mode': themeMode,
      if (locale != null) 'locale': locale,
    });
  }

  AppearanceSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<ThemeModeSetting?>? themeMode,
    Value<LocaleSetting?>? locale,
  }) {
    return AppearanceSettingsTableCompanion(
      id: id ?? this.id,
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(
        $AppearanceSettingsTableTable.$converterthemeModen.toSql(
          themeMode.value,
        ),
      );
    }
    if (locale.present) {
      map['locale'] = Variable<String>(
        $AppearanceSettingsTableTable.$converterlocalen.toSql(locale.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppearanceSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('themeMode: $themeMode, ')
          ..write('locale: $locale')
          ..write(')'))
        .toString();
  }
}

class $InstalledPluginsTableTable extends InstalledPluginsTable
    with TableInfo<$InstalledPluginsTableTable, InstalledPluginRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstalledPluginsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _manifestJsonMeta = const VerificationMeta(
    'manifestJson',
  );
  @override
  late final GeneratedColumn<String> manifestJson = GeneratedColumn<String>(
    'manifest_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scriptMeta = const VerificationMeta('script');
  @override
  late final GeneratedColumn<String> script = GeneratedColumn<String>(
    'script',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> installedAt =
      GeneratedColumn<int>(
        'installed_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>(
        $InstalledPluginsTableTable.$converterinstalledAt,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    manifestJson,
    script,
    installedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installed_plugins';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstalledPluginRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('manifest_json')) {
      context.handle(
        _manifestJsonMeta,
        manifestJson.isAcceptableOrUnknown(
          data['manifest_json']!,
          _manifestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manifestJsonMeta);
    }
    if (data.containsKey('script')) {
      context.handle(
        _scriptMeta,
        script.isAcceptableOrUnknown(data['script']!, _scriptMeta),
      );
    } else if (isInserting) {
      context.missing(_scriptMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InstalledPluginRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstalledPluginRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      manifestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_json'],
      )!,
      script: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}script'],
      )!,
      installedAt: $InstalledPluginsTableTable.$converterinstalledAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}installed_at'],
        )!,
      ),
    );
  }

  @override
  $InstalledPluginsTableTable createAlias(String alias) {
    return $InstalledPluginsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterinstalledAt =
      const EpochMillisecondsConverter();
}

class InstalledPluginRow extends DataClass
    implements Insertable<InstalledPluginRow> {
  /// 音源 id，例如 B 站插件的 id。
  final String id;
  final String version;
  final String manifestJson;
  final String script;

  /// UTC epoch 毫秒。
  final DateTime installedAt;
  const InstalledPluginRow({
    required this.id,
    required this.version,
    required this.manifestJson,
    required this.script,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<String>(version);
    map['manifest_json'] = Variable<String>(manifestJson);
    map['script'] = Variable<String>(script);
    {
      map['installed_at'] = Variable<int>(
        $InstalledPluginsTableTable.$converterinstalledAt.toSql(installedAt),
      );
    }
    return map;
  }

  InstalledPluginsTableCompanion toCompanion(bool nullToAbsent) {
    return InstalledPluginsTableCompanion(
      id: Value(id),
      version: Value(version),
      manifestJson: Value(manifestJson),
      script: Value(script),
      installedAt: Value(installedAt),
    );
  }

  factory InstalledPluginRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstalledPluginRow(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<String>(json['version']),
      manifestJson: serializer.fromJson<String>(json['manifestJson']),
      script: serializer.fromJson<String>(json['script']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<String>(version),
      'manifestJson': serializer.toJson<String>(manifestJson),
      'script': serializer.toJson<String>(script),
      'installedAt': serializer.toJson<DateTime>(installedAt),
    };
  }

  InstalledPluginRow copyWith({
    String? id,
    String? version,
    String? manifestJson,
    String? script,
    DateTime? installedAt,
  }) => InstalledPluginRow(
    id: id ?? this.id,
    version: version ?? this.version,
    manifestJson: manifestJson ?? this.manifestJson,
    script: script ?? this.script,
    installedAt: installedAt ?? this.installedAt,
  );
  InstalledPluginRow copyWithCompanion(InstalledPluginsTableCompanion data) {
    return InstalledPluginRow(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      manifestJson: data.manifestJson.present
          ? data.manifestJson.value
          : this.manifestJson,
      script: data.script.present ? data.script.value : this.script,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstalledPluginRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('script: $script, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, version, manifestJson, script, installedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstalledPluginRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.manifestJson == this.manifestJson &&
          other.script == this.script &&
          other.installedAt == this.installedAt);
}

class InstalledPluginsTableCompanion
    extends UpdateCompanion<InstalledPluginRow> {
  final Value<String> id;
  final Value<String> version;
  final Value<String> manifestJson;
  final Value<String> script;
  final Value<DateTime> installedAt;
  final Value<int> rowid;
  const InstalledPluginsTableCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.script = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstalledPluginsTableCompanion.insert({
    required String id,
    required String version,
    required String manifestJson,
    required String script,
    required DateTime installedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       version = Value(version),
       manifestJson = Value(manifestJson),
       script = Value(script),
       installedAt = Value(installedAt);
  static Insertable<InstalledPluginRow> custom({
    Expression<String>? id,
    Expression<String>? version,
    Expression<String>? manifestJson,
    Expression<String>? script,
    Expression<int>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (script != null) 'script': script,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstalledPluginsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? version,
    Value<String>? manifestJson,
    Value<String>? script,
    Value<DateTime>? installedAt,
    Value<int>? rowid,
  }) {
    return InstalledPluginsTableCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      manifestJson: manifestJson ?? this.manifestJson,
      script: script ?? this.script,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (manifestJson.present) {
      map['manifest_json'] = Variable<String>(manifestJson.value);
    }
    if (script.present) {
      map['script'] = Variable<String>(script.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<int>(
        $InstalledPluginsTableTable.$converterinstalledAt.toSql(
          installedAt.value,
        ),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstalledPluginsTableCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('script: $script, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PluginStorageTableTable extends PluginStorageTable
    with TableInfo<$PluginStorageTableTable, PluginStorageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PluginStorageTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pluginIdMeta = const VerificationMeta(
    'pluginId',
  );
  @override
  late final GeneratedColumn<String> pluginId = GeneratedColumn<String>(
    'plugin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES installed_plugins (id) ON DELETE CASCADE',
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
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [pluginId, key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plugin_storage';
  @override
  VerificationContext validateIntegrity(
    Insertable<PluginStorageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('plugin_id')) {
      context.handle(
        _pluginIdMeta,
        pluginId.isAcceptableOrUnknown(data['plugin_id']!, _pluginIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pluginIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pluginId, key};
  @override
  PluginStorageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PluginStorageRow(
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $PluginStorageTableTable createAlias(String alias) {
    return $PluginStorageTableTable(attachedDatabase, alias);
  }
}

class PluginStorageRow extends DataClass
    implements Insertable<PluginStorageRow> {
  final String pluginId;
  final String key;
  final String value;
  const PluginStorageRow({
    required this.pluginId,
    required this.key,
    required this.value,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['plugin_id'] = Variable<String>(pluginId);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  PluginStorageTableCompanion toCompanion(bool nullToAbsent) {
    return PluginStorageTableCompanion(
      pluginId: Value(pluginId),
      key: Value(key),
      value: Value(value),
    );
  }

  factory PluginStorageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PluginStorageRow(
      pluginId: serializer.fromJson<String>(json['pluginId']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pluginId': serializer.toJson<String>(pluginId),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  PluginStorageRow copyWith({String? pluginId, String? key, String? value}) =>
      PluginStorageRow(
        pluginId: pluginId ?? this.pluginId,
        key: key ?? this.key,
        value: value ?? this.value,
      );
  PluginStorageRow copyWithCompanion(PluginStorageTableCompanion data) {
    return PluginStorageRow(
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PluginStorageRow(')
          ..write('pluginId: $pluginId, ')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pluginId, key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginStorageRow &&
          other.pluginId == this.pluginId &&
          other.key == this.key &&
          other.value == this.value);
}

class PluginStorageTableCompanion extends UpdateCompanion<PluginStorageRow> {
  final Value<String> pluginId;
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const PluginStorageTableCompanion({
    this.pluginId = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PluginStorageTableCompanion.insert({
    required String pluginId,
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : pluginId = Value(pluginId),
       key = Value(key),
       value = Value(value);
  static Insertable<PluginStorageRow> custom({
    Expression<String>? pluginId,
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pluginId != null) 'plugin_id': pluginId,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PluginStorageTableCompanion copyWith({
    Value<String>? pluginId,
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return PluginStorageTableCompanion(
      pluginId: pluginId ?? this.pluginId,
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PluginStorageTableCompanion(')
          ..write('pluginId: $pluginId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AppearanceSettingsTableTable appearanceSettingsTable =
      $AppearanceSettingsTableTable(this);
  late final $InstalledPluginsTableTable installedPluginsTable =
      $InstalledPluginsTableTable(this);
  late final $PluginStorageTableTable pluginStorageTable =
      $PluginStorageTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appearanceSettingsTable,
    installedPluginsTable,
    pluginStorageTable,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'installed_plugins',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('plugin_storage', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$AppearanceSettingsTableTableCreateCompanionBuilder =
    AppearanceSettingsTableCompanion Function({
      Value<int> id,
      Value<ThemeModeSetting?> themeMode,
      Value<LocaleSetting?> locale,
    });
typedef $$AppearanceSettingsTableTableUpdateCompanionBuilder =
    AppearanceSettingsTableCompanion Function({
      Value<int> id,
      Value<ThemeModeSetting?> themeMode,
      Value<LocaleSetting?> locale,
    });

class $$AppearanceSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AppearanceSettingsTableTable> {
  $$AppearanceSettingsTableTableFilterComposer({
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

  ColumnWithTypeConverterFilters<ThemeModeSetting?, ThemeModeSetting, String>
  get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<LocaleSetting?, LocaleSetting, String>
  get locale => $composableBuilder(
    column: $table.locale,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$AppearanceSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AppearanceSettingsTableTable> {
  $$AppearanceSettingsTableTableOrderingComposer({
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

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locale => $composableBuilder(
    column: $table.locale,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppearanceSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppearanceSettingsTableTable> {
  $$AppearanceSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ThemeModeSetting?, String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocaleSetting?, String> get locale =>
      $composableBuilder(column: $table.locale, builder: (column) => column);
}

class $$AppearanceSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppearanceSettingsTableTable,
          AppearanceSettingsRow,
          $$AppearanceSettingsTableTableFilterComposer,
          $$AppearanceSettingsTableTableOrderingComposer,
          $$AppearanceSettingsTableTableAnnotationComposer,
          $$AppearanceSettingsTableTableCreateCompanionBuilder,
          $$AppearanceSettingsTableTableUpdateCompanionBuilder,
          (
            AppearanceSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $AppearanceSettingsTableTable,
              AppearanceSettingsRow
            >,
          ),
          AppearanceSettingsRow,
          PrefetchHooks Function()
        > {
  $$AppearanceSettingsTableTableTableManager(
    _$AppDatabase db,
    $AppearanceSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppearanceSettingsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AppearanceSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AppearanceSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<ThemeModeSetting?> themeMode = const Value.absent(),
                Value<LocaleSetting?> locale = const Value.absent(),
              }) => AppearanceSettingsTableCompanion(
                id: id,
                themeMode: themeMode,
                locale: locale,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<ThemeModeSetting?> themeMode = const Value.absent(),
                Value<LocaleSetting?> locale = const Value.absent(),
              }) => AppearanceSettingsTableCompanion.insert(
                id: id,
                themeMode: themeMode,
                locale: locale,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $AppearanceSettingsTableTable,
                    AppearanceSettingsRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AppearanceSettingsTableTable,
                    AppearanceSettingsRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppearanceSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppearanceSettingsTableTable,
      AppearanceSettingsRow,
      $$AppearanceSettingsTableTableFilterComposer,
      $$AppearanceSettingsTableTableOrderingComposer,
      $$AppearanceSettingsTableTableAnnotationComposer,
      $$AppearanceSettingsTableTableCreateCompanionBuilder,
      $$AppearanceSettingsTableTableUpdateCompanionBuilder,
      (
        AppearanceSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $AppearanceSettingsTableTable,
          AppearanceSettingsRow
        >,
      ),
      AppearanceSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$InstalledPluginsTableTableCreateCompanionBuilder =
    InstalledPluginsTableCompanion Function({
      required String id,
      required String version,
      required String manifestJson,
      required String script,
      required DateTime installedAt,
      Value<int> rowid,
    });
typedef $$InstalledPluginsTableTableUpdateCompanionBuilder =
    InstalledPluginsTableCompanion Function({
      Value<String> id,
      Value<String> version,
      Value<String> manifestJson,
      Value<String> script,
      Value<DateTime> installedAt,
      Value<int> rowid,
    });

final class $$InstalledPluginsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InstalledPluginsTableTable,
          InstalledPluginRow
        > {
  $$InstalledPluginsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$PluginStorageTableTable, List<PluginStorageRow>>
  _pluginStorageTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.pluginStorageTable,
        aliasName: 'installed_plugins__id__plugin_storage__plugin_id',
      );

  $$PluginStorageTableTableProcessedTableManager get pluginStorageTableRefs {
    final manager = $$PluginStorageTableTableTableManager(
      $_db,
      $_db.pluginStorageTable,
    ).filter((f) => f.pluginId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _pluginStorageTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$InstalledPluginsTableTableFilterComposer
    extends Composer<_$AppDatabase, $InstalledPluginsTableTable> {
  $$InstalledPluginsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get script => $composableBuilder(
    column: $table.script,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get installedAt =>
      $composableBuilder(
        column: $table.installedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  Expression<bool> pluginStorageTableRefs(
    Expression<bool> Function($$PluginStorageTableTableFilterComposer f) f,
  ) {
    final $$PluginStorageTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pluginStorageTable,
      getReferencedColumn: (t) => t.pluginId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PluginStorageTableTableFilterComposer(
            $db: $db,
            $table: $db.pluginStorageTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$InstalledPluginsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $InstalledPluginsTableTable> {
  $$InstalledPluginsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get script => $composableBuilder(
    column: $table.script,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstalledPluginsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstalledPluginsTableTable> {
  $$InstalledPluginsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get manifestJson => $composableBuilder(
    column: $table.manifestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get script =>
      $composableBuilder(column: $table.script, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get installedAt =>
      $composableBuilder(
        column: $table.installedAt,
        builder: (column) => column,
      );

  Expression<T> pluginStorageTableRefs<T extends Object>(
    Expression<T> Function($$PluginStorageTableTableAnnotationComposer a) f,
  ) {
    final $$PluginStorageTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.pluginStorageTable,
          getReferencedColumn: (t) => t.pluginId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PluginStorageTableTableAnnotationComposer(
                $db: $db,
                $table: $db.pluginStorageTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$InstalledPluginsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InstalledPluginsTableTable,
          InstalledPluginRow,
          $$InstalledPluginsTableTableFilterComposer,
          $$InstalledPluginsTableTableOrderingComposer,
          $$InstalledPluginsTableTableAnnotationComposer,
          $$InstalledPluginsTableTableCreateCompanionBuilder,
          $$InstalledPluginsTableTableUpdateCompanionBuilder,
          (InstalledPluginRow, $$InstalledPluginsTableTableReferences),
          InstalledPluginRow,
          PrefetchHooks Function({bool pluginStorageTableRefs})
        > {
  $$InstalledPluginsTableTableTableManager(
    _$AppDatabase db,
    $InstalledPluginsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstalledPluginsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$InstalledPluginsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$InstalledPluginsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> manifestJson = const Value.absent(),
                Value<String> script = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstalledPluginsTableCompanion(
                id: id,
                version: version,
                manifestJson: manifestJson,
                script: script,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String version,
                required String manifestJson,
                required String script,
                required DateTime installedAt,
                Value<int> rowid = const Value.absent(),
              }) => InstalledPluginsTableCompanion.insert(
                id: id,
                version: version,
                manifestJson: manifestJson,
                script: script,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InstalledPluginsTableTable, InstalledPluginRow>(
                    table,
                  ),
                  $$InstalledPluginsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({pluginStorageTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (pluginStorageTableRefs) db.pluginStorageTable,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (pluginStorageTableRefs)
                    await $_getPrefetchedData<
                      InstalledPluginRow,
                      $InstalledPluginsTableTable,
                      PluginStorageRow
                    >(
                      currentTable: table,
                      referencedTable: $$InstalledPluginsTableTableReferences
                          ._pluginStorageTableRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$InstalledPluginsTableTableReferences(
                            db,
                            table,
                            p0,
                          ).pluginStorageTableRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.pluginId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$InstalledPluginsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InstalledPluginsTableTable,
      InstalledPluginRow,
      $$InstalledPluginsTableTableFilterComposer,
      $$InstalledPluginsTableTableOrderingComposer,
      $$InstalledPluginsTableTableAnnotationComposer,
      $$InstalledPluginsTableTableCreateCompanionBuilder,
      $$InstalledPluginsTableTableUpdateCompanionBuilder,
      (InstalledPluginRow, $$InstalledPluginsTableTableReferences),
      InstalledPluginRow,
      PrefetchHooks Function({bool pluginStorageTableRefs})
    >;
typedef $$PluginStorageTableTableCreateCompanionBuilder =
    PluginStorageTableCompanion Function({
      required String pluginId,
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$PluginStorageTableTableUpdateCompanionBuilder =
    PluginStorageTableCompanion Function({
      Value<String> pluginId,
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

final class $$PluginStorageTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PluginStorageTableTable,
          PluginStorageRow
        > {
  $$PluginStorageTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $InstalledPluginsTableTable _pluginIdTable(_$AppDatabase db) => db
      .installedPluginsTable
      .createAlias('plugin_storage__plugin_id__installed_plugins__id');

  $$InstalledPluginsTableTableProcessedTableManager get pluginId {
    final $_column = $_itemColumn<String>('plugin_id')!;

    final manager = $$InstalledPluginsTableTableTableManager(
      $_db,
      $_db.installedPluginsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_pluginIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PluginStorageTableTableFilterComposer
    extends Composer<_$AppDatabase, $PluginStorageTableTable> {
  $$PluginStorageTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  $$InstalledPluginsTableTableFilterComposer get pluginId {
    final $$InstalledPluginsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.pluginId,
          referencedTable: $db.installedPluginsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InstalledPluginsTableTableFilterComposer(
                $db: $db,
                $table: $db.installedPluginsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$PluginStorageTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PluginStorageTableTable> {
  $$PluginStorageTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  $$InstalledPluginsTableTableOrderingComposer get pluginId {
    final $$InstalledPluginsTableTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.pluginId,
          referencedTable: $db.installedPluginsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InstalledPluginsTableTableOrderingComposer(
                $db: $db,
                $table: $db.installedPluginsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$PluginStorageTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PluginStorageTableTable> {
  $$PluginStorageTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  $$InstalledPluginsTableTableAnnotationComposer get pluginId {
    final $$InstalledPluginsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.pluginId,
          referencedTable: $db.installedPluginsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InstalledPluginsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.installedPluginsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$PluginStorageTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PluginStorageTableTable,
          PluginStorageRow,
          $$PluginStorageTableTableFilterComposer,
          $$PluginStorageTableTableOrderingComposer,
          $$PluginStorageTableTableAnnotationComposer,
          $$PluginStorageTableTableCreateCompanionBuilder,
          $$PluginStorageTableTableUpdateCompanionBuilder,
          (PluginStorageRow, $$PluginStorageTableTableReferences),
          PluginStorageRow,
          PrefetchHooks Function({bool pluginId})
        > {
  $$PluginStorageTableTableTableManager(
    _$AppDatabase db,
    $PluginStorageTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PluginStorageTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PluginStorageTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PluginStorageTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> pluginId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PluginStorageTableCompanion(
                pluginId: pluginId,
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pluginId,
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => PluginStorageTableCompanion.insert(
                pluginId: pluginId,
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PluginStorageTableTable, PluginStorageRow>(
                    table,
                  ),
                  $$PluginStorageTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({pluginId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (pluginId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.pluginId,
                        referencedTable: $$PluginStorageTableTableReferences
                            ._pluginIdTable(db),
                        referencedColumn: $$PluginStorageTableTableReferences
                            ._pluginIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PluginStorageTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PluginStorageTableTable,
      PluginStorageRow,
      $$PluginStorageTableTableFilterComposer,
      $$PluginStorageTableTableOrderingComposer,
      $$PluginStorageTableTableAnnotationComposer,
      $$PluginStorageTableTableCreateCompanionBuilder,
      $$PluginStorageTableTableUpdateCompanionBuilder,
      (PluginStorageRow, $$PluginStorageTableTableReferences),
      PluginStorageRow,
      PrefetchHooks Function({bool pluginId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppearanceSettingsTableTableTableManager get appearanceSettingsTable =>
      $$AppearanceSettingsTableTableTableManager(
        _db,
        _db.appearanceSettingsTable,
      );
  $$InstalledPluginsTableTableTableManager get installedPluginsTable =>
      $$InstalledPluginsTableTableTableManager(_db, _db.installedPluginsTable);
  $$PluginStorageTableTableTableManager get pluginStorageTable =>
      $$PluginStorageTableTableTableManager(_db, _db.pluginStorageTable);
}
