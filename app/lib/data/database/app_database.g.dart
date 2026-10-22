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

class $NetworkSettingsTableTable extends NetworkSettingsTable
    with TableInfo<$NetworkSettingsTableTable, NetworkSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NetworkSettingsTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _cacheLimitMbMeta = const VerificationMeta(
    'cacheLimitMb',
  );
  @override
  late final GeneratedColumn<int> cacheLimitMb = GeneratedColumn<int>(
    'cache_limit_mb',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _radioStatusIntervalMinutesMeta =
      const VerificationMeta('radioStatusIntervalMinutes');
  @override
  late final GeneratedColumn<int> radioStatusIntervalMinutes =
      GeneratedColumn<int>(
        'radio_status_interval_minutes',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _chartRefreshIntervalMinutesMeta =
      const VerificationMeta('chartRefreshIntervalMinutes');
  @override
  late final GeneratedColumn<int> chartRefreshIntervalMinutes =
      GeneratedColumn<int>(
        'chart_refresh_interval_minutes',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cacheLimitMb,
    radioStatusIntervalMinutes,
    chartRefreshIntervalMinutes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'network_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<NetworkSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cache_limit_mb')) {
      context.handle(
        _cacheLimitMbMeta,
        cacheLimitMb.isAcceptableOrUnknown(
          data['cache_limit_mb']!,
          _cacheLimitMbMeta,
        ),
      );
    }
    if (data.containsKey('radio_status_interval_minutes')) {
      context.handle(
        _radioStatusIntervalMinutesMeta,
        radioStatusIntervalMinutes.isAcceptableOrUnknown(
          data['radio_status_interval_minutes']!,
          _radioStatusIntervalMinutesMeta,
        ),
      );
    }
    if (data.containsKey('chart_refresh_interval_minutes')) {
      context.handle(
        _chartRefreshIntervalMinutesMeta,
        chartRefreshIntervalMinutes.isAcceptableOrUnknown(
          data['chart_refresh_interval_minutes']!,
          _chartRefreshIntervalMinutesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NetworkSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NetworkSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cacheLimitMb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cache_limit_mb'],
      ),
      radioStatusIntervalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}radio_status_interval_minutes'],
      ),
      chartRefreshIntervalMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chart_refresh_interval_minutes'],
      ),
    );
  }

  @override
  $NetworkSettingsTableTable createAlias(String alias) {
    return $NetworkSettingsTableTable(attachedDatabase, alias);
  }
}

class NetworkSettingsRow extends DataClass
    implements Insertable<NetworkSettingsRow> {
  /// 固定為 1；CHECK 讓第二列插不進去。
  final int id;

  /// 快取上限（MiB）；空＝平台宣告的預設（ADR 0016 §決定 3）。
  final int? cacheLimitMb;

  /// 電台狀態刷新間隔（分）；`0`＝關閉，空＝預設（ADR 0017 §決定 6、M3 design §3.3）。
  final int? radioStatusIntervalMinutes;

  /// 排行刷新間隔（分）；`0`＝關閉，空＝預設 60（ADR 0017 §決定 6、M4 design §3.3）。
  final int? chartRefreshIntervalMinutes;
  const NetworkSettingsRow({
    required this.id,
    this.cacheLimitMb,
    this.radioStatusIntervalMinutes,
    this.chartRefreshIntervalMinutes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cacheLimitMb != null) {
      map['cache_limit_mb'] = Variable<int>(cacheLimitMb);
    }
    if (!nullToAbsent || radioStatusIntervalMinutes != null) {
      map['radio_status_interval_minutes'] = Variable<int>(
        radioStatusIntervalMinutes,
      );
    }
    if (!nullToAbsent || chartRefreshIntervalMinutes != null) {
      map['chart_refresh_interval_minutes'] = Variable<int>(
        chartRefreshIntervalMinutes,
      );
    }
    return map;
  }

  NetworkSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return NetworkSettingsTableCompanion(
      id: Value(id),
      cacheLimitMb: cacheLimitMb == null && nullToAbsent
          ? const Value.absent()
          : Value(cacheLimitMb),
      radioStatusIntervalMinutes:
          radioStatusIntervalMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(radioStatusIntervalMinutes),
      chartRefreshIntervalMinutes:
          chartRefreshIntervalMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(chartRefreshIntervalMinutes),
    );
  }

  factory NetworkSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NetworkSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      cacheLimitMb: serializer.fromJson<int?>(json['cacheLimitMb']),
      radioStatusIntervalMinutes: serializer.fromJson<int?>(
        json['radioStatusIntervalMinutes'],
      ),
      chartRefreshIntervalMinutes: serializer.fromJson<int?>(
        json['chartRefreshIntervalMinutes'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cacheLimitMb': serializer.toJson<int?>(cacheLimitMb),
      'radioStatusIntervalMinutes': serializer.toJson<int?>(
        radioStatusIntervalMinutes,
      ),
      'chartRefreshIntervalMinutes': serializer.toJson<int?>(
        chartRefreshIntervalMinutes,
      ),
    };
  }

  NetworkSettingsRow copyWith({
    int? id,
    Value<int?> cacheLimitMb = const Value.absent(),
    Value<int?> radioStatusIntervalMinutes = const Value.absent(),
    Value<int?> chartRefreshIntervalMinutes = const Value.absent(),
  }) => NetworkSettingsRow(
    id: id ?? this.id,
    cacheLimitMb: cacheLimitMb.present ? cacheLimitMb.value : this.cacheLimitMb,
    radioStatusIntervalMinutes: radioStatusIntervalMinutes.present
        ? radioStatusIntervalMinutes.value
        : this.radioStatusIntervalMinutes,
    chartRefreshIntervalMinutes: chartRefreshIntervalMinutes.present
        ? chartRefreshIntervalMinutes.value
        : this.chartRefreshIntervalMinutes,
  );
  NetworkSettingsRow copyWithCompanion(NetworkSettingsTableCompanion data) {
    return NetworkSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      cacheLimitMb: data.cacheLimitMb.present
          ? data.cacheLimitMb.value
          : this.cacheLimitMb,
      radioStatusIntervalMinutes: data.radioStatusIntervalMinutes.present
          ? data.radioStatusIntervalMinutes.value
          : this.radioStatusIntervalMinutes,
      chartRefreshIntervalMinutes: data.chartRefreshIntervalMinutes.present
          ? data.chartRefreshIntervalMinutes.value
          : this.chartRefreshIntervalMinutes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NetworkSettingsRow(')
          ..write('id: $id, ')
          ..write('cacheLimitMb: $cacheLimitMb, ')
          ..write('radioStatusIntervalMinutes: $radioStatusIntervalMinutes, ')
          ..write('chartRefreshIntervalMinutes: $chartRefreshIntervalMinutes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cacheLimitMb,
    radioStatusIntervalMinutes,
    chartRefreshIntervalMinutes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkSettingsRow &&
          other.id == this.id &&
          other.cacheLimitMb == this.cacheLimitMb &&
          other.radioStatusIntervalMinutes == this.radioStatusIntervalMinutes &&
          other.chartRefreshIntervalMinutes ==
              this.chartRefreshIntervalMinutes);
}

class NetworkSettingsTableCompanion
    extends UpdateCompanion<NetworkSettingsRow> {
  final Value<int> id;
  final Value<int?> cacheLimitMb;
  final Value<int?> radioStatusIntervalMinutes;
  final Value<int?> chartRefreshIntervalMinutes;
  const NetworkSettingsTableCompanion({
    this.id = const Value.absent(),
    this.cacheLimitMb = const Value.absent(),
    this.radioStatusIntervalMinutes = const Value.absent(),
    this.chartRefreshIntervalMinutes = const Value.absent(),
  });
  NetworkSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    this.cacheLimitMb = const Value.absent(),
    this.radioStatusIntervalMinutes = const Value.absent(),
    this.chartRefreshIntervalMinutes = const Value.absent(),
  });
  static Insertable<NetworkSettingsRow> custom({
    Expression<int>? id,
    Expression<int>? cacheLimitMb,
    Expression<int>? radioStatusIntervalMinutes,
    Expression<int>? chartRefreshIntervalMinutes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cacheLimitMb != null) 'cache_limit_mb': cacheLimitMb,
      if (radioStatusIntervalMinutes != null)
        'radio_status_interval_minutes': radioStatusIntervalMinutes,
      if (chartRefreshIntervalMinutes != null)
        'chart_refresh_interval_minutes': chartRefreshIntervalMinutes,
    });
  }

  NetworkSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<int?>? cacheLimitMb,
    Value<int?>? radioStatusIntervalMinutes,
    Value<int?>? chartRefreshIntervalMinutes,
  }) {
    return NetworkSettingsTableCompanion(
      id: id ?? this.id,
      cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
      radioStatusIntervalMinutes:
          radioStatusIntervalMinutes ?? this.radioStatusIntervalMinutes,
      chartRefreshIntervalMinutes:
          chartRefreshIntervalMinutes ?? this.chartRefreshIntervalMinutes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cacheLimitMb.present) {
      map['cache_limit_mb'] = Variable<int>(cacheLimitMb.value);
    }
    if (radioStatusIntervalMinutes.present) {
      map['radio_status_interval_minutes'] = Variable<int>(
        radioStatusIntervalMinutes.value,
      );
    }
    if (chartRefreshIntervalMinutes.present) {
      map['chart_refresh_interval_minutes'] = Variable<int>(
        chartRefreshIntervalMinutes.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NetworkSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('cacheLimitMb: $cacheLimitMb, ')
          ..write('radioStatusIntervalMinutes: $radioStatusIntervalMinutes, ')
          ..write('chartRefreshIntervalMinutes: $chartRefreshIntervalMinutes')
          ..write(')'))
        .toString();
  }
}

class $PlaybackSettingsTableTable extends PlaybackSettingsTable
    with TableInfo<$PlaybackSettingsTableTable, PlaybackSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackSettingsTableTable(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumnWithTypeConverter<AudioQuality?, String>
  audioQuality =
      GeneratedColumn<String>(
        'audio_quality',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<AudioQuality?>(
        $PlaybackSettingsTableTable.$converteraudioQualityn,
      );
  @override
  late final GeneratedColumnWithTypeConverter<AudioFormatPriority?, String>
  audioFormatPriority =
      GeneratedColumn<String>(
        'audio_format_priority',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<AudioFormatPriority?>(
        $PlaybackSettingsTableTable.$converteraudioFormatPriorityn,
      );
  static const VerificationMeta _rememberPositionMeta = const VerificationMeta(
    'rememberPosition',
  );
  @override
  late final GeneratedColumn<bool> rememberPosition = GeneratedColumn<bool>(
    'remember_position',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remember_position" IN (0, 1))',
    ),
  );
  static const VerificationMeta _tempPlayRewindSecondsMeta =
      const VerificationMeta('tempPlayRewindSeconds');
  @override
  late final GeneratedColumn<int> tempPlayRewindSeconds = GeneratedColumn<int>(
    'temp_play_rewind_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skipPreviewClipsMeta = const VerificationMeta(
    'skipPreviewClips',
  );
  @override
  late final GeneratedColumn<bool> skipPreviewClips = GeneratedColumn<bool>(
    'skip_preview_clips',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("skip_preview_clips" IN (0, 1))',
    ),
  );
  static const VerificationMeta _outputDeviceIdMeta = const VerificationMeta(
    'outputDeviceId',
  );
  @override
  late final GeneratedColumn<String> outputDeviceId = GeneratedColumn<String>(
    'output_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outputDeviceNameMeta = const VerificationMeta(
    'outputDeviceName',
  );
  @override
  late final GeneratedColumn<String> outputDeviceName = GeneratedColumn<String>(
    'output_device_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restartRewindSecondsMeta =
      const VerificationMeta('restartRewindSeconds');
  @override
  late final GeneratedColumn<int> restartRewindSeconds = GeneratedColumn<int>(
    'restart_rewind_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playHistoryLimitMeta = const VerificationMeta(
    'playHistoryLimit',
  );
  @override
  late final GeneratedColumn<int> playHistoryLimit = GeneratedColumn<int>(
    'play_history_limit',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoScrollToCurrentMeta =
      const VerificationMeta('autoScrollToCurrent');
  @override
  late final GeneratedColumn<bool> autoScrollToCurrent = GeneratedColumn<bool>(
    'auto_scroll_to_current',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_scroll_to_current" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    audioQuality,
    audioFormatPriority,
    rememberPosition,
    tempPlayRewindSeconds,
    skipPreviewClips,
    outputDeviceId,
    outputDeviceName,
    restartRewindSeconds,
    playHistoryLimit,
    autoScrollToCurrent,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('remember_position')) {
      context.handle(
        _rememberPositionMeta,
        rememberPosition.isAcceptableOrUnknown(
          data['remember_position']!,
          _rememberPositionMeta,
        ),
      );
    }
    if (data.containsKey('temp_play_rewind_seconds')) {
      context.handle(
        _tempPlayRewindSecondsMeta,
        tempPlayRewindSeconds.isAcceptableOrUnknown(
          data['temp_play_rewind_seconds']!,
          _tempPlayRewindSecondsMeta,
        ),
      );
    }
    if (data.containsKey('skip_preview_clips')) {
      context.handle(
        _skipPreviewClipsMeta,
        skipPreviewClips.isAcceptableOrUnknown(
          data['skip_preview_clips']!,
          _skipPreviewClipsMeta,
        ),
      );
    }
    if (data.containsKey('output_device_id')) {
      context.handle(
        _outputDeviceIdMeta,
        outputDeviceId.isAcceptableOrUnknown(
          data['output_device_id']!,
          _outputDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('output_device_name')) {
      context.handle(
        _outputDeviceNameMeta,
        outputDeviceName.isAcceptableOrUnknown(
          data['output_device_name']!,
          _outputDeviceNameMeta,
        ),
      );
    }
    if (data.containsKey('restart_rewind_seconds')) {
      context.handle(
        _restartRewindSecondsMeta,
        restartRewindSeconds.isAcceptableOrUnknown(
          data['restart_rewind_seconds']!,
          _restartRewindSecondsMeta,
        ),
      );
    }
    if (data.containsKey('play_history_limit')) {
      context.handle(
        _playHistoryLimitMeta,
        playHistoryLimit.isAcceptableOrUnknown(
          data['play_history_limit']!,
          _playHistoryLimitMeta,
        ),
      );
    }
    if (data.containsKey('auto_scroll_to_current')) {
      context.handle(
        _autoScrollToCurrentMeta,
        autoScrollToCurrent.isAcceptableOrUnknown(
          data['auto_scroll_to_current']!,
          _autoScrollToCurrentMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaybackSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      audioQuality: $PlaybackSettingsTableTable.$converteraudioQualityn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}audio_quality'],
        ),
      ),
      audioFormatPriority: $PlaybackSettingsTableTable
          .$converteraudioFormatPriorityn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}audio_format_priority'],
            ),
          ),
      rememberPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remember_position'],
      ),
      tempPlayRewindSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}temp_play_rewind_seconds'],
      ),
      skipPreviewClips: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}skip_preview_clips'],
      ),
      outputDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_device_id'],
      ),
      outputDeviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_device_name'],
      ),
      restartRewindSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}restart_rewind_seconds'],
      ),
      playHistoryLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_history_limit'],
      ),
      autoScrollToCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_scroll_to_current'],
      ),
    );
  }

  @override
  $PlaybackSettingsTableTable createAlias(String alias) {
    return $PlaybackSettingsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<AudioQuality, String> $converteraudioQuality =
      const AudioQualityConverter();
  static TypeConverter<AudioQuality?, String?> $converteraudioQualityn =
      NullAwareTypeConverter.wrap($converteraudioQuality);
  static TypeConverter<AudioFormatPriority, String>
  $converteraudioFormatPriority = const AudioFormatPriorityConverter();
  static TypeConverter<AudioFormatPriority?, String?>
  $converteraudioFormatPriorityn = NullAwareTypeConverter.wrap(
    $converteraudioFormatPriority,
  );
}

class PlaybackSettingsRow extends DataClass
    implements Insertable<PlaybackSettingsRow> {
  /// 固定為 1；CHECK 讓第二列插不進去。
  final int id;
  final AudioQuality? audioQuality;
  final AudioFormatPriority? audioFormatPriority;
  final bool? rememberPosition;
  final int? tempPlayRewindSeconds;
  final bool? skipPreviewClips;

  /// 偏好的輸出裝置（只有 Windows）：mpv 的裝置名與顯示用的描述。
  final String? outputDeviceId;
  final String? outputDeviceName;
  final int? restartRewindSeconds;
  final int? playHistoryLimit;
  final bool? autoScrollToCurrent;
  const PlaybackSettingsRow({
    required this.id,
    this.audioQuality,
    this.audioFormatPriority,
    this.rememberPosition,
    this.tempPlayRewindSeconds,
    this.skipPreviewClips,
    this.outputDeviceId,
    this.outputDeviceName,
    this.restartRewindSeconds,
    this.playHistoryLimit,
    this.autoScrollToCurrent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || audioQuality != null) {
      map['audio_quality'] = Variable<String>(
        $PlaybackSettingsTableTable.$converteraudioQualityn.toSql(audioQuality),
      );
    }
    if (!nullToAbsent || audioFormatPriority != null) {
      map['audio_format_priority'] = Variable<String>(
        $PlaybackSettingsTableTable.$converteraudioFormatPriorityn.toSql(
          audioFormatPriority,
        ),
      );
    }
    if (!nullToAbsent || rememberPosition != null) {
      map['remember_position'] = Variable<bool>(rememberPosition);
    }
    if (!nullToAbsent || tempPlayRewindSeconds != null) {
      map['temp_play_rewind_seconds'] = Variable<int>(tempPlayRewindSeconds);
    }
    if (!nullToAbsent || skipPreviewClips != null) {
      map['skip_preview_clips'] = Variable<bool>(skipPreviewClips);
    }
    if (!nullToAbsent || outputDeviceId != null) {
      map['output_device_id'] = Variable<String>(outputDeviceId);
    }
    if (!nullToAbsent || outputDeviceName != null) {
      map['output_device_name'] = Variable<String>(outputDeviceName);
    }
    if (!nullToAbsent || restartRewindSeconds != null) {
      map['restart_rewind_seconds'] = Variable<int>(restartRewindSeconds);
    }
    if (!nullToAbsent || playHistoryLimit != null) {
      map['play_history_limit'] = Variable<int>(playHistoryLimit);
    }
    if (!nullToAbsent || autoScrollToCurrent != null) {
      map['auto_scroll_to_current'] = Variable<bool>(autoScrollToCurrent);
    }
    return map;
  }

  PlaybackSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return PlaybackSettingsTableCompanion(
      id: Value(id),
      audioQuality: audioQuality == null && nullToAbsent
          ? const Value.absent()
          : Value(audioQuality),
      audioFormatPriority: audioFormatPriority == null && nullToAbsent
          ? const Value.absent()
          : Value(audioFormatPriority),
      rememberPosition: rememberPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(rememberPosition),
      tempPlayRewindSeconds: tempPlayRewindSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(tempPlayRewindSeconds),
      skipPreviewClips: skipPreviewClips == null && nullToAbsent
          ? const Value.absent()
          : Value(skipPreviewClips),
      outputDeviceId: outputDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(outputDeviceId),
      outputDeviceName: outputDeviceName == null && nullToAbsent
          ? const Value.absent()
          : Value(outputDeviceName),
      restartRewindSeconds: restartRewindSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(restartRewindSeconds),
      playHistoryLimit: playHistoryLimit == null && nullToAbsent
          ? const Value.absent()
          : Value(playHistoryLimit),
      autoScrollToCurrent: autoScrollToCurrent == null && nullToAbsent
          ? const Value.absent()
          : Value(autoScrollToCurrent),
    );
  }

  factory PlaybackSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      audioQuality: serializer.fromJson<AudioQuality?>(json['audioQuality']),
      audioFormatPriority: serializer.fromJson<AudioFormatPriority?>(
        json['audioFormatPriority'],
      ),
      rememberPosition: serializer.fromJson<bool?>(json['rememberPosition']),
      tempPlayRewindSeconds: serializer.fromJson<int?>(
        json['tempPlayRewindSeconds'],
      ),
      skipPreviewClips: serializer.fromJson<bool?>(json['skipPreviewClips']),
      outputDeviceId: serializer.fromJson<String?>(json['outputDeviceId']),
      outputDeviceName: serializer.fromJson<String?>(json['outputDeviceName']),
      restartRewindSeconds: serializer.fromJson<int?>(
        json['restartRewindSeconds'],
      ),
      playHistoryLimit: serializer.fromJson<int?>(json['playHistoryLimit']),
      autoScrollToCurrent: serializer.fromJson<bool?>(
        json['autoScrollToCurrent'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'audioQuality': serializer.toJson<AudioQuality?>(audioQuality),
      'audioFormatPriority': serializer.toJson<AudioFormatPriority?>(
        audioFormatPriority,
      ),
      'rememberPosition': serializer.toJson<bool?>(rememberPosition),
      'tempPlayRewindSeconds': serializer.toJson<int?>(tempPlayRewindSeconds),
      'skipPreviewClips': serializer.toJson<bool?>(skipPreviewClips),
      'outputDeviceId': serializer.toJson<String?>(outputDeviceId),
      'outputDeviceName': serializer.toJson<String?>(outputDeviceName),
      'restartRewindSeconds': serializer.toJson<int?>(restartRewindSeconds),
      'playHistoryLimit': serializer.toJson<int?>(playHistoryLimit),
      'autoScrollToCurrent': serializer.toJson<bool?>(autoScrollToCurrent),
    };
  }

  PlaybackSettingsRow copyWith({
    int? id,
    Value<AudioQuality?> audioQuality = const Value.absent(),
    Value<AudioFormatPriority?> audioFormatPriority = const Value.absent(),
    Value<bool?> rememberPosition = const Value.absent(),
    Value<int?> tempPlayRewindSeconds = const Value.absent(),
    Value<bool?> skipPreviewClips = const Value.absent(),
    Value<String?> outputDeviceId = const Value.absent(),
    Value<String?> outputDeviceName = const Value.absent(),
    Value<int?> restartRewindSeconds = const Value.absent(),
    Value<int?> playHistoryLimit = const Value.absent(),
    Value<bool?> autoScrollToCurrent = const Value.absent(),
  }) => PlaybackSettingsRow(
    id: id ?? this.id,
    audioQuality: audioQuality.present ? audioQuality.value : this.audioQuality,
    audioFormatPriority: audioFormatPriority.present
        ? audioFormatPriority.value
        : this.audioFormatPriority,
    rememberPosition: rememberPosition.present
        ? rememberPosition.value
        : this.rememberPosition,
    tempPlayRewindSeconds: tempPlayRewindSeconds.present
        ? tempPlayRewindSeconds.value
        : this.tempPlayRewindSeconds,
    skipPreviewClips: skipPreviewClips.present
        ? skipPreviewClips.value
        : this.skipPreviewClips,
    outputDeviceId: outputDeviceId.present
        ? outputDeviceId.value
        : this.outputDeviceId,
    outputDeviceName: outputDeviceName.present
        ? outputDeviceName.value
        : this.outputDeviceName,
    restartRewindSeconds: restartRewindSeconds.present
        ? restartRewindSeconds.value
        : this.restartRewindSeconds,
    playHistoryLimit: playHistoryLimit.present
        ? playHistoryLimit.value
        : this.playHistoryLimit,
    autoScrollToCurrent: autoScrollToCurrent.present
        ? autoScrollToCurrent.value
        : this.autoScrollToCurrent,
  );
  PlaybackSettingsRow copyWithCompanion(PlaybackSettingsTableCompanion data) {
    return PlaybackSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      audioQuality: data.audioQuality.present
          ? data.audioQuality.value
          : this.audioQuality,
      audioFormatPriority: data.audioFormatPriority.present
          ? data.audioFormatPriority.value
          : this.audioFormatPriority,
      rememberPosition: data.rememberPosition.present
          ? data.rememberPosition.value
          : this.rememberPosition,
      tempPlayRewindSeconds: data.tempPlayRewindSeconds.present
          ? data.tempPlayRewindSeconds.value
          : this.tempPlayRewindSeconds,
      skipPreviewClips: data.skipPreviewClips.present
          ? data.skipPreviewClips.value
          : this.skipPreviewClips,
      outputDeviceId: data.outputDeviceId.present
          ? data.outputDeviceId.value
          : this.outputDeviceId,
      outputDeviceName: data.outputDeviceName.present
          ? data.outputDeviceName.value
          : this.outputDeviceName,
      restartRewindSeconds: data.restartRewindSeconds.present
          ? data.restartRewindSeconds.value
          : this.restartRewindSeconds,
      playHistoryLimit: data.playHistoryLimit.present
          ? data.playHistoryLimit.value
          : this.playHistoryLimit,
      autoScrollToCurrent: data.autoScrollToCurrent.present
          ? data.autoScrollToCurrent.value
          : this.autoScrollToCurrent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackSettingsRow(')
          ..write('id: $id, ')
          ..write('audioQuality: $audioQuality, ')
          ..write('audioFormatPriority: $audioFormatPriority, ')
          ..write('rememberPosition: $rememberPosition, ')
          ..write('tempPlayRewindSeconds: $tempPlayRewindSeconds, ')
          ..write('skipPreviewClips: $skipPreviewClips, ')
          ..write('outputDeviceId: $outputDeviceId, ')
          ..write('outputDeviceName: $outputDeviceName, ')
          ..write('restartRewindSeconds: $restartRewindSeconds, ')
          ..write('playHistoryLimit: $playHistoryLimit, ')
          ..write('autoScrollToCurrent: $autoScrollToCurrent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    audioQuality,
    audioFormatPriority,
    rememberPosition,
    tempPlayRewindSeconds,
    skipPreviewClips,
    outputDeviceId,
    outputDeviceName,
    restartRewindSeconds,
    playHistoryLimit,
    autoScrollToCurrent,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackSettingsRow &&
          other.id == this.id &&
          other.audioQuality == this.audioQuality &&
          other.audioFormatPriority == this.audioFormatPriority &&
          other.rememberPosition == this.rememberPosition &&
          other.tempPlayRewindSeconds == this.tempPlayRewindSeconds &&
          other.skipPreviewClips == this.skipPreviewClips &&
          other.outputDeviceId == this.outputDeviceId &&
          other.outputDeviceName == this.outputDeviceName &&
          other.restartRewindSeconds == this.restartRewindSeconds &&
          other.playHistoryLimit == this.playHistoryLimit &&
          other.autoScrollToCurrent == this.autoScrollToCurrent);
}

class PlaybackSettingsTableCompanion
    extends UpdateCompanion<PlaybackSettingsRow> {
  final Value<int> id;
  final Value<AudioQuality?> audioQuality;
  final Value<AudioFormatPriority?> audioFormatPriority;
  final Value<bool?> rememberPosition;
  final Value<int?> tempPlayRewindSeconds;
  final Value<bool?> skipPreviewClips;
  final Value<String?> outputDeviceId;
  final Value<String?> outputDeviceName;
  final Value<int?> restartRewindSeconds;
  final Value<int?> playHistoryLimit;
  final Value<bool?> autoScrollToCurrent;
  const PlaybackSettingsTableCompanion({
    this.id = const Value.absent(),
    this.audioQuality = const Value.absent(),
    this.audioFormatPriority = const Value.absent(),
    this.rememberPosition = const Value.absent(),
    this.tempPlayRewindSeconds = const Value.absent(),
    this.skipPreviewClips = const Value.absent(),
    this.outputDeviceId = const Value.absent(),
    this.outputDeviceName = const Value.absent(),
    this.restartRewindSeconds = const Value.absent(),
    this.playHistoryLimit = const Value.absent(),
    this.autoScrollToCurrent = const Value.absent(),
  });
  PlaybackSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    this.audioQuality = const Value.absent(),
    this.audioFormatPriority = const Value.absent(),
    this.rememberPosition = const Value.absent(),
    this.tempPlayRewindSeconds = const Value.absent(),
    this.skipPreviewClips = const Value.absent(),
    this.outputDeviceId = const Value.absent(),
    this.outputDeviceName = const Value.absent(),
    this.restartRewindSeconds = const Value.absent(),
    this.playHistoryLimit = const Value.absent(),
    this.autoScrollToCurrent = const Value.absent(),
  });
  static Insertable<PlaybackSettingsRow> custom({
    Expression<int>? id,
    Expression<String>? audioQuality,
    Expression<String>? audioFormatPriority,
    Expression<bool>? rememberPosition,
    Expression<int>? tempPlayRewindSeconds,
    Expression<bool>? skipPreviewClips,
    Expression<String>? outputDeviceId,
    Expression<String>? outputDeviceName,
    Expression<int>? restartRewindSeconds,
    Expression<int>? playHistoryLimit,
    Expression<bool>? autoScrollToCurrent,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (audioQuality != null) 'audio_quality': audioQuality,
      if (audioFormatPriority != null)
        'audio_format_priority': audioFormatPriority,
      if (rememberPosition != null) 'remember_position': rememberPosition,
      if (tempPlayRewindSeconds != null)
        'temp_play_rewind_seconds': tempPlayRewindSeconds,
      if (skipPreviewClips != null) 'skip_preview_clips': skipPreviewClips,
      if (outputDeviceId != null) 'output_device_id': outputDeviceId,
      if (outputDeviceName != null) 'output_device_name': outputDeviceName,
      if (restartRewindSeconds != null)
        'restart_rewind_seconds': restartRewindSeconds,
      if (playHistoryLimit != null) 'play_history_limit': playHistoryLimit,
      if (autoScrollToCurrent != null)
        'auto_scroll_to_current': autoScrollToCurrent,
    });
  }

  PlaybackSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<AudioQuality?>? audioQuality,
    Value<AudioFormatPriority?>? audioFormatPriority,
    Value<bool?>? rememberPosition,
    Value<int?>? tempPlayRewindSeconds,
    Value<bool?>? skipPreviewClips,
    Value<String?>? outputDeviceId,
    Value<String?>? outputDeviceName,
    Value<int?>? restartRewindSeconds,
    Value<int?>? playHistoryLimit,
    Value<bool?>? autoScrollToCurrent,
  }) {
    return PlaybackSettingsTableCompanion(
      id: id ?? this.id,
      audioQuality: audioQuality ?? this.audioQuality,
      audioFormatPriority: audioFormatPriority ?? this.audioFormatPriority,
      rememberPosition: rememberPosition ?? this.rememberPosition,
      tempPlayRewindSeconds:
          tempPlayRewindSeconds ?? this.tempPlayRewindSeconds,
      skipPreviewClips: skipPreviewClips ?? this.skipPreviewClips,
      outputDeviceId: outputDeviceId ?? this.outputDeviceId,
      outputDeviceName: outputDeviceName ?? this.outputDeviceName,
      restartRewindSeconds: restartRewindSeconds ?? this.restartRewindSeconds,
      playHistoryLimit: playHistoryLimit ?? this.playHistoryLimit,
      autoScrollToCurrent: autoScrollToCurrent ?? this.autoScrollToCurrent,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (audioQuality.present) {
      map['audio_quality'] = Variable<String>(
        $PlaybackSettingsTableTable.$converteraudioQualityn.toSql(
          audioQuality.value,
        ),
      );
    }
    if (audioFormatPriority.present) {
      map['audio_format_priority'] = Variable<String>(
        $PlaybackSettingsTableTable.$converteraudioFormatPriorityn.toSql(
          audioFormatPriority.value,
        ),
      );
    }
    if (rememberPosition.present) {
      map['remember_position'] = Variable<bool>(rememberPosition.value);
    }
    if (tempPlayRewindSeconds.present) {
      map['temp_play_rewind_seconds'] = Variable<int>(
        tempPlayRewindSeconds.value,
      );
    }
    if (skipPreviewClips.present) {
      map['skip_preview_clips'] = Variable<bool>(skipPreviewClips.value);
    }
    if (outputDeviceId.present) {
      map['output_device_id'] = Variable<String>(outputDeviceId.value);
    }
    if (outputDeviceName.present) {
      map['output_device_name'] = Variable<String>(outputDeviceName.value);
    }
    if (restartRewindSeconds.present) {
      map['restart_rewind_seconds'] = Variable<int>(restartRewindSeconds.value);
    }
    if (playHistoryLimit.present) {
      map['play_history_limit'] = Variable<int>(playHistoryLimit.value);
    }
    if (autoScrollToCurrent.present) {
      map['auto_scroll_to_current'] = Variable<bool>(autoScrollToCurrent.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('audioQuality: $audioQuality, ')
          ..write('audioFormatPriority: $audioFormatPriority, ')
          ..write('rememberPosition: $rememberPosition, ')
          ..write('tempPlayRewindSeconds: $tempPlayRewindSeconds, ')
          ..write('skipPreviewClips: $skipPreviewClips, ')
          ..write('outputDeviceId: $outputDeviceId, ')
          ..write('outputDeviceName: $outputDeviceName, ')
          ..write('restartRewindSeconds: $restartRewindSeconds, ')
          ..write('playHistoryLimit: $playHistoryLimit, ')
          ..write('autoScrollToCurrent: $autoScrollToCurrent')
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
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sourceIndexUrlMeta = const VerificationMeta(
    'sourceIndexUrl',
  );
  @override
  late final GeneratedColumn<String> sourceIndexUrl = GeneratedColumn<String>(
    'source_index_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checksJsonMeta = const VerificationMeta(
    'checksJson',
  );
  @override
  late final GeneratedColumn<String> checksJson = GeneratedColumn<String>(
    'checks_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fromDevFolderMeta = const VerificationMeta(
    'fromDevFolder',
  );
  @override
  late final GeneratedColumn<bool> fromDevFolder = GeneratedColumn<bool>(
    'from_dev_folder',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("from_dev_folder" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    manifestJson,
    script,
    installedAt,
    enabled,
    sourceIndexUrl,
    checksJson,
    fromDevFolder,
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
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('source_index_url')) {
      context.handle(
        _sourceIndexUrlMeta,
        sourceIndexUrl.isAcceptableOrUnknown(
          data['source_index_url']!,
          _sourceIndexUrlMeta,
        ),
      );
    }
    if (data.containsKey('checks_json')) {
      context.handle(
        _checksJsonMeta,
        checksJson.isAcceptableOrUnknown(data['checks_json']!, _checksJsonMeta),
      );
    }
    if (data.containsKey('from_dev_folder')) {
      context.handle(
        _fromDevFolderMeta,
        fromDevFolder.isAcceptableOrUnknown(
          data['from_dev_folder']!,
          _fromDevFolderMeta,
        ),
      );
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
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      sourceIndexUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_index_url'],
      ),
      checksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checks_json'],
      ),
      fromDevFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}from_dev_folder'],
      )!,
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

  /// 啟用與否（ADR 0030 §決定 7）；停用的插件不載入。升級前裝好的列為真。
  final bool enabled;

  /// 來自哪個 index 網址；空＝從檔案或網址安裝（ADR 0030 §決定 6）。
  final String? sourceIndexUrl;

  /// 從 index 安裝時一併存的 `checks.json` 原文，給健康檢查用；沒有就是空。
  final String? checksJson;

  /// 真＝這一列是插件開發工具為了 `plugin_storage` 的外鍵補的，不是使用者裝的
  /// （M3 PR 16b）；每次套用開發資料夾時對齊，不屬於資料夾的標記列會被刪掉。
  final bool fromDevFolder;
  const InstalledPluginRow({
    required this.id,
    required this.version,
    required this.manifestJson,
    required this.script,
    required this.installedAt,
    required this.enabled,
    this.sourceIndexUrl,
    this.checksJson,
    required this.fromDevFolder,
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
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || sourceIndexUrl != null) {
      map['source_index_url'] = Variable<String>(sourceIndexUrl);
    }
    if (!nullToAbsent || checksJson != null) {
      map['checks_json'] = Variable<String>(checksJson);
    }
    map['from_dev_folder'] = Variable<bool>(fromDevFolder);
    return map;
  }

  InstalledPluginsTableCompanion toCompanion(bool nullToAbsent) {
    return InstalledPluginsTableCompanion(
      id: Value(id),
      version: Value(version),
      manifestJson: Value(manifestJson),
      script: Value(script),
      installedAt: Value(installedAt),
      enabled: Value(enabled),
      sourceIndexUrl: sourceIndexUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceIndexUrl),
      checksJson: checksJson == null && nullToAbsent
          ? const Value.absent()
          : Value(checksJson),
      fromDevFolder: Value(fromDevFolder),
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
      enabled: serializer.fromJson<bool>(json['enabled']),
      sourceIndexUrl: serializer.fromJson<String?>(json['sourceIndexUrl']),
      checksJson: serializer.fromJson<String?>(json['checksJson']),
      fromDevFolder: serializer.fromJson<bool>(json['fromDevFolder']),
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
      'enabled': serializer.toJson<bool>(enabled),
      'sourceIndexUrl': serializer.toJson<String?>(sourceIndexUrl),
      'checksJson': serializer.toJson<String?>(checksJson),
      'fromDevFolder': serializer.toJson<bool>(fromDevFolder),
    };
  }

  InstalledPluginRow copyWith({
    String? id,
    String? version,
    String? manifestJson,
    String? script,
    DateTime? installedAt,
    bool? enabled,
    Value<String?> sourceIndexUrl = const Value.absent(),
    Value<String?> checksJson = const Value.absent(),
    bool? fromDevFolder,
  }) => InstalledPluginRow(
    id: id ?? this.id,
    version: version ?? this.version,
    manifestJson: manifestJson ?? this.manifestJson,
    script: script ?? this.script,
    installedAt: installedAt ?? this.installedAt,
    enabled: enabled ?? this.enabled,
    sourceIndexUrl: sourceIndexUrl.present
        ? sourceIndexUrl.value
        : this.sourceIndexUrl,
    checksJson: checksJson.present ? checksJson.value : this.checksJson,
    fromDevFolder: fromDevFolder ?? this.fromDevFolder,
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
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sourceIndexUrl: data.sourceIndexUrl.present
          ? data.sourceIndexUrl.value
          : this.sourceIndexUrl,
      checksJson: data.checksJson.present
          ? data.checksJson.value
          : this.checksJson,
      fromDevFolder: data.fromDevFolder.present
          ? data.fromDevFolder.value
          : this.fromDevFolder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstalledPluginRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('manifestJson: $manifestJson, ')
          ..write('script: $script, ')
          ..write('installedAt: $installedAt, ')
          ..write('enabled: $enabled, ')
          ..write('sourceIndexUrl: $sourceIndexUrl, ')
          ..write('checksJson: $checksJson, ')
          ..write('fromDevFolder: $fromDevFolder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    manifestJson,
    script,
    installedAt,
    enabled,
    sourceIndexUrl,
    checksJson,
    fromDevFolder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstalledPluginRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.manifestJson == this.manifestJson &&
          other.script == this.script &&
          other.installedAt == this.installedAt &&
          other.enabled == this.enabled &&
          other.sourceIndexUrl == this.sourceIndexUrl &&
          other.checksJson == this.checksJson &&
          other.fromDevFolder == this.fromDevFolder);
}

class InstalledPluginsTableCompanion
    extends UpdateCompanion<InstalledPluginRow> {
  final Value<String> id;
  final Value<String> version;
  final Value<String> manifestJson;
  final Value<String> script;
  final Value<DateTime> installedAt;
  final Value<bool> enabled;
  final Value<String?> sourceIndexUrl;
  final Value<String?> checksJson;
  final Value<bool> fromDevFolder;
  final Value<int> rowid;
  const InstalledPluginsTableCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.manifestJson = const Value.absent(),
    this.script = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sourceIndexUrl = const Value.absent(),
    this.checksJson = const Value.absent(),
    this.fromDevFolder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstalledPluginsTableCompanion.insert({
    required String id,
    required String version,
    required String manifestJson,
    required String script,
    required DateTime installedAt,
    this.enabled = const Value.absent(),
    this.sourceIndexUrl = const Value.absent(),
    this.checksJson = const Value.absent(),
    this.fromDevFolder = const Value.absent(),
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
    Expression<bool>? enabled,
    Expression<String>? sourceIndexUrl,
    Expression<String>? checksJson,
    Expression<bool>? fromDevFolder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (manifestJson != null) 'manifest_json': manifestJson,
      if (script != null) 'script': script,
      if (installedAt != null) 'installed_at': installedAt,
      if (enabled != null) 'enabled': enabled,
      if (sourceIndexUrl != null) 'source_index_url': sourceIndexUrl,
      if (checksJson != null) 'checks_json': checksJson,
      if (fromDevFolder != null) 'from_dev_folder': fromDevFolder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstalledPluginsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? version,
    Value<String>? manifestJson,
    Value<String>? script,
    Value<DateTime>? installedAt,
    Value<bool>? enabled,
    Value<String?>? sourceIndexUrl,
    Value<String?>? checksJson,
    Value<bool>? fromDevFolder,
    Value<int>? rowid,
  }) {
    return InstalledPluginsTableCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      manifestJson: manifestJson ?? this.manifestJson,
      script: script ?? this.script,
      installedAt: installedAt ?? this.installedAt,
      enabled: enabled ?? this.enabled,
      sourceIndexUrl: sourceIndexUrl ?? this.sourceIndexUrl,
      checksJson: checksJson ?? this.checksJson,
      fromDevFolder: fromDevFolder ?? this.fromDevFolder,
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
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sourceIndexUrl.present) {
      map['source_index_url'] = Variable<String>(sourceIndexUrl.value);
    }
    if (checksJson.present) {
      map['checks_json'] = Variable<String>(checksJson.value);
    }
    if (fromDevFolder.present) {
      map['from_dev_folder'] = Variable<bool>(fromDevFolder.value);
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
          ..write('enabled: $enabled, ')
          ..write('sourceIndexUrl: $sourceIndexUrl, ')
          ..write('checksJson: $checksJson, ')
          ..write('fromDevFolder: $fromDevFolder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PluginIndexesTableTable extends PluginIndexesTable
    with TableInfo<$PluginIndexesTableTable, PluginIndexRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PluginIndexesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> addedAt =
      GeneratedColumn<int>(
        'added_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PluginIndexesTableTable.$converteraddedAt);
  @override
  List<GeneratedColumn> get $columns => [url, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plugin_indexes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PluginIndexRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  PluginIndexRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PluginIndexRow(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      addedAt: $PluginIndexesTableTable.$converteraddedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}added_at'],
        )!,
      ),
    );
  }

  @override
  $PluginIndexesTableTable createAlias(String alias) {
    return $PluginIndexesTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converteraddedAt =
      const EpochMillisecondsConverter();
}

class PluginIndexRow extends DataClass implements Insertable<PluginIndexRow> {
  final String url;

  /// UTC epoch 毫秒。
  final DateTime addedAt;
  const PluginIndexRow({required this.url, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    {
      map['added_at'] = Variable<int>(
        $PluginIndexesTableTable.$converteraddedAt.toSql(addedAt),
      );
    }
    return map;
  }

  PluginIndexesTableCompanion toCompanion(bool nullToAbsent) {
    return PluginIndexesTableCompanion(
      url: Value(url),
      addedAt: Value(addedAt),
    );
  }

  factory PluginIndexRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PluginIndexRow(
      url: serializer.fromJson<String>(json['url']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  PluginIndexRow copyWith({String? url, DateTime? addedAt}) =>
      PluginIndexRow(url: url ?? this.url, addedAt: addedAt ?? this.addedAt);
  PluginIndexRow copyWithCompanion(PluginIndexesTableCompanion data) {
    return PluginIndexRow(
      url: data.url.present ? data.url.value : this.url,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PluginIndexRow(')
          ..write('url: $url, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(url, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PluginIndexRow &&
          other.url == this.url &&
          other.addedAt == this.addedAt);
}

class PluginIndexesTableCompanion extends UpdateCompanion<PluginIndexRow> {
  final Value<String> url;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const PluginIndexesTableCompanion({
    this.url = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PluginIndexesTableCompanion.insert({
    required String url,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       addedAt = Value(addedAt);
  static Insertable<PluginIndexRow> custom({
    Expression<String>? url,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PluginIndexesTableCompanion copyWith({
    Value<String>? url,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return PluginIndexesTableCompanion(
      url: url ?? this.url,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(
        $PluginIndexesTableTable.$converteraddedAt.toSql(addedAt.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PluginIndexesTableCompanion(')
          ..write('url: $url, ')
          ..write('addedAt: $addedAt, ')
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

class $TracksTableTable extends TracksTable
    with TableInfo<$TracksTableTable, TrackRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTypeIdMeta = const VerificationMeta(
    'sourceTypeId',
  );
  @override
  late final GeneratedColumn<String> sourceTypeId = GeneratedColumn<String>(
    'source_type_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<int> cid = GeneratedColumn<int>(
    'cid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploaderMeta = const VerificationMeta(
    'uploader',
  );
  @override
  late final GeneratedColumn<String> uploader = GeneratedColumn<String>(
    'uploader',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artworkJsonMeta = const VerificationMeta(
    'artworkJson',
  );
  @override
  late final GeneratedColumn<String> artworkJson = GeneratedColumn<String>(
    'artwork_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($TracksTableTable.$converterupdatedAt);
  static const VerificationMeta _partIndexMeta = const VerificationMeta(
    'partIndex',
  );
  @override
  late final GeneratedColumn<int> partIndex = GeneratedColumn<int>(
    'part_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentTitleMeta = const VerificationMeta(
    'parentTitle',
  );
  @override
  late final GeneratedColumn<String> parentTitle = GeneratedColumn<String>(
    'parent_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackKey,
    sourceTypeId,
    sourceId,
    cid,
    title,
    uploader,
    durationMs,
    artworkJson,
    updatedAt,
    partIndex,
    parentTitle,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    if (data.containsKey('source_type_id')) {
      context.handle(
        _sourceTypeIdMeta,
        sourceTypeId.isAcceptableOrUnknown(
          data['source_type_id']!,
          _sourceTypeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeIdMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('cid')) {
      context.handle(
        _cidMeta,
        cid.isAcceptableOrUnknown(data['cid']!, _cidMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('uploader')) {
      context.handle(
        _uploaderMeta,
        uploader.isAcceptableOrUnknown(data['uploader']!, _uploaderMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('artwork_json')) {
      context.handle(
        _artworkJsonMeta,
        artworkJson.isAcceptableOrUnknown(
          data['artwork_json']!,
          _artworkJsonMeta,
        ),
      );
    }
    if (data.containsKey('part_index')) {
      context.handle(
        _partIndexMeta,
        partIndex.isAcceptableOrUnknown(data['part_index']!, _partIndexMeta),
      );
    }
    if (data.containsKey('parent_title')) {
      context.handle(
        _parentTitleMeta,
        parentTitle.isAcceptableOrUnknown(
          data['parent_title']!,
          _parentTitleMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackKey};
  @override
  TrackRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackRow(
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      sourceTypeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type_id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      cid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cid'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      uploader: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uploader'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      artworkJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_json'],
      ),
      updatedAt: $TracksTableTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      partIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_index'],
      ),
      parentTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_title'],
      ),
    );
  }

  @override
  $TracksTableTable createAlias(String alias) {
    return $TracksTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterupdatedAt =
      const EpochMillisecondsConverter();
}

class TrackRow extends DataClass implements Insertable<TrackRow> {
  /// `TrackKey.format` 的輸出（ADR 0005）。
  final String trackKey;

  /// 曲目鍵的三段，查詢與 M5 對照用。
  final String sourceTypeId;
  final String sourceId;
  final int? cid;
  final String title;
  final String? uploader;
  final int? durationMs;

  /// `[{url, width?}]`，ADR 0016 §決定 4 的 DTO 原樣。
  final String? artworkJson;

  /// 最後一次 upsert。
  final DateTime updatedAt;

  /// 分 P 曲目才有：分 P 的序號（從 1 起）與影片標題（M3 design §3.1、§11.1）。
  final int? partIndex;
  final String? parentTitle;
  const TrackRow({
    required this.trackKey,
    required this.sourceTypeId,
    required this.sourceId,
    this.cid,
    required this.title,
    this.uploader,
    this.durationMs,
    this.artworkJson,
    required this.updatedAt,
    this.partIndex,
    this.parentTitle,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_key'] = Variable<String>(trackKey);
    map['source_type_id'] = Variable<String>(sourceTypeId);
    map['source_id'] = Variable<String>(sourceId);
    if (!nullToAbsent || cid != null) {
      map['cid'] = Variable<int>(cid);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || uploader != null) {
      map['uploader'] = Variable<String>(uploader);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || artworkJson != null) {
      map['artwork_json'] = Variable<String>(artworkJson);
    }
    {
      map['updated_at'] = Variable<int>(
        $TracksTableTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || partIndex != null) {
      map['part_index'] = Variable<int>(partIndex);
    }
    if (!nullToAbsent || parentTitle != null) {
      map['parent_title'] = Variable<String>(parentTitle);
    }
    return map;
  }

  TracksTableCompanion toCompanion(bool nullToAbsent) {
    return TracksTableCompanion(
      trackKey: Value(trackKey),
      sourceTypeId: Value(sourceTypeId),
      sourceId: Value(sourceId),
      cid: cid == null && nullToAbsent ? const Value.absent() : Value(cid),
      title: Value(title),
      uploader: uploader == null && nullToAbsent
          ? const Value.absent()
          : Value(uploader),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      artworkJson: artworkJson == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkJson),
      updatedAt: Value(updatedAt),
      partIndex: partIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(partIndex),
      parentTitle: parentTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(parentTitle),
    );
  }

  factory TrackRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackRow(
      trackKey: serializer.fromJson<String>(json['trackKey']),
      sourceTypeId: serializer.fromJson<String>(json['sourceTypeId']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      cid: serializer.fromJson<int?>(json['cid']),
      title: serializer.fromJson<String>(json['title']),
      uploader: serializer.fromJson<String?>(json['uploader']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      artworkJson: serializer.fromJson<String?>(json['artworkJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      partIndex: serializer.fromJson<int?>(json['partIndex']),
      parentTitle: serializer.fromJson<String?>(json['parentTitle']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackKey': serializer.toJson<String>(trackKey),
      'sourceTypeId': serializer.toJson<String>(sourceTypeId),
      'sourceId': serializer.toJson<String>(sourceId),
      'cid': serializer.toJson<int?>(cid),
      'title': serializer.toJson<String>(title),
      'uploader': serializer.toJson<String?>(uploader),
      'durationMs': serializer.toJson<int?>(durationMs),
      'artworkJson': serializer.toJson<String?>(artworkJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'partIndex': serializer.toJson<int?>(partIndex),
      'parentTitle': serializer.toJson<String?>(parentTitle),
    };
  }

  TrackRow copyWith({
    String? trackKey,
    String? sourceTypeId,
    String? sourceId,
    Value<int?> cid = const Value.absent(),
    String? title,
    Value<String?> uploader = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> artworkJson = const Value.absent(),
    DateTime? updatedAt,
    Value<int?> partIndex = const Value.absent(),
    Value<String?> parentTitle = const Value.absent(),
  }) => TrackRow(
    trackKey: trackKey ?? this.trackKey,
    sourceTypeId: sourceTypeId ?? this.sourceTypeId,
    sourceId: sourceId ?? this.sourceId,
    cid: cid.present ? cid.value : this.cid,
    title: title ?? this.title,
    uploader: uploader.present ? uploader.value : this.uploader,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    artworkJson: artworkJson.present ? artworkJson.value : this.artworkJson,
    updatedAt: updatedAt ?? this.updatedAt,
    partIndex: partIndex.present ? partIndex.value : this.partIndex,
    parentTitle: parentTitle.present ? parentTitle.value : this.parentTitle,
  );
  TrackRow copyWithCompanion(TracksTableCompanion data) {
    return TrackRow(
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      sourceTypeId: data.sourceTypeId.present
          ? data.sourceTypeId.value
          : this.sourceTypeId,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      cid: data.cid.present ? data.cid.value : this.cid,
      title: data.title.present ? data.title.value : this.title,
      uploader: data.uploader.present ? data.uploader.value : this.uploader,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      artworkJson: data.artworkJson.present
          ? data.artworkJson.value
          : this.artworkJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      partIndex: data.partIndex.present ? data.partIndex.value : this.partIndex,
      parentTitle: data.parentTitle.present
          ? data.parentTitle.value
          : this.parentTitle,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackRow(')
          ..write('trackKey: $trackKey, ')
          ..write('sourceTypeId: $sourceTypeId, ')
          ..write('sourceId: $sourceId, ')
          ..write('cid: $cid, ')
          ..write('title: $title, ')
          ..write('uploader: $uploader, ')
          ..write('durationMs: $durationMs, ')
          ..write('artworkJson: $artworkJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('partIndex: $partIndex, ')
          ..write('parentTitle: $parentTitle')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    trackKey,
    sourceTypeId,
    sourceId,
    cid,
    title,
    uploader,
    durationMs,
    artworkJson,
    updatedAt,
    partIndex,
    parentTitle,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackRow &&
          other.trackKey == this.trackKey &&
          other.sourceTypeId == this.sourceTypeId &&
          other.sourceId == this.sourceId &&
          other.cid == this.cid &&
          other.title == this.title &&
          other.uploader == this.uploader &&
          other.durationMs == this.durationMs &&
          other.artworkJson == this.artworkJson &&
          other.updatedAt == this.updatedAt &&
          other.partIndex == this.partIndex &&
          other.parentTitle == this.parentTitle);
}

class TracksTableCompanion extends UpdateCompanion<TrackRow> {
  final Value<String> trackKey;
  final Value<String> sourceTypeId;
  final Value<String> sourceId;
  final Value<int?> cid;
  final Value<String> title;
  final Value<String?> uploader;
  final Value<int?> durationMs;
  final Value<String?> artworkJson;
  final Value<DateTime> updatedAt;
  final Value<int?> partIndex;
  final Value<String?> parentTitle;
  final Value<int> rowid;
  const TracksTableCompanion({
    this.trackKey = const Value.absent(),
    this.sourceTypeId = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.cid = const Value.absent(),
    this.title = const Value.absent(),
    this.uploader = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artworkJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.partIndex = const Value.absent(),
    this.parentTitle = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TracksTableCompanion.insert({
    required String trackKey,
    required String sourceTypeId,
    required String sourceId,
    this.cid = const Value.absent(),
    required String title,
    this.uploader = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.artworkJson = const Value.absent(),
    required DateTime updatedAt,
    this.partIndex = const Value.absent(),
    this.parentTitle = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackKey = Value(trackKey),
       sourceTypeId = Value(sourceTypeId),
       sourceId = Value(sourceId),
       title = Value(title),
       updatedAt = Value(updatedAt);
  static Insertable<TrackRow> custom({
    Expression<String>? trackKey,
    Expression<String>? sourceTypeId,
    Expression<String>? sourceId,
    Expression<int>? cid,
    Expression<String>? title,
    Expression<String>? uploader,
    Expression<int>? durationMs,
    Expression<String>? artworkJson,
    Expression<int>? updatedAt,
    Expression<int>? partIndex,
    Expression<String>? parentTitle,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackKey != null) 'track_key': trackKey,
      if (sourceTypeId != null) 'source_type_id': sourceTypeId,
      if (sourceId != null) 'source_id': sourceId,
      if (cid != null) 'cid': cid,
      if (title != null) 'title': title,
      if (uploader != null) 'uploader': uploader,
      if (durationMs != null) 'duration_ms': durationMs,
      if (artworkJson != null) 'artwork_json': artworkJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (partIndex != null) 'part_index': partIndex,
      if (parentTitle != null) 'parent_title': parentTitle,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TracksTableCompanion copyWith({
    Value<String>? trackKey,
    Value<String>? sourceTypeId,
    Value<String>? sourceId,
    Value<int?>? cid,
    Value<String>? title,
    Value<String?>? uploader,
    Value<int?>? durationMs,
    Value<String?>? artworkJson,
    Value<DateTime>? updatedAt,
    Value<int?>? partIndex,
    Value<String?>? parentTitle,
    Value<int>? rowid,
  }) {
    return TracksTableCompanion(
      trackKey: trackKey ?? this.trackKey,
      sourceTypeId: sourceTypeId ?? this.sourceTypeId,
      sourceId: sourceId ?? this.sourceId,
      cid: cid ?? this.cid,
      title: title ?? this.title,
      uploader: uploader ?? this.uploader,
      durationMs: durationMs ?? this.durationMs,
      artworkJson: artworkJson ?? this.artworkJson,
      updatedAt: updatedAt ?? this.updatedAt,
      partIndex: partIndex ?? this.partIndex,
      parentTitle: parentTitle ?? this.parentTitle,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (sourceTypeId.present) {
      map['source_type_id'] = Variable<String>(sourceTypeId.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (cid.present) {
      map['cid'] = Variable<int>(cid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (uploader.present) {
      map['uploader'] = Variable<String>(uploader.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (artworkJson.present) {
      map['artwork_json'] = Variable<String>(artworkJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $TracksTableTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (partIndex.present) {
      map['part_index'] = Variable<int>(partIndex.value);
    }
    if (parentTitle.present) {
      map['parent_title'] = Variable<String>(parentTitle.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksTableCompanion(')
          ..write('trackKey: $trackKey, ')
          ..write('sourceTypeId: $sourceTypeId, ')
          ..write('sourceId: $sourceId, ')
          ..write('cid: $cid, ')
          ..write('title: $title, ')
          ..write('uploader: $uploader, ')
          ..write('durationMs: $durationMs, ')
          ..write('artworkJson: $artworkJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('partIndex: $partIndex, ')
          ..write('parentTitle: $parentTitle, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueueEntriesTableTable extends QueueEntriesTable
    with TableInfo<$QueueEntriesTableTable, QueueEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueEntriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (track_key) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _shuffleRankMeta = const VerificationMeta(
    'shuffleRank',
  );
  @override
  late final GeneratedColumn<int> shuffleRank = GeneratedColumn<int>(
    'shuffle_rank',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [position, trackKey, shuffleRank];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    if (data.containsKey('shuffle_rank')) {
      context.handle(
        _shuffleRankMeta,
        shuffleRank.isAcceptableOrUnknown(
          data['shuffle_rank']!,
          _shuffleRankMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {position};
  @override
  QueueEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueEntryRow(
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      shuffleRank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}shuffle_rank'],
      ),
    );
  }

  @override
  $QueueEntriesTableTable createAlias(String alias) {
    return $QueueEntriesTableTable(attachedDatabase, alias);
  }
}

class QueueEntryRow extends DataClass implements Insertable<QueueEntryRow> {
  final int position;
  final String trackKey;

  /// 隨機開啟時，這個位置在本輪排列裡的名次（ADR 0018 §決定 5：隨機順序以位置為
  /// 單位，所以跟著位置走，不跟著歌）；沒開隨機時為空。
  final int? shuffleRank;
  const QueueEntryRow({
    required this.position,
    required this.trackKey,
    this.shuffleRank,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['position'] = Variable<int>(position);
    map['track_key'] = Variable<String>(trackKey);
    if (!nullToAbsent || shuffleRank != null) {
      map['shuffle_rank'] = Variable<int>(shuffleRank);
    }
    return map;
  }

  QueueEntriesTableCompanion toCompanion(bool nullToAbsent) {
    return QueueEntriesTableCompanion(
      position: Value(position),
      trackKey: Value(trackKey),
      shuffleRank: shuffleRank == null && nullToAbsent
          ? const Value.absent()
          : Value(shuffleRank),
    );
  }

  factory QueueEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueEntryRow(
      position: serializer.fromJson<int>(json['position']),
      trackKey: serializer.fromJson<String>(json['trackKey']),
      shuffleRank: serializer.fromJson<int?>(json['shuffleRank']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'position': serializer.toJson<int>(position),
      'trackKey': serializer.toJson<String>(trackKey),
      'shuffleRank': serializer.toJson<int?>(shuffleRank),
    };
  }

  QueueEntryRow copyWith({
    int? position,
    String? trackKey,
    Value<int?> shuffleRank = const Value.absent(),
  }) => QueueEntryRow(
    position: position ?? this.position,
    trackKey: trackKey ?? this.trackKey,
    shuffleRank: shuffleRank.present ? shuffleRank.value : this.shuffleRank,
  );
  QueueEntryRow copyWithCompanion(QueueEntriesTableCompanion data) {
    return QueueEntryRow(
      position: data.position.present ? data.position.value : this.position,
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      shuffleRank: data.shuffleRank.present
          ? data.shuffleRank.value
          : this.shuffleRank,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueEntryRow(')
          ..write('position: $position, ')
          ..write('trackKey: $trackKey, ')
          ..write('shuffleRank: $shuffleRank')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(position, trackKey, shuffleRank);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueEntryRow &&
          other.position == this.position &&
          other.trackKey == this.trackKey &&
          other.shuffleRank == this.shuffleRank);
}

class QueueEntriesTableCompanion extends UpdateCompanion<QueueEntryRow> {
  final Value<int> position;
  final Value<String> trackKey;
  final Value<int?> shuffleRank;
  const QueueEntriesTableCompanion({
    this.position = const Value.absent(),
    this.trackKey = const Value.absent(),
    this.shuffleRank = const Value.absent(),
  });
  QueueEntriesTableCompanion.insert({
    this.position = const Value.absent(),
    required String trackKey,
    this.shuffleRank = const Value.absent(),
  }) : trackKey = Value(trackKey);
  static Insertable<QueueEntryRow> custom({
    Expression<int>? position,
    Expression<String>? trackKey,
    Expression<int>? shuffleRank,
  }) {
    return RawValuesInsertable({
      if (position != null) 'position': position,
      if (trackKey != null) 'track_key': trackKey,
      if (shuffleRank != null) 'shuffle_rank': shuffleRank,
    });
  }

  QueueEntriesTableCompanion copyWith({
    Value<int>? position,
    Value<String>? trackKey,
    Value<int?>? shuffleRank,
  }) {
    return QueueEntriesTableCompanion(
      position: position ?? this.position,
      trackKey: trackKey ?? this.trackKey,
      shuffleRank: shuffleRank ?? this.shuffleRank,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (shuffleRank.present) {
      map['shuffle_rank'] = Variable<int>(shuffleRank.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueEntriesTableCompanion(')
          ..write('position: $position, ')
          ..write('trackKey: $trackKey, ')
          ..write('shuffleRank: $shuffleRank')
          ..write(')'))
        .toString();
  }
}

class $PlayerStateTableTable extends PlayerStateTable
    with TableInfo<$PlayerStateTableTable, PlayerStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayerStateTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _currentPositionMeta = const VerificationMeta(
    'currentPosition',
  );
  @override
  late final GeneratedColumn<int> currentPosition = GeneratedColumn<int>(
    'current_position',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LoopMode, String> loopMode =
      GeneratedColumn<String>(
        'loop_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LoopMode>($PlayerStateTableTable.$converterloopMode);
  static const VerificationMeta _shuffleEnabledMeta = const VerificationMeta(
    'shuffleEnabled',
  );
  @override
  late final GeneratedColumn<bool> shuffleEnabled = GeneratedColumn<bool>(
    'shuffle_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shuffle_enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<double> volume = GeneratedColumn<double>(
    'volume',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mutedMeta = const VerificationMeta('muted');
  @override
  late final GeneratedColumn<bool> muted = GeneratedColumn<bool>(
    'muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("muted" IN (0, 1))',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PlayerMode?, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<PlayerMode?>($PlayerStateTableTable.$convertermoden);
  static const VerificationMeta _mixPluginIdMeta = const VerificationMeta(
    'mixPluginId',
  );
  @override
  late final GeneratedColumn<String> mixPluginId = GeneratedColumn<String>(
    'mix_plugin_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mixIdMeta = const VerificationMeta('mixId');
  @override
  late final GeneratedColumn<String> mixId = GeneratedColumn<String>(
    'mix_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mixTitleMeta = const VerificationMeta(
    'mixTitle',
  );
  @override
  late final GeneratedColumn<String> mixTitle = GeneratedColumn<String>(
    'mix_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mixCursorMeta = const VerificationMeta(
    'mixCursor',
  );
  @override
  late final GeneratedColumn<String> mixCursor = GeneratedColumn<String>(
    'mix_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PlayerStateTableTable.$converterupdatedAt);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    currentPosition,
    positionMs,
    loopMode,
    shuffleEnabled,
    volume,
    muted,
    mode,
    mixPluginId,
    mixId,
    mixTitle,
    mixCursor,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'player_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayerStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('current_position')) {
      context.handle(
        _currentPositionMeta,
        currentPosition.isAcceptableOrUnknown(
          data['current_position']!,
          _currentPositionMeta,
        ),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('shuffle_enabled')) {
      context.handle(
        _shuffleEnabledMeta,
        shuffleEnabled.isAcceptableOrUnknown(
          data['shuffle_enabled']!,
          _shuffleEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_shuffleEnabledMeta);
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    } else if (isInserting) {
      context.missing(_volumeMeta);
    }
    if (data.containsKey('muted')) {
      context.handle(
        _mutedMeta,
        muted.isAcceptableOrUnknown(data['muted']!, _mutedMeta),
      );
    } else if (isInserting) {
      context.missing(_mutedMeta);
    }
    if (data.containsKey('mix_plugin_id')) {
      context.handle(
        _mixPluginIdMeta,
        mixPluginId.isAcceptableOrUnknown(
          data['mix_plugin_id']!,
          _mixPluginIdMeta,
        ),
      );
    }
    if (data.containsKey('mix_id')) {
      context.handle(
        _mixIdMeta,
        mixId.isAcceptableOrUnknown(data['mix_id']!, _mixIdMeta),
      );
    }
    if (data.containsKey('mix_title')) {
      context.handle(
        _mixTitleMeta,
        mixTitle.isAcceptableOrUnknown(data['mix_title']!, _mixTitleMeta),
      );
    }
    if (data.containsKey('mix_cursor')) {
      context.handle(
        _mixCursorMeta,
        mixCursor.isAcceptableOrUnknown(data['mix_cursor']!, _mixCursorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayerStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayerStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      currentPosition: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_position'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      loopMode: $PlayerStateTableTable.$converterloopMode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}loop_mode'],
        )!,
      ),
      shuffleEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shuffle_enabled'],
      )!,
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume'],
      )!,
      muted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}muted'],
      )!,
      mode: $PlayerStateTableTable.$convertermoden.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        ),
      ),
      mixPluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_plugin_id'],
      ),
      mixId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_id'],
      ),
      mixTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_title'],
      ),
      mixCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_cursor'],
      ),
      updatedAt: $PlayerStateTableTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
    );
  }

  @override
  $PlayerStateTableTable createAlias(String alias) {
    return $PlayerStateTableTable(attachedDatabase, alias);
  }

  static TypeConverter<LoopMode, String> $converterloopMode =
      const LoopModeConverter();
  static TypeConverter<PlayerMode, String> $convertermode =
      const PlayerModeConverter();
  static TypeConverter<PlayerMode?, String?> $convertermoden =
      NullAwareTypeConverter.wrap($convertermode);
  static TypeConverter<DateTime, int> $converterupdatedAt =
      const EpochMillisecondsConverter();
}

class PlayerStateRow extends DataClass implements Insertable<PlayerStateRow> {
  /// 固定為 1；CHECK 讓第二列插不進去。
  final int id;

  /// 佇列目前這首的位置；佇列是空的時為空。
  final int? currentPosition;
  final int positionMs;
  final LoopMode loopMode;
  final bool shuffleEnabled;

  /// 0–1；靜音時是取消靜音後回到的值。
  final double volume;
  final bool muted;

  /// 空（舊版的列）或 `queue`＝一般佇列；`mix`＝Mix，身分在下面四欄（M3 PR 19）。
  final PlayerMode? mode;
  final String? mixPluginId;
  final String? mixId;
  final String? mixTitle;

  /// 插件的不透明字串；空＝這個 Mix 沒有更多。
  final String? mixCursor;
  final DateTime updatedAt;
  const PlayerStateRow({
    required this.id,
    this.currentPosition,
    required this.positionMs,
    required this.loopMode,
    required this.shuffleEnabled,
    required this.volume,
    required this.muted,
    this.mode,
    this.mixPluginId,
    this.mixId,
    this.mixTitle,
    this.mixCursor,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || currentPosition != null) {
      map['current_position'] = Variable<int>(currentPosition);
    }
    map['position_ms'] = Variable<int>(positionMs);
    {
      map['loop_mode'] = Variable<String>(
        $PlayerStateTableTable.$converterloopMode.toSql(loopMode),
      );
    }
    map['shuffle_enabled'] = Variable<bool>(shuffleEnabled);
    map['volume'] = Variable<double>(volume);
    map['muted'] = Variable<bool>(muted);
    if (!nullToAbsent || mode != null) {
      map['mode'] = Variable<String>(
        $PlayerStateTableTable.$convertermoden.toSql(mode),
      );
    }
    if (!nullToAbsent || mixPluginId != null) {
      map['mix_plugin_id'] = Variable<String>(mixPluginId);
    }
    if (!nullToAbsent || mixId != null) {
      map['mix_id'] = Variable<String>(mixId);
    }
    if (!nullToAbsent || mixTitle != null) {
      map['mix_title'] = Variable<String>(mixTitle);
    }
    if (!nullToAbsent || mixCursor != null) {
      map['mix_cursor'] = Variable<String>(mixCursor);
    }
    {
      map['updated_at'] = Variable<int>(
        $PlayerStateTableTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    return map;
  }

  PlayerStateTableCompanion toCompanion(bool nullToAbsent) {
    return PlayerStateTableCompanion(
      id: Value(id),
      currentPosition: currentPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(currentPosition),
      positionMs: Value(positionMs),
      loopMode: Value(loopMode),
      shuffleEnabled: Value(shuffleEnabled),
      volume: Value(volume),
      muted: Value(muted),
      mode: mode == null && nullToAbsent ? const Value.absent() : Value(mode),
      mixPluginId: mixPluginId == null && nullToAbsent
          ? const Value.absent()
          : Value(mixPluginId),
      mixId: mixId == null && nullToAbsent
          ? const Value.absent()
          : Value(mixId),
      mixTitle: mixTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(mixTitle),
      mixCursor: mixCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(mixCursor),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlayerStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayerStateRow(
      id: serializer.fromJson<int>(json['id']),
      currentPosition: serializer.fromJson<int?>(json['currentPosition']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      loopMode: serializer.fromJson<LoopMode>(json['loopMode']),
      shuffleEnabled: serializer.fromJson<bool>(json['shuffleEnabled']),
      volume: serializer.fromJson<double>(json['volume']),
      muted: serializer.fromJson<bool>(json['muted']),
      mode: serializer.fromJson<PlayerMode?>(json['mode']),
      mixPluginId: serializer.fromJson<String?>(json['mixPluginId']),
      mixId: serializer.fromJson<String?>(json['mixId']),
      mixTitle: serializer.fromJson<String?>(json['mixTitle']),
      mixCursor: serializer.fromJson<String?>(json['mixCursor']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'currentPosition': serializer.toJson<int?>(currentPosition),
      'positionMs': serializer.toJson<int>(positionMs),
      'loopMode': serializer.toJson<LoopMode>(loopMode),
      'shuffleEnabled': serializer.toJson<bool>(shuffleEnabled),
      'volume': serializer.toJson<double>(volume),
      'muted': serializer.toJson<bool>(muted),
      'mode': serializer.toJson<PlayerMode?>(mode),
      'mixPluginId': serializer.toJson<String?>(mixPluginId),
      'mixId': serializer.toJson<String?>(mixId),
      'mixTitle': serializer.toJson<String?>(mixTitle),
      'mixCursor': serializer.toJson<String?>(mixCursor),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlayerStateRow copyWith({
    int? id,
    Value<int?> currentPosition = const Value.absent(),
    int? positionMs,
    LoopMode? loopMode,
    bool? shuffleEnabled,
    double? volume,
    bool? muted,
    Value<PlayerMode?> mode = const Value.absent(),
    Value<String?> mixPluginId = const Value.absent(),
    Value<String?> mixId = const Value.absent(),
    Value<String?> mixTitle = const Value.absent(),
    Value<String?> mixCursor = const Value.absent(),
    DateTime? updatedAt,
  }) => PlayerStateRow(
    id: id ?? this.id,
    currentPosition: currentPosition.present
        ? currentPosition.value
        : this.currentPosition,
    positionMs: positionMs ?? this.positionMs,
    loopMode: loopMode ?? this.loopMode,
    shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    mode: mode.present ? mode.value : this.mode,
    mixPluginId: mixPluginId.present ? mixPluginId.value : this.mixPluginId,
    mixId: mixId.present ? mixId.value : this.mixId,
    mixTitle: mixTitle.present ? mixTitle.value : this.mixTitle,
    mixCursor: mixCursor.present ? mixCursor.value : this.mixCursor,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlayerStateRow copyWithCompanion(PlayerStateTableCompanion data) {
    return PlayerStateRow(
      id: data.id.present ? data.id.value : this.id,
      currentPosition: data.currentPosition.present
          ? data.currentPosition.value
          : this.currentPosition,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      loopMode: data.loopMode.present ? data.loopMode.value : this.loopMode,
      shuffleEnabled: data.shuffleEnabled.present
          ? data.shuffleEnabled.value
          : this.shuffleEnabled,
      volume: data.volume.present ? data.volume.value : this.volume,
      muted: data.muted.present ? data.muted.value : this.muted,
      mode: data.mode.present ? data.mode.value : this.mode,
      mixPluginId: data.mixPluginId.present
          ? data.mixPluginId.value
          : this.mixPluginId,
      mixId: data.mixId.present ? data.mixId.value : this.mixId,
      mixTitle: data.mixTitle.present ? data.mixTitle.value : this.mixTitle,
      mixCursor: data.mixCursor.present ? data.mixCursor.value : this.mixCursor,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayerStateRow(')
          ..write('id: $id, ')
          ..write('currentPosition: $currentPosition, ')
          ..write('positionMs: $positionMs, ')
          ..write('loopMode: $loopMode, ')
          ..write('shuffleEnabled: $shuffleEnabled, ')
          ..write('volume: $volume, ')
          ..write('muted: $muted, ')
          ..write('mode: $mode, ')
          ..write('mixPluginId: $mixPluginId, ')
          ..write('mixId: $mixId, ')
          ..write('mixTitle: $mixTitle, ')
          ..write('mixCursor: $mixCursor, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    currentPosition,
    positionMs,
    loopMode,
    shuffleEnabled,
    volume,
    muted,
    mode,
    mixPluginId,
    mixId,
    mixTitle,
    mixCursor,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayerStateRow &&
          other.id == this.id &&
          other.currentPosition == this.currentPosition &&
          other.positionMs == this.positionMs &&
          other.loopMode == this.loopMode &&
          other.shuffleEnabled == this.shuffleEnabled &&
          other.volume == this.volume &&
          other.muted == this.muted &&
          other.mode == this.mode &&
          other.mixPluginId == this.mixPluginId &&
          other.mixId == this.mixId &&
          other.mixTitle == this.mixTitle &&
          other.mixCursor == this.mixCursor &&
          other.updatedAt == this.updatedAt);
}

class PlayerStateTableCompanion extends UpdateCompanion<PlayerStateRow> {
  final Value<int> id;
  final Value<int?> currentPosition;
  final Value<int> positionMs;
  final Value<LoopMode> loopMode;
  final Value<bool> shuffleEnabled;
  final Value<double> volume;
  final Value<bool> muted;
  final Value<PlayerMode?> mode;
  final Value<String?> mixPluginId;
  final Value<String?> mixId;
  final Value<String?> mixTitle;
  final Value<String?> mixCursor;
  final Value<DateTime> updatedAt;
  const PlayerStateTableCompanion({
    this.id = const Value.absent(),
    this.currentPosition = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.loopMode = const Value.absent(),
    this.shuffleEnabled = const Value.absent(),
    this.volume = const Value.absent(),
    this.muted = const Value.absent(),
    this.mode = const Value.absent(),
    this.mixPluginId = const Value.absent(),
    this.mixId = const Value.absent(),
    this.mixTitle = const Value.absent(),
    this.mixCursor = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PlayerStateTableCompanion.insert({
    this.id = const Value.absent(),
    this.currentPosition = const Value.absent(),
    required int positionMs,
    required LoopMode loopMode,
    required bool shuffleEnabled,
    required double volume,
    required bool muted,
    this.mode = const Value.absent(),
    this.mixPluginId = const Value.absent(),
    this.mixId = const Value.absent(),
    this.mixTitle = const Value.absent(),
    this.mixCursor = const Value.absent(),
    required DateTime updatedAt,
  }) : positionMs = Value(positionMs),
       loopMode = Value(loopMode),
       shuffleEnabled = Value(shuffleEnabled),
       volume = Value(volume),
       muted = Value(muted),
       updatedAt = Value(updatedAt);
  static Insertable<PlayerStateRow> custom({
    Expression<int>? id,
    Expression<int>? currentPosition,
    Expression<int>? positionMs,
    Expression<String>? loopMode,
    Expression<bool>? shuffleEnabled,
    Expression<double>? volume,
    Expression<bool>? muted,
    Expression<String>? mode,
    Expression<String>? mixPluginId,
    Expression<String>? mixId,
    Expression<String>? mixTitle,
    Expression<String>? mixCursor,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currentPosition != null) 'current_position': currentPosition,
      if (positionMs != null) 'position_ms': positionMs,
      if (loopMode != null) 'loop_mode': loopMode,
      if (shuffleEnabled != null) 'shuffle_enabled': shuffleEnabled,
      if (volume != null) 'volume': volume,
      if (muted != null) 'muted': muted,
      if (mode != null) 'mode': mode,
      if (mixPluginId != null) 'mix_plugin_id': mixPluginId,
      if (mixId != null) 'mix_id': mixId,
      if (mixTitle != null) 'mix_title': mixTitle,
      if (mixCursor != null) 'mix_cursor': mixCursor,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PlayerStateTableCompanion copyWith({
    Value<int>? id,
    Value<int?>? currentPosition,
    Value<int>? positionMs,
    Value<LoopMode>? loopMode,
    Value<bool>? shuffleEnabled,
    Value<double>? volume,
    Value<bool>? muted,
    Value<PlayerMode?>? mode,
    Value<String?>? mixPluginId,
    Value<String?>? mixId,
    Value<String?>? mixTitle,
    Value<String?>? mixCursor,
    Value<DateTime>? updatedAt,
  }) {
    return PlayerStateTableCompanion(
      id: id ?? this.id,
      currentPosition: currentPosition ?? this.currentPosition,
      positionMs: positionMs ?? this.positionMs,
      loopMode: loopMode ?? this.loopMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      mode: mode ?? this.mode,
      mixPluginId: mixPluginId ?? this.mixPluginId,
      mixId: mixId ?? this.mixId,
      mixTitle: mixTitle ?? this.mixTitle,
      mixCursor: mixCursor ?? this.mixCursor,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (currentPosition.present) {
      map['current_position'] = Variable<int>(currentPosition.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (loopMode.present) {
      map['loop_mode'] = Variable<String>(
        $PlayerStateTableTable.$converterloopMode.toSql(loopMode.value),
      );
    }
    if (shuffleEnabled.present) {
      map['shuffle_enabled'] = Variable<bool>(shuffleEnabled.value);
    }
    if (volume.present) {
      map['volume'] = Variable<double>(volume.value);
    }
    if (muted.present) {
      map['muted'] = Variable<bool>(muted.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $PlayerStateTableTable.$convertermoden.toSql(mode.value),
      );
    }
    if (mixPluginId.present) {
      map['mix_plugin_id'] = Variable<String>(mixPluginId.value);
    }
    if (mixId.present) {
      map['mix_id'] = Variable<String>(mixId.value);
    }
    if (mixTitle.present) {
      map['mix_title'] = Variable<String>(mixTitle.value);
    }
    if (mixCursor.present) {
      map['mix_cursor'] = Variable<String>(mixCursor.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $PlayerStateTableTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayerStateTableCompanion(')
          ..write('id: $id, ')
          ..write('currentPosition: $currentPosition, ')
          ..write('positionMs: $positionMs, ')
          ..write('loopMode: $loopMode, ')
          ..write('shuffleEnabled: $shuffleEnabled, ')
          ..write('volume: $volume, ')
          ..write('muted: $muted, ')
          ..write('mode: $mode, ')
          ..write('mixPluginId: $mixPluginId, ')
          ..write('mixId: $mixId, ')
          ..write('mixTitle: $mixTitle, ')
          ..write('mixCursor: $mixCursor, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PlayHistoryTableTable extends PlayHistoryTable
    with TableInfo<$PlayHistoryTableTable, PlayHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayHistoryTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (track_key) ON DELETE RESTRICT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> playedAt =
      GeneratedColumn<int>(
        'played_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PlayHistoryTableTable.$converterplayedAt);
  @override
  List<GeneratedColumn> get $columns => [id, trackKey, playedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlayHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      playedAt: $PlayHistoryTableTable.$converterplayedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}played_at'],
        )!,
      ),
    );
  }

  @override
  $PlayHistoryTableTable createAlias(String alias) {
    return $PlayHistoryTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterplayedAt =
      const EpochMillisecondsConverter();
}

class PlayHistoryRow extends DataClass implements Insertable<PlayHistoryRow> {
  final int id;
  final String trackKey;
  final DateTime playedAt;
  const PlayHistoryRow({
    required this.id,
    required this.trackKey,
    required this.playedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_key'] = Variable<String>(trackKey);
    {
      map['played_at'] = Variable<int>(
        $PlayHistoryTableTable.$converterplayedAt.toSql(playedAt),
      );
    }
    return map;
  }

  PlayHistoryTableCompanion toCompanion(bool nullToAbsent) {
    return PlayHistoryTableCompanion(
      id: Value(id),
      trackKey: Value(trackKey),
      playedAt: Value(playedAt),
    );
  }

  factory PlayHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayHistoryRow(
      id: serializer.fromJson<int>(json['id']),
      trackKey: serializer.fromJson<String>(json['trackKey']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackKey': serializer.toJson<String>(trackKey),
      'playedAt': serializer.toJson<DateTime>(playedAt),
    };
  }

  PlayHistoryRow copyWith({int? id, String? trackKey, DateTime? playedAt}) =>
      PlayHistoryRow(
        id: id ?? this.id,
        trackKey: trackKey ?? this.trackKey,
        playedAt: playedAt ?? this.playedAt,
      );
  PlayHistoryRow copyWithCompanion(PlayHistoryTableCompanion data) {
    return PlayHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryRow(')
          ..write('id: $id, ')
          ..write('trackKey: $trackKey, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, trackKey, playedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayHistoryRow &&
          other.id == this.id &&
          other.trackKey == this.trackKey &&
          other.playedAt == this.playedAt);
}

class PlayHistoryTableCompanion extends UpdateCompanion<PlayHistoryRow> {
  final Value<int> id;
  final Value<String> trackKey;
  final Value<DateTime> playedAt;
  const PlayHistoryTableCompanion({
    this.id = const Value.absent(),
    this.trackKey = const Value.absent(),
    this.playedAt = const Value.absent(),
  });
  PlayHistoryTableCompanion.insert({
    this.id = const Value.absent(),
    required String trackKey,
    required DateTime playedAt,
  }) : trackKey = Value(trackKey),
       playedAt = Value(playedAt);
  static Insertable<PlayHistoryRow> custom({
    Expression<int>? id,
    Expression<String>? trackKey,
    Expression<int>? playedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackKey != null) 'track_key': trackKey,
      if (playedAt != null) 'played_at': playedAt,
    });
  }

  PlayHistoryTableCompanion copyWith({
    Value<int>? id,
    Value<String>? trackKey,
    Value<DateTime>? playedAt,
  }) {
    return PlayHistoryTableCompanion(
      id: id ?? this.id,
      trackKey: trackKey ?? this.trackKey,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<int>(
        $PlayHistoryTableTable.$converterplayedAt.toSql(playedAt.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayHistoryTableCompanion(')
          ..write('id: $id, ')
          ..write('trackKey: $trackKey, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }
}

class $LayoutStateTableTable extends LayoutStateTable
    with TableInfo<$LayoutStateTableTable, LayoutStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LayoutStateTableTable(this.attachedDatabase, [this._alias]);
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
  late final GeneratedColumnWithTypeConverter<PlayerTab?, String> playerTab =
      GeneratedColumn<String>(
        'player_tab',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<PlayerTab?>($LayoutStateTableTable.$converterplayerTabn);
  static const VerificationMeta _panelExpandedMeta = const VerificationMeta(
    'panelExpanded',
  );
  @override
  late final GeneratedColumn<bool> panelExpanded = GeneratedColumn<bool>(
    'panel_expanded',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("panel_expanded" IN (0, 1))',
    ),
  );
  static const VerificationMeta _panelWidthMeta = const VerificationMeta(
    'panelWidth',
  );
  @override
  late final GeneratedColumn<double> panelWidth = GeneratedColumn<double>(
    'panel_width',
    aliasedName,
    true,
    check: () => ComparableExpr(panelWidth).isSmallerOrEqualValue(1600),
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playerTab,
    panelExpanded,
    panelWidth,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'layout_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<LayoutStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('panel_expanded')) {
      context.handle(
        _panelExpandedMeta,
        panelExpanded.isAcceptableOrUnknown(
          data['panel_expanded']!,
          _panelExpandedMeta,
        ),
      );
    }
    if (data.containsKey('panel_width')) {
      context.handle(
        _panelWidthMeta,
        panelWidth.isAcceptableOrUnknown(data['panel_width']!, _panelWidthMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LayoutStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LayoutStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      playerTab: $LayoutStateTableTable.$converterplayerTabn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}player_tab'],
        ),
      ),
      panelExpanded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}panel_expanded'],
      ),
      panelWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}panel_width'],
      ),
    );
  }

  @override
  $LayoutStateTableTable createAlias(String alias) {
    return $LayoutStateTableTable(attachedDatabase, alias);
  }

  static TypeConverter<PlayerTab, String> $converterplayerTab =
      const PlayerTabConverter();
  static TypeConverter<PlayerTab?, String?> $converterplayerTabn =
      NullAwareTypeConverter.wrap($converterplayerTab);
}

class LayoutStateRow extends DataClass implements Insertable<LayoutStateRow> {
  /// 固定為 1；CHECK 讓第二列插不進去。
  final int id;

  /// 播放頁右欄上次選的分頁。
  final PlayerTab? playerTab;

  /// 右側「正在播放」面板展開與否。
  final bool? panelExpanded;

  /// 右側面板的寬度（dp）。資料庫只擋明顯的壞值，實際範圍在讀取時依視窗夾取。
  final double? panelWidth;
  const LayoutStateRow({
    required this.id,
    this.playerTab,
    this.panelExpanded,
    this.panelWidth,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || playerTab != null) {
      map['player_tab'] = Variable<String>(
        $LayoutStateTableTable.$converterplayerTabn.toSql(playerTab),
      );
    }
    if (!nullToAbsent || panelExpanded != null) {
      map['panel_expanded'] = Variable<bool>(panelExpanded);
    }
    if (!nullToAbsent || panelWidth != null) {
      map['panel_width'] = Variable<double>(panelWidth);
    }
    return map;
  }

  LayoutStateTableCompanion toCompanion(bool nullToAbsent) {
    return LayoutStateTableCompanion(
      id: Value(id),
      playerTab: playerTab == null && nullToAbsent
          ? const Value.absent()
          : Value(playerTab),
      panelExpanded: panelExpanded == null && nullToAbsent
          ? const Value.absent()
          : Value(panelExpanded),
      panelWidth: panelWidth == null && nullToAbsent
          ? const Value.absent()
          : Value(panelWidth),
    );
  }

  factory LayoutStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LayoutStateRow(
      id: serializer.fromJson<int>(json['id']),
      playerTab: serializer.fromJson<PlayerTab?>(json['playerTab']),
      panelExpanded: serializer.fromJson<bool?>(json['panelExpanded']),
      panelWidth: serializer.fromJson<double?>(json['panelWidth']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playerTab': serializer.toJson<PlayerTab?>(playerTab),
      'panelExpanded': serializer.toJson<bool?>(panelExpanded),
      'panelWidth': serializer.toJson<double?>(panelWidth),
    };
  }

  LayoutStateRow copyWith({
    int? id,
    Value<PlayerTab?> playerTab = const Value.absent(),
    Value<bool?> panelExpanded = const Value.absent(),
    Value<double?> panelWidth = const Value.absent(),
  }) => LayoutStateRow(
    id: id ?? this.id,
    playerTab: playerTab.present ? playerTab.value : this.playerTab,
    panelExpanded: panelExpanded.present
        ? panelExpanded.value
        : this.panelExpanded,
    panelWidth: panelWidth.present ? panelWidth.value : this.panelWidth,
  );
  LayoutStateRow copyWithCompanion(LayoutStateTableCompanion data) {
    return LayoutStateRow(
      id: data.id.present ? data.id.value : this.id,
      playerTab: data.playerTab.present ? data.playerTab.value : this.playerTab,
      panelExpanded: data.panelExpanded.present
          ? data.panelExpanded.value
          : this.panelExpanded,
      panelWidth: data.panelWidth.present
          ? data.panelWidth.value
          : this.panelWidth,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LayoutStateRow(')
          ..write('id: $id, ')
          ..write('playerTab: $playerTab, ')
          ..write('panelExpanded: $panelExpanded, ')
          ..write('panelWidth: $panelWidth')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playerTab, panelExpanded, panelWidth);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LayoutStateRow &&
          other.id == this.id &&
          other.playerTab == this.playerTab &&
          other.panelExpanded == this.panelExpanded &&
          other.panelWidth == this.panelWidth);
}

class LayoutStateTableCompanion extends UpdateCompanion<LayoutStateRow> {
  final Value<int> id;
  final Value<PlayerTab?> playerTab;
  final Value<bool?> panelExpanded;
  final Value<double?> panelWidth;
  const LayoutStateTableCompanion({
    this.id = const Value.absent(),
    this.playerTab = const Value.absent(),
    this.panelExpanded = const Value.absent(),
    this.panelWidth = const Value.absent(),
  });
  LayoutStateTableCompanion.insert({
    this.id = const Value.absent(),
    this.playerTab = const Value.absent(),
    this.panelExpanded = const Value.absent(),
    this.panelWidth = const Value.absent(),
  });
  static Insertable<LayoutStateRow> custom({
    Expression<int>? id,
    Expression<String>? playerTab,
    Expression<bool>? panelExpanded,
    Expression<double>? panelWidth,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playerTab != null) 'player_tab': playerTab,
      if (panelExpanded != null) 'panel_expanded': panelExpanded,
      if (panelWidth != null) 'panel_width': panelWidth,
    });
  }

  LayoutStateTableCompanion copyWith({
    Value<int>? id,
    Value<PlayerTab?>? playerTab,
    Value<bool?>? panelExpanded,
    Value<double?>? panelWidth,
  }) {
    return LayoutStateTableCompanion(
      id: id ?? this.id,
      playerTab: playerTab ?? this.playerTab,
      panelExpanded: panelExpanded ?? this.panelExpanded,
      panelWidth: panelWidth ?? this.panelWidth,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playerTab.present) {
      map['player_tab'] = Variable<String>(
        $LayoutStateTableTable.$converterplayerTabn.toSql(playerTab.value),
      );
    }
    if (panelExpanded.present) {
      map['panel_expanded'] = Variable<bool>(panelExpanded.value);
    }
    if (panelWidth.present) {
      map['panel_width'] = Variable<double>(panelWidth.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LayoutStateTableCompanion(')
          ..write('id: $id, ')
          ..write('playerTab: $playerTab, ')
          ..write('panelExpanded: $panelExpanded, ')
          ..write('panelWidth: $panelWidth')
          ..write(')'))
        .toString();
  }
}

class $AccountsTableTable extends AccountsTable
    with TableInfo<$AccountsTableTable, AccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTableTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarJsonMeta = const VerificationMeta(
    'avatarJson',
  );
  @override
  late final GeneratedColumn<String> avatarJson = GeneratedColumn<String>(
    'avatar_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AccountStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AccountStatus>($AccountsTableTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> loggedInAt =
      GeneratedColumn<int>(
        'logged_in_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($AccountsTableTable.$converterloggedInAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastRefreshAt =
      GeneratedColumn<int>(
        'last_refresh_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>($AccountsTableTable.$converterlastRefreshAtn);
  @override
  late final GeneratedColumnWithTypeConverter<RefreshResult?, String>
  lastRefreshResult =
      GeneratedColumn<String>(
        'last_refresh_result',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<RefreshResult?>(
        $AccountsTableTable.$converterlastRefreshResultn,
      );
  @override
  List<GeneratedColumn> get $columns => [
    pluginId,
    userId,
    displayName,
    avatarJson,
    status,
    loggedInAt,
    lastRefreshAt,
    lastRefreshResult,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<AccountRow> instance, {
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
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_json')) {
      context.handle(
        _avatarJsonMeta,
        avatarJson.isAcceptableOrUnknown(data['avatar_json']!, _avatarJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pluginId};
  @override
  AccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountRow(
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      avatarJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_json'],
      ),
      status: $AccountsTableTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      loggedInAt: $AccountsTableTable.$converterloggedInAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}logged_in_at'],
        )!,
      ),
      lastRefreshAt: $AccountsTableTable.$converterlastRefreshAtn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_refresh_at'],
        ),
      ),
      lastRefreshResult: $AccountsTableTable.$converterlastRefreshResultn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.string,
              data['${effectivePrefix}last_refresh_result'],
            ),
          ),
    );
  }

  @override
  $AccountsTableTable createAlias(String alias) {
    return $AccountsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<AccountStatus, String> $converterstatus =
      const AccountStatusConverter();
  static TypeConverter<DateTime, int> $converterloggedInAt =
      const EpochMillisecondsConverter();
  static TypeConverter<DateTime, int> $converterlastRefreshAt =
      const EpochMillisecondsConverter();
  static TypeConverter<DateTime?, int?> $converterlastRefreshAtn =
      NullAwareTypeConverter.wrap($converterlastRefreshAt);
  static TypeConverter<RefreshResult, String> $converterlastRefreshResult =
      const RefreshResultConverter();
  static TypeConverter<RefreshResult?, String?> $converterlastRefreshResultn =
      NullAwareTypeConverter.wrap($converterlastRefreshResult);
}

class AccountRow extends DataClass implements Insertable<AccountRow> {
  final String pluginId;
  final String userId;
  final String displayName;

  /// `Artwork[]` 的 JSON；沒有頭像為空。
  final String? avatarJson;
  final AccountStatus status;
  final DateTime loggedInAt;
  final DateTime? lastRefreshAt;
  final RefreshResult? lastRefreshResult;
  const AccountRow({
    required this.pluginId,
    required this.userId,
    required this.displayName,
    this.avatarJson,
    required this.status,
    required this.loggedInAt,
    this.lastRefreshAt,
    this.lastRefreshResult,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['plugin_id'] = Variable<String>(pluginId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarJson != null) {
      map['avatar_json'] = Variable<String>(avatarJson);
    }
    {
      map['status'] = Variable<String>(
        $AccountsTableTable.$converterstatus.toSql(status),
      );
    }
    {
      map['logged_in_at'] = Variable<int>(
        $AccountsTableTable.$converterloggedInAt.toSql(loggedInAt),
      );
    }
    if (!nullToAbsent || lastRefreshAt != null) {
      map['last_refresh_at'] = Variable<int>(
        $AccountsTableTable.$converterlastRefreshAtn.toSql(lastRefreshAt),
      );
    }
    if (!nullToAbsent || lastRefreshResult != null) {
      map['last_refresh_result'] = Variable<String>(
        $AccountsTableTable.$converterlastRefreshResultn.toSql(
          lastRefreshResult,
        ),
      );
    }
    return map;
  }

  AccountsTableCompanion toCompanion(bool nullToAbsent) {
    return AccountsTableCompanion(
      pluginId: Value(pluginId),
      userId: Value(userId),
      displayName: Value(displayName),
      avatarJson: avatarJson == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarJson),
      status: Value(status),
      loggedInAt: Value(loggedInAt),
      lastRefreshAt: lastRefreshAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRefreshAt),
      lastRefreshResult: lastRefreshResult == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRefreshResult),
    );
  }

  factory AccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountRow(
      pluginId: serializer.fromJson<String>(json['pluginId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarJson: serializer.fromJson<String?>(json['avatarJson']),
      status: serializer.fromJson<AccountStatus>(json['status']),
      loggedInAt: serializer.fromJson<DateTime>(json['loggedInAt']),
      lastRefreshAt: serializer.fromJson<DateTime?>(json['lastRefreshAt']),
      lastRefreshResult: serializer.fromJson<RefreshResult?>(
        json['lastRefreshResult'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pluginId': serializer.toJson<String>(pluginId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'avatarJson': serializer.toJson<String?>(avatarJson),
      'status': serializer.toJson<AccountStatus>(status),
      'loggedInAt': serializer.toJson<DateTime>(loggedInAt),
      'lastRefreshAt': serializer.toJson<DateTime?>(lastRefreshAt),
      'lastRefreshResult': serializer.toJson<RefreshResult?>(lastRefreshResult),
    };
  }

  AccountRow copyWith({
    String? pluginId,
    String? userId,
    String? displayName,
    Value<String?> avatarJson = const Value.absent(),
    AccountStatus? status,
    DateTime? loggedInAt,
    Value<DateTime?> lastRefreshAt = const Value.absent(),
    Value<RefreshResult?> lastRefreshResult = const Value.absent(),
  }) => AccountRow(
    pluginId: pluginId ?? this.pluginId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    avatarJson: avatarJson.present ? avatarJson.value : this.avatarJson,
    status: status ?? this.status,
    loggedInAt: loggedInAt ?? this.loggedInAt,
    lastRefreshAt: lastRefreshAt.present
        ? lastRefreshAt.value
        : this.lastRefreshAt,
    lastRefreshResult: lastRefreshResult.present
        ? lastRefreshResult.value
        : this.lastRefreshResult,
  );
  AccountRow copyWithCompanion(AccountsTableCompanion data) {
    return AccountRow(
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarJson: data.avatarJson.present
          ? data.avatarJson.value
          : this.avatarJson,
      status: data.status.present ? data.status.value : this.status,
      loggedInAt: data.loggedInAt.present
          ? data.loggedInAt.value
          : this.loggedInAt,
      lastRefreshAt: data.lastRefreshAt.present
          ? data.lastRefreshAt.value
          : this.lastRefreshAt,
      lastRefreshResult: data.lastRefreshResult.present
          ? data.lastRefreshResult.value
          : this.lastRefreshResult,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountRow(')
          ..write('pluginId: $pluginId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('avatarJson: $avatarJson, ')
          ..write('status: $status, ')
          ..write('loggedInAt: $loggedInAt, ')
          ..write('lastRefreshAt: $lastRefreshAt, ')
          ..write('lastRefreshResult: $lastRefreshResult')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pluginId,
    userId,
    displayName,
    avatarJson,
    status,
    loggedInAt,
    lastRefreshAt,
    lastRefreshResult,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountRow &&
          other.pluginId == this.pluginId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.avatarJson == this.avatarJson &&
          other.status == this.status &&
          other.loggedInAt == this.loggedInAt &&
          other.lastRefreshAt == this.lastRefreshAt &&
          other.lastRefreshResult == this.lastRefreshResult);
}

class AccountsTableCompanion extends UpdateCompanion<AccountRow> {
  final Value<String> pluginId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<String?> avatarJson;
  final Value<AccountStatus> status;
  final Value<DateTime> loggedInAt;
  final Value<DateTime?> lastRefreshAt;
  final Value<RefreshResult?> lastRefreshResult;
  final Value<int> rowid;
  const AccountsTableCompanion({
    this.pluginId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarJson = const Value.absent(),
    this.status = const Value.absent(),
    this.loggedInAt = const Value.absent(),
    this.lastRefreshAt = const Value.absent(),
    this.lastRefreshResult = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsTableCompanion.insert({
    required String pluginId,
    required String userId,
    required String displayName,
    this.avatarJson = const Value.absent(),
    required AccountStatus status,
    required DateTime loggedInAt,
    this.lastRefreshAt = const Value.absent(),
    this.lastRefreshResult = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pluginId = Value(pluginId),
       userId = Value(userId),
       displayName = Value(displayName),
       status = Value(status),
       loggedInAt = Value(loggedInAt);
  static Insertable<AccountRow> custom({
    Expression<String>? pluginId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? avatarJson,
    Expression<String>? status,
    Expression<int>? loggedInAt,
    Expression<int>? lastRefreshAt,
    Expression<String>? lastRefreshResult,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pluginId != null) 'plugin_id': pluginId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (avatarJson != null) 'avatar_json': avatarJson,
      if (status != null) 'status': status,
      if (loggedInAt != null) 'logged_in_at': loggedInAt,
      if (lastRefreshAt != null) 'last_refresh_at': lastRefreshAt,
      if (lastRefreshResult != null) 'last_refresh_result': lastRefreshResult,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsTableCompanion copyWith({
    Value<String>? pluginId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<String?>? avatarJson,
    Value<AccountStatus>? status,
    Value<DateTime>? loggedInAt,
    Value<DateTime?>? lastRefreshAt,
    Value<RefreshResult?>? lastRefreshResult,
    Value<int>? rowid,
  }) {
    return AccountsTableCompanion(
      pluginId: pluginId ?? this.pluginId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarJson: avatarJson ?? this.avatarJson,
      status: status ?? this.status,
      loggedInAt: loggedInAt ?? this.loggedInAt,
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
      lastRefreshResult: lastRefreshResult ?? this.lastRefreshResult,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarJson.present) {
      map['avatar_json'] = Variable<String>(avatarJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $AccountsTableTable.$converterstatus.toSql(status.value),
      );
    }
    if (loggedInAt.present) {
      map['logged_in_at'] = Variable<int>(
        $AccountsTableTable.$converterloggedInAt.toSql(loggedInAt.value),
      );
    }
    if (lastRefreshAt.present) {
      map['last_refresh_at'] = Variable<int>(
        $AccountsTableTable.$converterlastRefreshAtn.toSql(lastRefreshAt.value),
      );
    }
    if (lastRefreshResult.present) {
      map['last_refresh_result'] = Variable<String>(
        $AccountsTableTable.$converterlastRefreshResultn.toSql(
          lastRefreshResult.value,
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
    return (StringBuffer('AccountsTableCompanion(')
          ..write('pluginId: $pluginId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('avatarJson: $avatarJson, ')
          ..write('status: $status, ')
          ..write('loggedInAt: $loggedInAt, ')
          ..write('lastRefreshAt: $lastRefreshAt, ')
          ..write('lastRefreshResult: $lastRefreshResult, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourceSettingsTableTable extends SourceSettingsTable
    with TableInfo<$SourceSettingsTableTable, SourceSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceSettingsTableTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _browseAsLoggedInMeta = const VerificationMeta(
    'browseAsLoggedIn',
  );
  @override
  late final GeneratedColumn<bool> browseAsLoggedIn = GeneratedColumn<bool>(
    'browse_as_logged_in',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("browse_as_logged_in" IN (0, 1))',
    ),
  );
  static const VerificationMeta _matchTargetMeta = const VerificationMeta(
    'matchTarget',
  );
  @override
  late final GeneratedColumn<bool> matchTarget = GeneratedColumn<bool>(
    'match_target',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("match_target" IN (0, 1))',
    ),
  );
  static const VerificationMeta _matchRankMeta = const VerificationMeta(
    'matchRank',
  );
  @override
  late final GeneratedColumn<int> matchRank = GeneratedColumn<int>(
    'match_rank',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pluginId,
    browseAsLoggedIn,
    matchTarget,
    matchRank,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceSettingsRow> instance, {
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
    if (data.containsKey('browse_as_logged_in')) {
      context.handle(
        _browseAsLoggedInMeta,
        browseAsLoggedIn.isAcceptableOrUnknown(
          data['browse_as_logged_in']!,
          _browseAsLoggedInMeta,
        ),
      );
    }
    if (data.containsKey('match_target')) {
      context.handle(
        _matchTargetMeta,
        matchTarget.isAcceptableOrUnknown(
          data['match_target']!,
          _matchTargetMeta,
        ),
      );
    }
    if (data.containsKey('match_rank')) {
      context.handle(
        _matchRankMeta,
        matchRank.isAcceptableOrUnknown(data['match_rank']!, _matchRankMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pluginId};
  @override
  SourceSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceSettingsRow(
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      )!,
      browseAsLoggedIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}browse_as_logged_in'],
      ),
      matchTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}match_target'],
      ),
      matchRank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}match_rank'],
      ),
    );
  }

  @override
  $SourceSettingsTableTable createAlias(String alias) {
    return $SourceSettingsTableTable(attachedDatabase, alias);
  }
}

class SourceSettingsRow extends DataClass
    implements Insertable<SourceSettingsRow> {
  final String pluginId;

  /// 「以登入身分瀏覽與播放」（ADR 0012 §決定 6）。
  final bool? browseAsLoggedIn;

  /// 外部匯入的匹配目標（M4 design §8.3）：空＝依預設（已啟用、同時有 `search` 與
  /// `resolveStream` 的都是目標），`false`＝使用者取消勾選。
  final bool? matchTarget;

  /// 匹配目標的順序，由小到大；空的排在後面、依插件清單（ADR 0014 §決定 9）。
  final int? matchRank;
  const SourceSettingsRow({
    required this.pluginId,
    this.browseAsLoggedIn,
    this.matchTarget,
    this.matchRank,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['plugin_id'] = Variable<String>(pluginId);
    if (!nullToAbsent || browseAsLoggedIn != null) {
      map['browse_as_logged_in'] = Variable<bool>(browseAsLoggedIn);
    }
    if (!nullToAbsent || matchTarget != null) {
      map['match_target'] = Variable<bool>(matchTarget);
    }
    if (!nullToAbsent || matchRank != null) {
      map['match_rank'] = Variable<int>(matchRank);
    }
    return map;
  }

  SourceSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return SourceSettingsTableCompanion(
      pluginId: Value(pluginId),
      browseAsLoggedIn: browseAsLoggedIn == null && nullToAbsent
          ? const Value.absent()
          : Value(browseAsLoggedIn),
      matchTarget: matchTarget == null && nullToAbsent
          ? const Value.absent()
          : Value(matchTarget),
      matchRank: matchRank == null && nullToAbsent
          ? const Value.absent()
          : Value(matchRank),
    );
  }

  factory SourceSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceSettingsRow(
      pluginId: serializer.fromJson<String>(json['pluginId']),
      browseAsLoggedIn: serializer.fromJson<bool?>(json['browseAsLoggedIn']),
      matchTarget: serializer.fromJson<bool?>(json['matchTarget']),
      matchRank: serializer.fromJson<int?>(json['matchRank']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pluginId': serializer.toJson<String>(pluginId),
      'browseAsLoggedIn': serializer.toJson<bool?>(browseAsLoggedIn),
      'matchTarget': serializer.toJson<bool?>(matchTarget),
      'matchRank': serializer.toJson<int?>(matchRank),
    };
  }

  SourceSettingsRow copyWith({
    String? pluginId,
    Value<bool?> browseAsLoggedIn = const Value.absent(),
    Value<bool?> matchTarget = const Value.absent(),
    Value<int?> matchRank = const Value.absent(),
  }) => SourceSettingsRow(
    pluginId: pluginId ?? this.pluginId,
    browseAsLoggedIn: browseAsLoggedIn.present
        ? browseAsLoggedIn.value
        : this.browseAsLoggedIn,
    matchTarget: matchTarget.present ? matchTarget.value : this.matchTarget,
    matchRank: matchRank.present ? matchRank.value : this.matchRank,
  );
  SourceSettingsRow copyWithCompanion(SourceSettingsTableCompanion data) {
    return SourceSettingsRow(
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      browseAsLoggedIn: data.browseAsLoggedIn.present
          ? data.browseAsLoggedIn.value
          : this.browseAsLoggedIn,
      matchTarget: data.matchTarget.present
          ? data.matchTarget.value
          : this.matchTarget,
      matchRank: data.matchRank.present ? data.matchRank.value : this.matchRank,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceSettingsRow(')
          ..write('pluginId: $pluginId, ')
          ..write('browseAsLoggedIn: $browseAsLoggedIn, ')
          ..write('matchTarget: $matchTarget, ')
          ..write('matchRank: $matchRank')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(pluginId, browseAsLoggedIn, matchTarget, matchRank);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceSettingsRow &&
          other.pluginId == this.pluginId &&
          other.browseAsLoggedIn == this.browseAsLoggedIn &&
          other.matchTarget == this.matchTarget &&
          other.matchRank == this.matchRank);
}

class SourceSettingsTableCompanion extends UpdateCompanion<SourceSettingsRow> {
  final Value<String> pluginId;
  final Value<bool?> browseAsLoggedIn;
  final Value<bool?> matchTarget;
  final Value<int?> matchRank;
  final Value<int> rowid;
  const SourceSettingsTableCompanion({
    this.pluginId = const Value.absent(),
    this.browseAsLoggedIn = const Value.absent(),
    this.matchTarget = const Value.absent(),
    this.matchRank = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceSettingsTableCompanion.insert({
    required String pluginId,
    this.browseAsLoggedIn = const Value.absent(),
    this.matchTarget = const Value.absent(),
    this.matchRank = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pluginId = Value(pluginId);
  static Insertable<SourceSettingsRow> custom({
    Expression<String>? pluginId,
    Expression<bool>? browseAsLoggedIn,
    Expression<bool>? matchTarget,
    Expression<int>? matchRank,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pluginId != null) 'plugin_id': pluginId,
      if (browseAsLoggedIn != null) 'browse_as_logged_in': browseAsLoggedIn,
      if (matchTarget != null) 'match_target': matchTarget,
      if (matchRank != null) 'match_rank': matchRank,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceSettingsTableCompanion copyWith({
    Value<String>? pluginId,
    Value<bool?>? browseAsLoggedIn,
    Value<bool?>? matchTarget,
    Value<int?>? matchRank,
    Value<int>? rowid,
  }) {
    return SourceSettingsTableCompanion(
      pluginId: pluginId ?? this.pluginId,
      browseAsLoggedIn: browseAsLoggedIn ?? this.browseAsLoggedIn,
      matchTarget: matchTarget ?? this.matchTarget,
      matchRank: matchRank ?? this.matchRank,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (browseAsLoggedIn.present) {
      map['browse_as_logged_in'] = Variable<bool>(browseAsLoggedIn.value);
    }
    if (matchTarget.present) {
      map['match_target'] = Variable<bool>(matchTarget.value);
    }
    if (matchRank.present) {
      map['match_rank'] = Variable<int>(matchRank.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceSettingsTableCompanion(')
          ..write('pluginId: $pluginId, ')
          ..write('browseAsLoggedIn: $browseAsLoggedIn, ')
          ..write('matchTarget: $matchTarget, ')
          ..write('matchRank: $matchRank, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeveloperSettingsTableTable extends DeveloperSettingsTable
    with TableInfo<$DeveloperSettingsTableTable, DeveloperSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeveloperSettingsTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _developerModeMeta = const VerificationMeta(
    'developerMode',
  );
  @override
  late final GeneratedColumn<bool> developerMode = GeneratedColumn<bool>(
    'developer_mode',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("developer_mode" IN (0, 1))',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<LogLevelSetting?, String>
  logLevel =
      GeneratedColumn<String>(
        'log_level',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<LogLevelSetting?>(
        $DeveloperSettingsTableTable.$converterlogLeveln,
      );
  static const VerificationMeta _pluginDevFolderMeta = const VerificationMeta(
    'pluginDevFolder',
  );
  @override
  late final GeneratedColumn<String> pluginDevFolder = GeneratedColumn<String>(
    'plugin_dev_folder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reportReminderDismissedMeta =
      const VerificationMeta('reportReminderDismissed');
  @override
  late final GeneratedColumn<bool> reportReminderDismissed =
      GeneratedColumn<bool>(
        'report_reminder_dismissed',
        aliasedName,
        true,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("report_reminder_dismissed" IN (0, 1))',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    developerMode,
    logLevel,
    pluginDevFolder,
    reportReminderDismissed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'developer_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeveloperSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('developer_mode')) {
      context.handle(
        _developerModeMeta,
        developerMode.isAcceptableOrUnknown(
          data['developer_mode']!,
          _developerModeMeta,
        ),
      );
    }
    if (data.containsKey('plugin_dev_folder')) {
      context.handle(
        _pluginDevFolderMeta,
        pluginDevFolder.isAcceptableOrUnknown(
          data['plugin_dev_folder']!,
          _pluginDevFolderMeta,
        ),
      );
    }
    if (data.containsKey('report_reminder_dismissed')) {
      context.handle(
        _reportReminderDismissedMeta,
        reportReminderDismissed.isAcceptableOrUnknown(
          data['report_reminder_dismissed']!,
          _reportReminderDismissedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeveloperSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeveloperSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      developerMode: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}developer_mode'],
      ),
      logLevel: $DeveloperSettingsTableTable.$converterlogLeveln.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}log_level'],
        ),
      ),
      pluginDevFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_dev_folder'],
      ),
      reportReminderDismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}report_reminder_dismissed'],
      ),
    );
  }

  @override
  $DeveloperSettingsTableTable createAlias(String alias) {
    return $DeveloperSettingsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<LogLevelSetting, String> $converterlogLevel =
      const LogLevelSettingConverter();
  static TypeConverter<LogLevelSetting?, String?> $converterlogLeveln =
      NullAwareTypeConverter.wrap($converterlogLevel);
}

class DeveloperSettingsRow extends DataClass
    implements Insertable<DeveloperSettingsRow> {
  /// 固定為 1；CHECK 讓第二列插不進去。
  final int id;
  final bool? developerMode;
  final LogLevelSetting? logLevel;

  /// 插件開發資料夾的路徑（ADR 0025 §決定 7，M3 PR 16）。
  final String? pluginDevFolder;

  /// 「送出前請檢查」不再提醒（ADR 0023 §決定 4、ADR 0025 §決定 10，M3 PR 13）。
  final bool? reportReminderDismissed;
  const DeveloperSettingsRow({
    required this.id,
    this.developerMode,
    this.logLevel,
    this.pluginDevFolder,
    this.reportReminderDismissed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || developerMode != null) {
      map['developer_mode'] = Variable<bool>(developerMode);
    }
    if (!nullToAbsent || logLevel != null) {
      map['log_level'] = Variable<String>(
        $DeveloperSettingsTableTable.$converterlogLeveln.toSql(logLevel),
      );
    }
    if (!nullToAbsent || pluginDevFolder != null) {
      map['plugin_dev_folder'] = Variable<String>(pluginDevFolder);
    }
    if (!nullToAbsent || reportReminderDismissed != null) {
      map['report_reminder_dismissed'] = Variable<bool>(
        reportReminderDismissed,
      );
    }
    return map;
  }

  DeveloperSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return DeveloperSettingsTableCompanion(
      id: Value(id),
      developerMode: developerMode == null && nullToAbsent
          ? const Value.absent()
          : Value(developerMode),
      logLevel: logLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(logLevel),
      pluginDevFolder: pluginDevFolder == null && nullToAbsent
          ? const Value.absent()
          : Value(pluginDevFolder),
      reportReminderDismissed: reportReminderDismissed == null && nullToAbsent
          ? const Value.absent()
          : Value(reportReminderDismissed),
    );
  }

  factory DeveloperSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeveloperSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      developerMode: serializer.fromJson<bool?>(json['developerMode']),
      logLevel: serializer.fromJson<LogLevelSetting?>(json['logLevel']),
      pluginDevFolder: serializer.fromJson<String?>(json['pluginDevFolder']),
      reportReminderDismissed: serializer.fromJson<bool?>(
        json['reportReminderDismissed'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'developerMode': serializer.toJson<bool?>(developerMode),
      'logLevel': serializer.toJson<LogLevelSetting?>(logLevel),
      'pluginDevFolder': serializer.toJson<String?>(pluginDevFolder),
      'reportReminderDismissed': serializer.toJson<bool?>(
        reportReminderDismissed,
      ),
    };
  }

  DeveloperSettingsRow copyWith({
    int? id,
    Value<bool?> developerMode = const Value.absent(),
    Value<LogLevelSetting?> logLevel = const Value.absent(),
    Value<String?> pluginDevFolder = const Value.absent(),
    Value<bool?> reportReminderDismissed = const Value.absent(),
  }) => DeveloperSettingsRow(
    id: id ?? this.id,
    developerMode: developerMode.present
        ? developerMode.value
        : this.developerMode,
    logLevel: logLevel.present ? logLevel.value : this.logLevel,
    pluginDevFolder: pluginDevFolder.present
        ? pluginDevFolder.value
        : this.pluginDevFolder,
    reportReminderDismissed: reportReminderDismissed.present
        ? reportReminderDismissed.value
        : this.reportReminderDismissed,
  );
  DeveloperSettingsRow copyWithCompanion(DeveloperSettingsTableCompanion data) {
    return DeveloperSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      developerMode: data.developerMode.present
          ? data.developerMode.value
          : this.developerMode,
      logLevel: data.logLevel.present ? data.logLevel.value : this.logLevel,
      pluginDevFolder: data.pluginDevFolder.present
          ? data.pluginDevFolder.value
          : this.pluginDevFolder,
      reportReminderDismissed: data.reportReminderDismissed.present
          ? data.reportReminderDismissed.value
          : this.reportReminderDismissed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeveloperSettingsRow(')
          ..write('id: $id, ')
          ..write('developerMode: $developerMode, ')
          ..write('logLevel: $logLevel, ')
          ..write('pluginDevFolder: $pluginDevFolder, ')
          ..write('reportReminderDismissed: $reportReminderDismissed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    developerMode,
    logLevel,
    pluginDevFolder,
    reportReminderDismissed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeveloperSettingsRow &&
          other.id == this.id &&
          other.developerMode == this.developerMode &&
          other.logLevel == this.logLevel &&
          other.pluginDevFolder == this.pluginDevFolder &&
          other.reportReminderDismissed == this.reportReminderDismissed);
}

class DeveloperSettingsTableCompanion
    extends UpdateCompanion<DeveloperSettingsRow> {
  final Value<int> id;
  final Value<bool?> developerMode;
  final Value<LogLevelSetting?> logLevel;
  final Value<String?> pluginDevFolder;
  final Value<bool?> reportReminderDismissed;
  const DeveloperSettingsTableCompanion({
    this.id = const Value.absent(),
    this.developerMode = const Value.absent(),
    this.logLevel = const Value.absent(),
    this.pluginDevFolder = const Value.absent(),
    this.reportReminderDismissed = const Value.absent(),
  });
  DeveloperSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    this.developerMode = const Value.absent(),
    this.logLevel = const Value.absent(),
    this.pluginDevFolder = const Value.absent(),
    this.reportReminderDismissed = const Value.absent(),
  });
  static Insertable<DeveloperSettingsRow> custom({
    Expression<int>? id,
    Expression<bool>? developerMode,
    Expression<String>? logLevel,
    Expression<String>? pluginDevFolder,
    Expression<bool>? reportReminderDismissed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (developerMode != null) 'developer_mode': developerMode,
      if (logLevel != null) 'log_level': logLevel,
      if (pluginDevFolder != null) 'plugin_dev_folder': pluginDevFolder,
      if (reportReminderDismissed != null)
        'report_reminder_dismissed': reportReminderDismissed,
    });
  }

  DeveloperSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<bool?>? developerMode,
    Value<LogLevelSetting?>? logLevel,
    Value<String?>? pluginDevFolder,
    Value<bool?>? reportReminderDismissed,
  }) {
    return DeveloperSettingsTableCompanion(
      id: id ?? this.id,
      developerMode: developerMode ?? this.developerMode,
      logLevel: logLevel ?? this.logLevel,
      pluginDevFolder: pluginDevFolder ?? this.pluginDevFolder,
      reportReminderDismissed:
          reportReminderDismissed ?? this.reportReminderDismissed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (developerMode.present) {
      map['developer_mode'] = Variable<bool>(developerMode.value);
    }
    if (logLevel.present) {
      map['log_level'] = Variable<String>(
        $DeveloperSettingsTableTable.$converterlogLeveln.toSql(logLevel.value),
      );
    }
    if (pluginDevFolder.present) {
      map['plugin_dev_folder'] = Variable<String>(pluginDevFolder.value);
    }
    if (reportReminderDismissed.present) {
      map['report_reminder_dismissed'] = Variable<bool>(
        reportReminderDismissed.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeveloperSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('developerMode: $developerMode, ')
          ..write('logLevel: $logLevel, ')
          ..write('pluginDevFolder: $pluginDevFolder, ')
          ..write('reportReminderDismissed: $reportReminderDismissed')
          ..write(')'))
        .toString();
  }
}

class $SchedulerRunsTableTable extends SchedulerRunsTable
    with TableInfo<$SchedulerRunsTableTable, SchedulerRunRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchedulerRunsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> lastSuccessAt =
      GeneratedColumn<int>(
        'last_success_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>(
        $SchedulerRunsTableTable.$converterlastSuccessAt,
      );
  @override
  List<GeneratedColumn> get $columns => [jobId, lastSuccessAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheduler_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchedulerRunRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {jobId};
  @override
  SchedulerRunRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchedulerRunRow(
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      lastSuccessAt: $SchedulerRunsTableTable.$converterlastSuccessAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_success_at'],
        )!,
      ),
    );
  }

  @override
  $SchedulerRunsTableTable createAlias(String alias) {
    return $SchedulerRunsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterlastSuccessAt =
      const EpochMillisecondsConverter();
}

class SchedulerRunRow extends DataClass implements Insertable<SchedulerRunRow> {
  final String jobId;
  final DateTime lastSuccessAt;
  const SchedulerRunRow({required this.jobId, required this.lastSuccessAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['job_id'] = Variable<String>(jobId);
    {
      map['last_success_at'] = Variable<int>(
        $SchedulerRunsTableTable.$converterlastSuccessAt.toSql(lastSuccessAt),
      );
    }
    return map;
  }

  SchedulerRunsTableCompanion toCompanion(bool nullToAbsent) {
    return SchedulerRunsTableCompanion(
      jobId: Value(jobId),
      lastSuccessAt: Value(lastSuccessAt),
    );
  }

  factory SchedulerRunRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchedulerRunRow(
      jobId: serializer.fromJson<String>(json['jobId']),
      lastSuccessAt: serializer.fromJson<DateTime>(json['lastSuccessAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'jobId': serializer.toJson<String>(jobId),
      'lastSuccessAt': serializer.toJson<DateTime>(lastSuccessAt),
    };
  }

  SchedulerRunRow copyWith({String? jobId, DateTime? lastSuccessAt}) =>
      SchedulerRunRow(
        jobId: jobId ?? this.jobId,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      );
  SchedulerRunRow copyWithCompanion(SchedulerRunsTableCompanion data) {
    return SchedulerRunRow(
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      lastSuccessAt: data.lastSuccessAt.present
          ? data.lastSuccessAt.value
          : this.lastSuccessAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchedulerRunRow(')
          ..write('jobId: $jobId, ')
          ..write('lastSuccessAt: $lastSuccessAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(jobId, lastSuccessAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchedulerRunRow &&
          other.jobId == this.jobId &&
          other.lastSuccessAt == this.lastSuccessAt);
}

class SchedulerRunsTableCompanion extends UpdateCompanion<SchedulerRunRow> {
  final Value<String> jobId;
  final Value<DateTime> lastSuccessAt;
  final Value<int> rowid;
  const SchedulerRunsTableCompanion({
    this.jobId = const Value.absent(),
    this.lastSuccessAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchedulerRunsTableCompanion.insert({
    required String jobId,
    required DateTime lastSuccessAt,
    this.rowid = const Value.absent(),
  }) : jobId = Value(jobId),
       lastSuccessAt = Value(lastSuccessAt);
  static Insertable<SchedulerRunRow> custom({
    Expression<String>? jobId,
    Expression<int>? lastSuccessAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (jobId != null) 'job_id': jobId,
      if (lastSuccessAt != null) 'last_success_at': lastSuccessAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchedulerRunsTableCompanion copyWith({
    Value<String>? jobId,
    Value<DateTime>? lastSuccessAt,
    Value<int>? rowid,
  }) {
    return SchedulerRunsTableCompanion(
      jobId: jobId ?? this.jobId,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (lastSuccessAt.present) {
      map['last_success_at'] = Variable<int>(
        $SchedulerRunsTableTable.$converterlastSuccessAt.toSql(
          lastSuccessAt.value,
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
    return (StringBuffer('SchedulerRunsTableCompanion(')
          ..write('jobId: $jobId, ')
          ..write('lastSuccessAt: $lastSuccessAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RadioStationsTableTable extends RadioStationsTable
    with TableInfo<$RadioStationsTableTable, RadioStationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RadioStationsTableTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostNameMeta = const VerificationMeta(
    'hostName',
  );
  @override
  late final GeneratedColumn<String> hostName = GeneratedColumn<String>(
    'host_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artworkJsonMeta = const VerificationMeta(
    'artworkJson',
  );
  @override
  late final GeneratedColumn<String> artworkJson = GeneratedColumn<String>(
    'artwork_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> addedAt =
      GeneratedColumn<int>(
        'added_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($RadioStationsTableTable.$converteraddedAt);
  @override
  late final GeneratedColumnWithTypeConverter<RadioLiveStatus?, String>
  liveStatus =
      GeneratedColumn<String>(
        'live_status',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<RadioLiveStatus?>(
        $RadioStationsTableTable.$converterliveStatusn,
      );
  static const VerificationMeta _liveTitleMeta = const VerificationMeta(
    'liveTitle',
  );
  @override
  late final GeneratedColumn<String> liveTitle = GeneratedColumn<String>(
    'live_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> statusCheckedAt =
      GeneratedColumn<int>(
        'status_checked_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>(
        $RadioStationsTableTable.$converterstatusCheckedAtn,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pluginId,
    roomId,
    title,
    hostName,
    artworkJson,
    sortOrder,
    addedAt,
    liveStatus,
    liveTitle,
    statusCheckedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'radio_stations';
  @override
  VerificationContext validateIntegrity(
    Insertable<RadioStationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('plugin_id')) {
      context.handle(
        _pluginIdMeta,
        pluginId.isAcceptableOrUnknown(data['plugin_id']!, _pluginIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pluginIdMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('host_name')) {
      context.handle(
        _hostNameMeta,
        hostName.isAcceptableOrUnknown(data['host_name']!, _hostNameMeta),
      );
    }
    if (data.containsKey('artwork_json')) {
      context.handle(
        _artworkJsonMeta,
        artworkJson.isAcceptableOrUnknown(
          data['artwork_json']!,
          _artworkJsonMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('live_title')) {
      context.handle(
        _liveTitleMeta,
        liveTitle.isAcceptableOrUnknown(data['live_title']!, _liveTitleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {pluginId, roomId},
  ];
  @override
  RadioStationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RadioStationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      hostName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_name'],
      ),
      artworkJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_json'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      addedAt: $RadioStationsTableTable.$converteraddedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}added_at'],
        )!,
      ),
      liveStatus: $RadioStationsTableTable.$converterliveStatusn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}live_status'],
        ),
      ),
      liveTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}live_title'],
      ),
      statusCheckedAt: $RadioStationsTableTable.$converterstatusCheckedAtn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.int,
              data['${effectivePrefix}status_checked_at'],
            ),
          ),
    );
  }

  @override
  $RadioStationsTableTable createAlias(String alias) {
    return $RadioStationsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converteraddedAt =
      const EpochMillisecondsConverter();
  static TypeConverter<RadioLiveStatus, String> $converterliveStatus =
      const RadioLiveStatusConverter();
  static TypeConverter<RadioLiveStatus?, String?> $converterliveStatusn =
      NullAwareTypeConverter.wrap($converterliveStatus);
  static TypeConverter<DateTime, int> $converterstatusCheckedAt =
      const EpochMillisecondsConverter();
  static TypeConverter<DateTime?, int?> $converterstatusCheckedAtn =
      NullAwareTypeConverter.wrap($converterstatusCheckedAt);
}

class RadioStationRow extends DataClass implements Insertable<RadioStationRow> {
  final int id;
  final String pluginId;

  /// 音源內的直播間 id（`liveStatus` 回傳的那個，不一定是網址裡的）。
  final String roomId;
  final String title;
  final String? hostName;

  /// `[{url, width?}]` 的 JSON，同 `tracks.artwork_json`；沒有封面為空。
  final String? artworkJson;

  /// 清單順序，由小到大；拖曳後整批重寫。
  final int sortOrder;
  final DateTime addedAt;

  /// 最後一次查到的狀態；還沒查過為空。
  final RadioLiveStatus? liveStatus;
  final String? liveTitle;
  final DateTime? statusCheckedAt;
  const RadioStationRow({
    required this.id,
    required this.pluginId,
    required this.roomId,
    required this.title,
    this.hostName,
    this.artworkJson,
    required this.sortOrder,
    required this.addedAt,
    this.liveStatus,
    this.liveTitle,
    this.statusCheckedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['plugin_id'] = Variable<String>(pluginId);
    map['room_id'] = Variable<String>(roomId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || hostName != null) {
      map['host_name'] = Variable<String>(hostName);
    }
    if (!nullToAbsent || artworkJson != null) {
      map['artwork_json'] = Variable<String>(artworkJson);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    {
      map['added_at'] = Variable<int>(
        $RadioStationsTableTable.$converteraddedAt.toSql(addedAt),
      );
    }
    if (!nullToAbsent || liveStatus != null) {
      map['live_status'] = Variable<String>(
        $RadioStationsTableTable.$converterliveStatusn.toSql(liveStatus),
      );
    }
    if (!nullToAbsent || liveTitle != null) {
      map['live_title'] = Variable<String>(liveTitle);
    }
    if (!nullToAbsent || statusCheckedAt != null) {
      map['status_checked_at'] = Variable<int>(
        $RadioStationsTableTable.$converterstatusCheckedAtn.toSql(
          statusCheckedAt,
        ),
      );
    }
    return map;
  }

  RadioStationsTableCompanion toCompanion(bool nullToAbsent) {
    return RadioStationsTableCompanion(
      id: Value(id),
      pluginId: Value(pluginId),
      roomId: Value(roomId),
      title: Value(title),
      hostName: hostName == null && nullToAbsent
          ? const Value.absent()
          : Value(hostName),
      artworkJson: artworkJson == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkJson),
      sortOrder: Value(sortOrder),
      addedAt: Value(addedAt),
      liveStatus: liveStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(liveStatus),
      liveTitle: liveTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(liveTitle),
      statusCheckedAt: statusCheckedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(statusCheckedAt),
    );
  }

  factory RadioStationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RadioStationRow(
      id: serializer.fromJson<int>(json['id']),
      pluginId: serializer.fromJson<String>(json['pluginId']),
      roomId: serializer.fromJson<String>(json['roomId']),
      title: serializer.fromJson<String>(json['title']),
      hostName: serializer.fromJson<String?>(json['hostName']),
      artworkJson: serializer.fromJson<String?>(json['artworkJson']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      liveStatus: serializer.fromJson<RadioLiveStatus?>(json['liveStatus']),
      liveTitle: serializer.fromJson<String?>(json['liveTitle']),
      statusCheckedAt: serializer.fromJson<DateTime?>(json['statusCheckedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pluginId': serializer.toJson<String>(pluginId),
      'roomId': serializer.toJson<String>(roomId),
      'title': serializer.toJson<String>(title),
      'hostName': serializer.toJson<String?>(hostName),
      'artworkJson': serializer.toJson<String?>(artworkJson),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'liveStatus': serializer.toJson<RadioLiveStatus?>(liveStatus),
      'liveTitle': serializer.toJson<String?>(liveTitle),
      'statusCheckedAt': serializer.toJson<DateTime?>(statusCheckedAt),
    };
  }

  RadioStationRow copyWith({
    int? id,
    String? pluginId,
    String? roomId,
    String? title,
    Value<String?> hostName = const Value.absent(),
    Value<String?> artworkJson = const Value.absent(),
    int? sortOrder,
    DateTime? addedAt,
    Value<RadioLiveStatus?> liveStatus = const Value.absent(),
    Value<String?> liveTitle = const Value.absent(),
    Value<DateTime?> statusCheckedAt = const Value.absent(),
  }) => RadioStationRow(
    id: id ?? this.id,
    pluginId: pluginId ?? this.pluginId,
    roomId: roomId ?? this.roomId,
    title: title ?? this.title,
    hostName: hostName.present ? hostName.value : this.hostName,
    artworkJson: artworkJson.present ? artworkJson.value : this.artworkJson,
    sortOrder: sortOrder ?? this.sortOrder,
    addedAt: addedAt ?? this.addedAt,
    liveStatus: liveStatus.present ? liveStatus.value : this.liveStatus,
    liveTitle: liveTitle.present ? liveTitle.value : this.liveTitle,
    statusCheckedAt: statusCheckedAt.present
        ? statusCheckedAt.value
        : this.statusCheckedAt,
  );
  RadioStationRow copyWithCompanion(RadioStationsTableCompanion data) {
    return RadioStationRow(
      id: data.id.present ? data.id.value : this.id,
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      title: data.title.present ? data.title.value : this.title,
      hostName: data.hostName.present ? data.hostName.value : this.hostName,
      artworkJson: data.artworkJson.present
          ? data.artworkJson.value
          : this.artworkJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      liveStatus: data.liveStatus.present
          ? data.liveStatus.value
          : this.liveStatus,
      liveTitle: data.liveTitle.present ? data.liveTitle.value : this.liveTitle,
      statusCheckedAt: data.statusCheckedAt.present
          ? data.statusCheckedAt.value
          : this.statusCheckedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RadioStationRow(')
          ..write('id: $id, ')
          ..write('pluginId: $pluginId, ')
          ..write('roomId: $roomId, ')
          ..write('title: $title, ')
          ..write('hostName: $hostName, ')
          ..write('artworkJson: $artworkJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAt: $addedAt, ')
          ..write('liveStatus: $liveStatus, ')
          ..write('liveTitle: $liveTitle, ')
          ..write('statusCheckedAt: $statusCheckedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pluginId,
    roomId,
    title,
    hostName,
    artworkJson,
    sortOrder,
    addedAt,
    liveStatus,
    liveTitle,
    statusCheckedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RadioStationRow &&
          other.id == this.id &&
          other.pluginId == this.pluginId &&
          other.roomId == this.roomId &&
          other.title == this.title &&
          other.hostName == this.hostName &&
          other.artworkJson == this.artworkJson &&
          other.sortOrder == this.sortOrder &&
          other.addedAt == this.addedAt &&
          other.liveStatus == this.liveStatus &&
          other.liveTitle == this.liveTitle &&
          other.statusCheckedAt == this.statusCheckedAt);
}

class RadioStationsTableCompanion extends UpdateCompanion<RadioStationRow> {
  final Value<int> id;
  final Value<String> pluginId;
  final Value<String> roomId;
  final Value<String> title;
  final Value<String?> hostName;
  final Value<String?> artworkJson;
  final Value<int> sortOrder;
  final Value<DateTime> addedAt;
  final Value<RadioLiveStatus?> liveStatus;
  final Value<String?> liveTitle;
  final Value<DateTime?> statusCheckedAt;
  const RadioStationsTableCompanion({
    this.id = const Value.absent(),
    this.pluginId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.title = const Value.absent(),
    this.hostName = const Value.absent(),
    this.artworkJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.liveStatus = const Value.absent(),
    this.liveTitle = const Value.absent(),
    this.statusCheckedAt = const Value.absent(),
  });
  RadioStationsTableCompanion.insert({
    this.id = const Value.absent(),
    required String pluginId,
    required String roomId,
    required String title,
    this.hostName = const Value.absent(),
    this.artworkJson = const Value.absent(),
    required int sortOrder,
    required DateTime addedAt,
    this.liveStatus = const Value.absent(),
    this.liveTitle = const Value.absent(),
    this.statusCheckedAt = const Value.absent(),
  }) : pluginId = Value(pluginId),
       roomId = Value(roomId),
       title = Value(title),
       sortOrder = Value(sortOrder),
       addedAt = Value(addedAt);
  static Insertable<RadioStationRow> custom({
    Expression<int>? id,
    Expression<String>? pluginId,
    Expression<String>? roomId,
    Expression<String>? title,
    Expression<String>? hostName,
    Expression<String>? artworkJson,
    Expression<int>? sortOrder,
    Expression<int>? addedAt,
    Expression<String>? liveStatus,
    Expression<String>? liveTitle,
    Expression<int>? statusCheckedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pluginId != null) 'plugin_id': pluginId,
      if (roomId != null) 'room_id': roomId,
      if (title != null) 'title': title,
      if (hostName != null) 'host_name': hostName,
      if (artworkJson != null) 'artwork_json': artworkJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (addedAt != null) 'added_at': addedAt,
      if (liveStatus != null) 'live_status': liveStatus,
      if (liveTitle != null) 'live_title': liveTitle,
      if (statusCheckedAt != null) 'status_checked_at': statusCheckedAt,
    });
  }

  RadioStationsTableCompanion copyWith({
    Value<int>? id,
    Value<String>? pluginId,
    Value<String>? roomId,
    Value<String>? title,
    Value<String?>? hostName,
    Value<String?>? artworkJson,
    Value<int>? sortOrder,
    Value<DateTime>? addedAt,
    Value<RadioLiveStatus?>? liveStatus,
    Value<String?>? liveTitle,
    Value<DateTime?>? statusCheckedAt,
  }) {
    return RadioStationsTableCompanion(
      id: id ?? this.id,
      pluginId: pluginId ?? this.pluginId,
      roomId: roomId ?? this.roomId,
      title: title ?? this.title,
      hostName: hostName ?? this.hostName,
      artworkJson: artworkJson ?? this.artworkJson,
      sortOrder: sortOrder ?? this.sortOrder,
      addedAt: addedAt ?? this.addedAt,
      liveStatus: liveStatus ?? this.liveStatus,
      liveTitle: liveTitle ?? this.liveTitle,
      statusCheckedAt: statusCheckedAt ?? this.statusCheckedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (hostName.present) {
      map['host_name'] = Variable<String>(hostName.value);
    }
    if (artworkJson.present) {
      map['artwork_json'] = Variable<String>(artworkJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(
        $RadioStationsTableTable.$converteraddedAt.toSql(addedAt.value),
      );
    }
    if (liveStatus.present) {
      map['live_status'] = Variable<String>(
        $RadioStationsTableTable.$converterliveStatusn.toSql(liveStatus.value),
      );
    }
    if (liveTitle.present) {
      map['live_title'] = Variable<String>(liveTitle.value);
    }
    if (statusCheckedAt.present) {
      map['status_checked_at'] = Variable<int>(
        $RadioStationsTableTable.$converterstatusCheckedAtn.toSql(
          statusCheckedAt.value,
        ),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RadioStationsTableCompanion(')
          ..write('id: $id, ')
          ..write('pluginId: $pluginId, ')
          ..write('roomId: $roomId, ')
          ..write('title: $title, ')
          ..write('hostName: $hostName, ')
          ..write('artworkJson: $artworkJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAt: $addedAt, ')
          ..write('liveStatus: $liveStatus, ')
          ..write('liveTitle: $liveTitle, ')
          ..write('statusCheckedAt: $statusCheckedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTableTable extends PlaylistsTable
    with TableInfo<$PlaylistsTableTable, PlaylistRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTableTable(this.attachedDatabase, [this._alias]);
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
  @override
  late final GeneratedColumnWithTypeConverter<PlaylistKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PlaylistKind>($PlaylistsTableTable.$converterkind);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artworkJsonMeta = const VerificationMeta(
    'artworkJson',
  );
  @override
  late final GeneratedColumn<String> artworkJson = GeneratedColumn<String>(
    'artwork_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> createdAt =
      GeneratedColumn<int>(
        'created_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PlaylistsTableTable.$convertercreatedAt);
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> updatedAt =
      GeneratedColumn<int>(
        'updated_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($PlaylistsTableTable.$converterupdatedAt);
  static const VerificationMeta _mixPluginIdMeta = const VerificationMeta(
    'mixPluginId',
  );
  @override
  late final GeneratedColumn<String> mixPluginId = GeneratedColumn<String>(
    'mix_plugin_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mixSeedSourceIdMeta = const VerificationMeta(
    'mixSeedSourceId',
  );
  @override
  late final GeneratedColumn<String> mixSeedSourceId = GeneratedColumn<String>(
    'mix_seed_source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mixSeedCidMeta = const VerificationMeta(
    'mixSeedCid',
  );
  @override
  late final GeneratedColumn<int> mixSeedCid = GeneratedColumn<int>(
    'mix_seed_cid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    name,
    description,
    artworkJson,
    sortOrder,
    createdAt,
    updatedAt,
    mixPluginId,
    mixSeedSourceId,
    mixSeedCid,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('artwork_json')) {
      context.handle(
        _artworkJsonMeta,
        artworkJson.isAcceptableOrUnknown(
          data['artwork_json']!,
          _artworkJsonMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('mix_plugin_id')) {
      context.handle(
        _mixPluginIdMeta,
        mixPluginId.isAcceptableOrUnknown(
          data['mix_plugin_id']!,
          _mixPluginIdMeta,
        ),
      );
    }
    if (data.containsKey('mix_seed_source_id')) {
      context.handle(
        _mixSeedSourceIdMeta,
        mixSeedSourceId.isAcceptableOrUnknown(
          data['mix_seed_source_id']!,
          _mixSeedSourceIdMeta,
        ),
      );
    }
    if (data.containsKey('mix_seed_cid')) {
      context.handle(
        _mixSeedCidMeta,
        mixSeedCid.isAcceptableOrUnknown(
          data['mix_seed_cid']!,
          _mixSeedCidMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: $PlaylistsTableTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      artworkJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_json'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: $PlaylistsTableTable.$convertercreatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}created_at'],
        )!,
      ),
      updatedAt: $PlaylistsTableTable.$converterupdatedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}updated_at'],
        )!,
      ),
      mixPluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_plugin_id'],
      ),
      mixSeedSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mix_seed_source_id'],
      ),
      mixSeedCid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mix_seed_cid'],
      ),
    );
  }

  @override
  $PlaylistsTableTable createAlias(String alias) {
    return $PlaylistsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<PlaylistKind, String> $converterkind =
      const PlaylistKindConverter();
  static TypeConverter<DateTime, int> $convertercreatedAt =
      const EpochMillisecondsConverter();
  static TypeConverter<DateTime, int> $converterupdatedAt =
      const EpochMillisecondsConverter();
}

class PlaylistRow extends DataClass implements Insertable<PlaylistRow> {
  final int id;
  final PlaylistKind kind;
  final String name;
  final String? description;

  /// `[{url, width?}]` 的 JSON，同 `tracks.artwork_json`；沒有封面為空。
  final String? artworkJson;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? mixPluginId;
  final String? mixSeedSourceId;
  final int? mixSeedCid;
  const PlaylistRow({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    this.artworkJson,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.mixPluginId,
    this.mixSeedSourceId,
    this.mixSeedCid,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['kind'] = Variable<String>(
        $PlaylistsTableTable.$converterkind.toSql(kind),
      );
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || artworkJson != null) {
      map['artwork_json'] = Variable<String>(artworkJson);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    {
      map['created_at'] = Variable<int>(
        $PlaylistsTableTable.$convertercreatedAt.toSql(createdAt),
      );
    }
    {
      map['updated_at'] = Variable<int>(
        $PlaylistsTableTable.$converterupdatedAt.toSql(updatedAt),
      );
    }
    if (!nullToAbsent || mixPluginId != null) {
      map['mix_plugin_id'] = Variable<String>(mixPluginId);
    }
    if (!nullToAbsent || mixSeedSourceId != null) {
      map['mix_seed_source_id'] = Variable<String>(mixSeedSourceId);
    }
    if (!nullToAbsent || mixSeedCid != null) {
      map['mix_seed_cid'] = Variable<int>(mixSeedCid);
    }
    return map;
  }

  PlaylistsTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsTableCompanion(
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      artworkJson: artworkJson == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkJson),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      mixPluginId: mixPluginId == null && nullToAbsent
          ? const Value.absent()
          : Value(mixPluginId),
      mixSeedSourceId: mixSeedSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(mixSeedSourceId),
      mixSeedCid: mixSeedCid == null && nullToAbsent
          ? const Value.absent()
          : Value(mixSeedCid),
    );
  }

  factory PlaylistRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<PlaylistKind>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      artworkJson: serializer.fromJson<String?>(json['artworkJson']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      mixPluginId: serializer.fromJson<String?>(json['mixPluginId']),
      mixSeedSourceId: serializer.fromJson<String?>(json['mixSeedSourceId']),
      mixSeedCid: serializer.fromJson<int?>(json['mixSeedCid']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<PlaylistKind>(kind),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'artworkJson': serializer.toJson<String?>(artworkJson),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'mixPluginId': serializer.toJson<String?>(mixPluginId),
      'mixSeedSourceId': serializer.toJson<String?>(mixSeedSourceId),
      'mixSeedCid': serializer.toJson<int?>(mixSeedCid),
    };
  }

  PlaylistRow copyWith({
    int? id,
    PlaylistKind? kind,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> artworkJson = const Value.absent(),
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> mixPluginId = const Value.absent(),
    Value<String?> mixSeedSourceId = const Value.absent(),
    Value<int?> mixSeedCid = const Value.absent(),
  }) => PlaylistRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    artworkJson: artworkJson.present ? artworkJson.value : this.artworkJson,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    mixPluginId: mixPluginId.present ? mixPluginId.value : this.mixPluginId,
    mixSeedSourceId: mixSeedSourceId.present
        ? mixSeedSourceId.value
        : this.mixSeedSourceId,
    mixSeedCid: mixSeedCid.present ? mixSeedCid.value : this.mixSeedCid,
  );
  PlaylistRow copyWithCompanion(PlaylistsTableCompanion data) {
    return PlaylistRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      artworkJson: data.artworkJson.present
          ? data.artworkJson.value
          : this.artworkJson,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      mixPluginId: data.mixPluginId.present
          ? data.mixPluginId.value
          : this.mixPluginId,
      mixSeedSourceId: data.mixSeedSourceId.present
          ? data.mixSeedSourceId.value
          : this.mixSeedSourceId,
      mixSeedCid: data.mixSeedCid.present
          ? data.mixSeedCid.value
          : this.mixSeedCid,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('artworkJson: $artworkJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mixPluginId: $mixPluginId, ')
          ..write('mixSeedSourceId: $mixSeedSourceId, ')
          ..write('mixSeedCid: $mixSeedCid')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    description,
    artworkJson,
    sortOrder,
    createdAt,
    updatedAt,
    mixPluginId,
    mixSeedSourceId,
    mixSeedCid,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.description == this.description &&
          other.artworkJson == this.artworkJson &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.mixPluginId == this.mixPluginId &&
          other.mixSeedSourceId == this.mixSeedSourceId &&
          other.mixSeedCid == this.mixSeedCid);
}

class PlaylistsTableCompanion extends UpdateCompanion<PlaylistRow> {
  final Value<int> id;
  final Value<PlaylistKind> kind;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> artworkJson;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> mixPluginId;
  final Value<String?> mixSeedSourceId;
  final Value<int?> mixSeedCid;
  const PlaylistsTableCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.artworkJson = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.mixPluginId = const Value.absent(),
    this.mixSeedSourceId = const Value.absent(),
    this.mixSeedCid = const Value.absent(),
  });
  PlaylistsTableCompanion.insert({
    this.id = const Value.absent(),
    required PlaylistKind kind,
    required String name,
    this.description = const Value.absent(),
    this.artworkJson = const Value.absent(),
    required int sortOrder,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.mixPluginId = const Value.absent(),
    this.mixSeedSourceId = const Value.absent(),
    this.mixSeedCid = const Value.absent(),
  }) : kind = Value(kind),
       name = Value(name),
       sortOrder = Value(sortOrder),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlaylistRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? artworkJson,
    Expression<int>? sortOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? mixPluginId,
    Expression<String>? mixSeedSourceId,
    Expression<int>? mixSeedCid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (artworkJson != null) 'artwork_json': artworkJson,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (mixPluginId != null) 'mix_plugin_id': mixPluginId,
      if (mixSeedSourceId != null) 'mix_seed_source_id': mixSeedSourceId,
      if (mixSeedCid != null) 'mix_seed_cid': mixSeedCid,
    });
  }

  PlaylistsTableCompanion copyWith({
    Value<int>? id,
    Value<PlaylistKind>? kind,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? artworkJson,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? mixPluginId,
    Value<String?>? mixSeedSourceId,
    Value<int?>? mixSeedCid,
  }) {
    return PlaylistsTableCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      description: description ?? this.description,
      artworkJson: artworkJson ?? this.artworkJson,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mixPluginId: mixPluginId ?? this.mixPluginId,
      mixSeedSourceId: mixSeedSourceId ?? this.mixSeedSourceId,
      mixSeedCid: mixSeedCid ?? this.mixSeedCid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $PlaylistsTableTable.$converterkind.toSql(kind.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (artworkJson.present) {
      map['artwork_json'] = Variable<String>(artworkJson.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(
        $PlaylistsTableTable.$convertercreatedAt.toSql(createdAt.value),
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(
        $PlaylistsTableTable.$converterupdatedAt.toSql(updatedAt.value),
      );
    }
    if (mixPluginId.present) {
      map['mix_plugin_id'] = Variable<String>(mixPluginId.value);
    }
    if (mixSeedSourceId.present) {
      map['mix_seed_source_id'] = Variable<String>(mixSeedSourceId.value);
    }
    if (mixSeedCid.present) {
      map['mix_seed_cid'] = Variable<int>(mixSeedCid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsTableCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('artworkJson: $artworkJson, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mixPluginId: $mixPluginId, ')
          ..write('mixSeedSourceId: $mixSeedSourceId, ')
          ..write('mixSeedCid: $mixSeedCid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistEntriesTableTable extends PlaylistEntriesTable
    with TableInfo<$PlaylistEntriesTableTable, PlaylistEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistEntriesTableTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES playlists (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (track_key) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _remoteItemIdMeta = const VerificationMeta(
    'remoteItemId',
  );
  @override
  late final GeneratedColumn<String> remoteItemId = GeneratedColumn<String>(
    'remote_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unavailableMeta = const VerificationMeta(
    'unavailable',
  );
  @override
  late final GeneratedColumn<bool> unavailable = GeneratedColumn<bool>(
    'unavailable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("unavailable" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _seenGenerationMeta = const VerificationMeta(
    'seenGeneration',
  );
  @override
  late final GeneratedColumn<int> seenGeneration = GeneratedColumn<int>(
    'seen_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    playlistId,
    position,
    trackKey,
    remoteItemId,
    unavailable,
    seenGeneration,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    if (data.containsKey('remote_item_id')) {
      context.handle(
        _remoteItemIdMeta,
        remoteItemId.isAcceptableOrUnknown(
          data['remote_item_id']!,
          _remoteItemIdMeta,
        ),
      );
    }
    if (data.containsKey('unavailable')) {
      context.handle(
        _unavailableMeta,
        unavailable.isAcceptableOrUnknown(
          data['unavailable']!,
          _unavailableMeta,
        ),
      );
    }
    if (data.containsKey('seen_generation')) {
      context.handle(
        _seenGenerationMeta,
        seenGeneration.isAcceptableOrUnknown(
          data['seen_generation']!,
          _seenGenerationMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}playlist_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      remoteItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_item_id'],
      ),
      unavailable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}unavailable'],
      )!,
      seenGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seen_generation'],
      )!,
    );
  }

  @override
  $PlaylistEntriesTableTable createAlias(String alias) {
    return $PlaylistEntriesTableTable(attachedDatabase, alias);
  }
}

class PlaylistEntryRow extends DataClass
    implements Insertable<PlaylistEntryRow> {
  final int id;
  final int playlistId;
  final int position;
  final String trackKey;
  final String? remoteItemId;
  final bool unavailable;
  final int seenGeneration;
  const PlaylistEntryRow({
    required this.id,
    required this.playlistId,
    required this.position,
    required this.trackKey,
    this.remoteItemId,
    required this.unavailable,
    required this.seenGeneration,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<int>(playlistId);
    map['position'] = Variable<int>(position);
    map['track_key'] = Variable<String>(trackKey);
    if (!nullToAbsent || remoteItemId != null) {
      map['remote_item_id'] = Variable<String>(remoteItemId);
    }
    map['unavailable'] = Variable<bool>(unavailable);
    map['seen_generation'] = Variable<int>(seenGeneration);
    return map;
  }

  PlaylistEntriesTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistEntriesTableCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      position: Value(position),
      trackKey: Value(trackKey),
      remoteItemId: remoteItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteItemId),
      unavailable: Value(unavailable),
      seenGeneration: Value(seenGeneration),
    );
  }

  factory PlaylistEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistEntryRow(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<int>(json['playlistId']),
      position: serializer.fromJson<int>(json['position']),
      trackKey: serializer.fromJson<String>(json['trackKey']),
      remoteItemId: serializer.fromJson<String?>(json['remoteItemId']),
      unavailable: serializer.fromJson<bool>(json['unavailable']),
      seenGeneration: serializer.fromJson<int>(json['seenGeneration']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<int>(playlistId),
      'position': serializer.toJson<int>(position),
      'trackKey': serializer.toJson<String>(trackKey),
      'remoteItemId': serializer.toJson<String?>(remoteItemId),
      'unavailable': serializer.toJson<bool>(unavailable),
      'seenGeneration': serializer.toJson<int>(seenGeneration),
    };
  }

  PlaylistEntryRow copyWith({
    int? id,
    int? playlistId,
    int? position,
    String? trackKey,
    Value<String?> remoteItemId = const Value.absent(),
    bool? unavailable,
    int? seenGeneration,
  }) => PlaylistEntryRow(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    position: position ?? this.position,
    trackKey: trackKey ?? this.trackKey,
    remoteItemId: remoteItemId.present ? remoteItemId.value : this.remoteItemId,
    unavailable: unavailable ?? this.unavailable,
    seenGeneration: seenGeneration ?? this.seenGeneration,
  );
  PlaylistEntryRow copyWithCompanion(PlaylistEntriesTableCompanion data) {
    return PlaylistEntryRow(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      position: data.position.present ? data.position.value : this.position,
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      remoteItemId: data.remoteItemId.present
          ? data.remoteItemId.value
          : this.remoteItemId,
      unavailable: data.unavailable.present
          ? data.unavailable.value
          : this.unavailable,
      seenGeneration: data.seenGeneration.present
          ? data.seenGeneration.value
          : this.seenGeneration,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntryRow(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('position: $position, ')
          ..write('trackKey: $trackKey, ')
          ..write('remoteItemId: $remoteItemId, ')
          ..write('unavailable: $unavailable, ')
          ..write('seenGeneration: $seenGeneration')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    playlistId,
    position,
    trackKey,
    remoteItemId,
    unavailable,
    seenGeneration,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistEntryRow &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.position == this.position &&
          other.trackKey == this.trackKey &&
          other.remoteItemId == this.remoteItemId &&
          other.unavailable == this.unavailable &&
          other.seenGeneration == this.seenGeneration);
}

class PlaylistEntriesTableCompanion extends UpdateCompanion<PlaylistEntryRow> {
  final Value<int> id;
  final Value<int> playlistId;
  final Value<int> position;
  final Value<String> trackKey;
  final Value<String?> remoteItemId;
  final Value<bool> unavailable;
  final Value<int> seenGeneration;
  const PlaylistEntriesTableCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.position = const Value.absent(),
    this.trackKey = const Value.absent(),
    this.remoteItemId = const Value.absent(),
    this.unavailable = const Value.absent(),
    this.seenGeneration = const Value.absent(),
  });
  PlaylistEntriesTableCompanion.insert({
    this.id = const Value.absent(),
    required int playlistId,
    required int position,
    required String trackKey,
    this.remoteItemId = const Value.absent(),
    this.unavailable = const Value.absent(),
    this.seenGeneration = const Value.absent(),
  }) : playlistId = Value(playlistId),
       position = Value(position),
       trackKey = Value(trackKey);
  static Insertable<PlaylistEntryRow> custom({
    Expression<int>? id,
    Expression<int>? playlistId,
    Expression<int>? position,
    Expression<String>? trackKey,
    Expression<String>? remoteItemId,
    Expression<bool>? unavailable,
    Expression<int>? seenGeneration,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (position != null) 'position': position,
      if (trackKey != null) 'track_key': trackKey,
      if (remoteItemId != null) 'remote_item_id': remoteItemId,
      if (unavailable != null) 'unavailable': unavailable,
      if (seenGeneration != null) 'seen_generation': seenGeneration,
    });
  }

  PlaylistEntriesTableCompanion copyWith({
    Value<int>? id,
    Value<int>? playlistId,
    Value<int>? position,
    Value<String>? trackKey,
    Value<String?>? remoteItemId,
    Value<bool>? unavailable,
    Value<int>? seenGeneration,
  }) {
    return PlaylistEntriesTableCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      position: position ?? this.position,
      trackKey: trackKey ?? this.trackKey,
      remoteItemId: remoteItemId ?? this.remoteItemId,
      unavailable: unavailable ?? this.unavailable,
      seenGeneration: seenGeneration ?? this.seenGeneration,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (remoteItemId.present) {
      map['remote_item_id'] = Variable<String>(remoteItemId.value);
    }
    if (unavailable.present) {
      map['unavailable'] = Variable<bool>(unavailable.value);
    }
    if (seenGeneration.present) {
      map['seen_generation'] = Variable<int>(seenGeneration.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistEntriesTableCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('position: $position, ')
          ..write('trackKey: $trackKey, ')
          ..write('remoteItemId: $remoteItemId, ')
          ..write('unavailable: $unavailable, ')
          ..write('seenGeneration: $seenGeneration')
          ..write(')'))
        .toString();
  }
}

class $PlaylistRemoteTableTable extends PlaylistRemoteTable
    with TableInfo<$PlaylistRemoteTableTable, PlaylistRemoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistRemoteTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES playlists (id) ON DELETE CASCADE',
    ),
  );
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
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerNameMeta = const VerificationMeta(
    'ownerName',
  );
  @override
  late final GeneratedColumn<String> ownerName = GeneratedColumn<String>(
    'owner_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _writableMeta = const VerificationMeta(
    'writable',
  );
  @override
  late final GeneratedColumn<bool> writable = GeneratedColumn<bool>(
    'writable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("writable" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nameOverriddenMeta = const VerificationMeta(
    'nameOverridden',
  );
  @override
  late final GeneratedColumn<bool> nameOverridden = GeneratedColumn<bool>(
    'name_overridden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("name_overridden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _descriptionOverriddenMeta =
      const VerificationMeta('descriptionOverridden');
  @override
  late final GeneratedColumn<bool> descriptionOverridden =
      GeneratedColumn<bool>(
        'description_overridden',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("description_overridden" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _artworkOverriddenMeta = const VerificationMeta(
    'artworkOverridden',
  );
  @override
  late final GeneratedColumn<bool> artworkOverridden = GeneratedColumn<bool>(
    'artwork_overridden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("artwork_overridden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _refreshIntervalHoursMeta =
      const VerificationMeta('refreshIntervalHours');
  @override
  late final GeneratedColumn<int> refreshIntervalHours = GeneratedColumn<int>(
    'refresh_interval_hours',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime?, int> lastRefreshedAt =
      GeneratedColumn<int>(
        'last_refreshed_at',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<DateTime?>(
        $PlaylistRemoteTableTable.$converterlastRefreshedAtn,
      );
  @override
  late final GeneratedColumnWithTypeConverter<PlaylistRefreshResult?, String>
  lastResult =
      GeneratedColumn<String>(
        'last_result',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<PlaylistRefreshResult?>(
        $PlaylistRemoteTableTable.$converterlastResultn,
      );
  @override
  late final GeneratedColumnWithTypeConverter<PlaylistRemoteStatus, String>
  status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('active'),
      ).withConverter<PlaylistRemoteStatus>(
        $PlaylistRemoteTableTable.$converterstatus,
      );
  static const VerificationMeta _refreshGenerationMeta = const VerificationMeta(
    'refreshGeneration',
  );
  @override
  late final GeneratedColumn<int> refreshGeneration = GeneratedColumn<int>(
    'refresh_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    pluginId,
    remoteId,
    ownerName,
    writable,
    nameOverridden,
    descriptionOverridden,
    artworkOverridden,
    refreshIntervalHours,
    lastRefreshedAt,
    lastResult,
    status,
    refreshGeneration,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_remote';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistRemoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    }
    if (data.containsKey('plugin_id')) {
      context.handle(
        _pluginIdMeta,
        pluginId.isAcceptableOrUnknown(data['plugin_id']!, _pluginIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pluginIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('owner_name')) {
      context.handle(
        _ownerNameMeta,
        ownerName.isAcceptableOrUnknown(data['owner_name']!, _ownerNameMeta),
      );
    }
    if (data.containsKey('writable')) {
      context.handle(
        _writableMeta,
        writable.isAcceptableOrUnknown(data['writable']!, _writableMeta),
      );
    }
    if (data.containsKey('name_overridden')) {
      context.handle(
        _nameOverriddenMeta,
        nameOverridden.isAcceptableOrUnknown(
          data['name_overridden']!,
          _nameOverriddenMeta,
        ),
      );
    }
    if (data.containsKey('description_overridden')) {
      context.handle(
        _descriptionOverriddenMeta,
        descriptionOverridden.isAcceptableOrUnknown(
          data['description_overridden']!,
          _descriptionOverriddenMeta,
        ),
      );
    }
    if (data.containsKey('artwork_overridden')) {
      context.handle(
        _artworkOverriddenMeta,
        artworkOverridden.isAcceptableOrUnknown(
          data['artwork_overridden']!,
          _artworkOverriddenMeta,
        ),
      );
    }
    if (data.containsKey('refresh_interval_hours')) {
      context.handle(
        _refreshIntervalHoursMeta,
        refreshIntervalHours.isAcceptableOrUnknown(
          data['refresh_interval_hours']!,
          _refreshIntervalHoursMeta,
        ),
      );
    }
    if (data.containsKey('refresh_generation')) {
      context.handle(
        _refreshGenerationMeta,
        refreshGeneration.isAcceptableOrUnknown(
          data['refresh_generation']!,
          _refreshGenerationMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {pluginId, remoteId},
  ];
  @override
  PlaylistRemoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistRemoteRow(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}playlist_id'],
      )!,
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      ownerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_name'],
      ),
      writable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}writable'],
      )!,
      nameOverridden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}name_overridden'],
      )!,
      descriptionOverridden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}description_overridden'],
      )!,
      artworkOverridden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}artwork_overridden'],
      )!,
      refreshIntervalHours: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}refresh_interval_hours'],
      ),
      lastRefreshedAt: $PlaylistRemoteTableTable.$converterlastRefreshedAtn
          .fromSql(
            attachedDatabase.typeMapping.read(
              DriftSqlType.int,
              data['${effectivePrefix}last_refreshed_at'],
            ),
          ),
      lastResult: $PlaylistRemoteTableTable.$converterlastResultn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_result'],
        ),
      ),
      status: $PlaylistRemoteTableTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      refreshGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}refresh_generation'],
      )!,
    );
  }

  @override
  $PlaylistRemoteTableTable createAlias(String alias) {
    return $PlaylistRemoteTableTable(attachedDatabase, alias);
  }

  static TypeConverter<DateTime, int> $converterlastRefreshedAt =
      const EpochMillisecondsConverter();
  static TypeConverter<DateTime?, int?> $converterlastRefreshedAtn =
      NullAwareTypeConverter.wrap($converterlastRefreshedAt);
  static TypeConverter<PlaylistRefreshResult, String> $converterlastResult =
      const PlaylistRefreshResultConverter();
  static TypeConverter<PlaylistRefreshResult?, String?> $converterlastResultn =
      NullAwareTypeConverter.wrap($converterlastResult);
  static TypeConverter<PlaylistRemoteStatus, String> $converterstatus =
      const PlaylistRemoteStatusConverter();
}

class PlaylistRemoteRow extends DataClass
    implements Insertable<PlaylistRemoteRow> {
  final int playlistId;
  final String pluginId;
  final String remoteId;
  final String? ownerName;
  final bool writable;
  final bool nameOverridden;
  final bool descriptionOverridden;
  final bool artworkOverridden;

  /// 空＝不啟用自動刷新；新匯入 24。
  final int? refreshIntervalHours;
  final DateTime? lastRefreshedAt;
  final PlaylistRefreshResult? lastResult;
  final PlaylistRemoteStatus status;

  /// 每次刷新開始加一；寫頁與套用前比對，過期的刷新就停（ADR 0033 §決定 2）。
  final int refreshGeneration;
  const PlaylistRemoteRow({
    required this.playlistId,
    required this.pluginId,
    required this.remoteId,
    this.ownerName,
    required this.writable,
    required this.nameOverridden,
    required this.descriptionOverridden,
    required this.artworkOverridden,
    this.refreshIntervalHours,
    this.lastRefreshedAt,
    this.lastResult,
    required this.status,
    required this.refreshGeneration,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<int>(playlistId);
    map['plugin_id'] = Variable<String>(pluginId);
    map['remote_id'] = Variable<String>(remoteId);
    if (!nullToAbsent || ownerName != null) {
      map['owner_name'] = Variable<String>(ownerName);
    }
    map['writable'] = Variable<bool>(writable);
    map['name_overridden'] = Variable<bool>(nameOverridden);
    map['description_overridden'] = Variable<bool>(descriptionOverridden);
    map['artwork_overridden'] = Variable<bool>(artworkOverridden);
    if (!nullToAbsent || refreshIntervalHours != null) {
      map['refresh_interval_hours'] = Variable<int>(refreshIntervalHours);
    }
    if (!nullToAbsent || lastRefreshedAt != null) {
      map['last_refreshed_at'] = Variable<int>(
        $PlaylistRemoteTableTable.$converterlastRefreshedAtn.toSql(
          lastRefreshedAt,
        ),
      );
    }
    if (!nullToAbsent || lastResult != null) {
      map['last_result'] = Variable<String>(
        $PlaylistRemoteTableTable.$converterlastResultn.toSql(lastResult),
      );
    }
    {
      map['status'] = Variable<String>(
        $PlaylistRemoteTableTable.$converterstatus.toSql(status),
      );
    }
    map['refresh_generation'] = Variable<int>(refreshGeneration);
    return map;
  }

  PlaylistRemoteTableCompanion toCompanion(bool nullToAbsent) {
    return PlaylistRemoteTableCompanion(
      playlistId: Value(playlistId),
      pluginId: Value(pluginId),
      remoteId: Value(remoteId),
      ownerName: ownerName == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerName),
      writable: Value(writable),
      nameOverridden: Value(nameOverridden),
      descriptionOverridden: Value(descriptionOverridden),
      artworkOverridden: Value(artworkOverridden),
      refreshIntervalHours: refreshIntervalHours == null && nullToAbsent
          ? const Value.absent()
          : Value(refreshIntervalHours),
      lastRefreshedAt: lastRefreshedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRefreshedAt),
      lastResult: lastResult == null && nullToAbsent
          ? const Value.absent()
          : Value(lastResult),
      status: Value(status),
      refreshGeneration: Value(refreshGeneration),
    );
  }

  factory PlaylistRemoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistRemoteRow(
      playlistId: serializer.fromJson<int>(json['playlistId']),
      pluginId: serializer.fromJson<String>(json['pluginId']),
      remoteId: serializer.fromJson<String>(json['remoteId']),
      ownerName: serializer.fromJson<String?>(json['ownerName']),
      writable: serializer.fromJson<bool>(json['writable']),
      nameOverridden: serializer.fromJson<bool>(json['nameOverridden']),
      descriptionOverridden: serializer.fromJson<bool>(
        json['descriptionOverridden'],
      ),
      artworkOverridden: serializer.fromJson<bool>(json['artworkOverridden']),
      refreshIntervalHours: serializer.fromJson<int?>(
        json['refreshIntervalHours'],
      ),
      lastRefreshedAt: serializer.fromJson<DateTime?>(json['lastRefreshedAt']),
      lastResult: serializer.fromJson<PlaylistRefreshResult?>(
        json['lastResult'],
      ),
      status: serializer.fromJson<PlaylistRemoteStatus>(json['status']),
      refreshGeneration: serializer.fromJson<int>(json['refreshGeneration']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<int>(playlistId),
      'pluginId': serializer.toJson<String>(pluginId),
      'remoteId': serializer.toJson<String>(remoteId),
      'ownerName': serializer.toJson<String?>(ownerName),
      'writable': serializer.toJson<bool>(writable),
      'nameOverridden': serializer.toJson<bool>(nameOverridden),
      'descriptionOverridden': serializer.toJson<bool>(descriptionOverridden),
      'artworkOverridden': serializer.toJson<bool>(artworkOverridden),
      'refreshIntervalHours': serializer.toJson<int?>(refreshIntervalHours),
      'lastRefreshedAt': serializer.toJson<DateTime?>(lastRefreshedAt),
      'lastResult': serializer.toJson<PlaylistRefreshResult?>(lastResult),
      'status': serializer.toJson<PlaylistRemoteStatus>(status),
      'refreshGeneration': serializer.toJson<int>(refreshGeneration),
    };
  }

  PlaylistRemoteRow copyWith({
    int? playlistId,
    String? pluginId,
    String? remoteId,
    Value<String?> ownerName = const Value.absent(),
    bool? writable,
    bool? nameOverridden,
    bool? descriptionOverridden,
    bool? artworkOverridden,
    Value<int?> refreshIntervalHours = const Value.absent(),
    Value<DateTime?> lastRefreshedAt = const Value.absent(),
    Value<PlaylistRefreshResult?> lastResult = const Value.absent(),
    PlaylistRemoteStatus? status,
    int? refreshGeneration,
  }) => PlaylistRemoteRow(
    playlistId: playlistId ?? this.playlistId,
    pluginId: pluginId ?? this.pluginId,
    remoteId: remoteId ?? this.remoteId,
    ownerName: ownerName.present ? ownerName.value : this.ownerName,
    writable: writable ?? this.writable,
    nameOverridden: nameOverridden ?? this.nameOverridden,
    descriptionOverridden: descriptionOverridden ?? this.descriptionOverridden,
    artworkOverridden: artworkOverridden ?? this.artworkOverridden,
    refreshIntervalHours: refreshIntervalHours.present
        ? refreshIntervalHours.value
        : this.refreshIntervalHours,
    lastRefreshedAt: lastRefreshedAt.present
        ? lastRefreshedAt.value
        : this.lastRefreshedAt,
    lastResult: lastResult.present ? lastResult.value : this.lastResult,
    status: status ?? this.status,
    refreshGeneration: refreshGeneration ?? this.refreshGeneration,
  );
  PlaylistRemoteRow copyWithCompanion(PlaylistRemoteTableCompanion data) {
    return PlaylistRemoteRow(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      ownerName: data.ownerName.present ? data.ownerName.value : this.ownerName,
      writable: data.writable.present ? data.writable.value : this.writable,
      nameOverridden: data.nameOverridden.present
          ? data.nameOverridden.value
          : this.nameOverridden,
      descriptionOverridden: data.descriptionOverridden.present
          ? data.descriptionOverridden.value
          : this.descriptionOverridden,
      artworkOverridden: data.artworkOverridden.present
          ? data.artworkOverridden.value
          : this.artworkOverridden,
      refreshIntervalHours: data.refreshIntervalHours.present
          ? data.refreshIntervalHours.value
          : this.refreshIntervalHours,
      lastRefreshedAt: data.lastRefreshedAt.present
          ? data.lastRefreshedAt.value
          : this.lastRefreshedAt,
      lastResult: data.lastResult.present
          ? data.lastResult.value
          : this.lastResult,
      status: data.status.present ? data.status.value : this.status,
      refreshGeneration: data.refreshGeneration.present
          ? data.refreshGeneration.value
          : this.refreshGeneration,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRemoteRow(')
          ..write('playlistId: $playlistId, ')
          ..write('pluginId: $pluginId, ')
          ..write('remoteId: $remoteId, ')
          ..write('ownerName: $ownerName, ')
          ..write('writable: $writable, ')
          ..write('nameOverridden: $nameOverridden, ')
          ..write('descriptionOverridden: $descriptionOverridden, ')
          ..write('artworkOverridden: $artworkOverridden, ')
          ..write('refreshIntervalHours: $refreshIntervalHours, ')
          ..write('lastRefreshedAt: $lastRefreshedAt, ')
          ..write('lastResult: $lastResult, ')
          ..write('status: $status, ')
          ..write('refreshGeneration: $refreshGeneration')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    playlistId,
    pluginId,
    remoteId,
    ownerName,
    writable,
    nameOverridden,
    descriptionOverridden,
    artworkOverridden,
    refreshIntervalHours,
    lastRefreshedAt,
    lastResult,
    status,
    refreshGeneration,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistRemoteRow &&
          other.playlistId == this.playlistId &&
          other.pluginId == this.pluginId &&
          other.remoteId == this.remoteId &&
          other.ownerName == this.ownerName &&
          other.writable == this.writable &&
          other.nameOverridden == this.nameOverridden &&
          other.descriptionOverridden == this.descriptionOverridden &&
          other.artworkOverridden == this.artworkOverridden &&
          other.refreshIntervalHours == this.refreshIntervalHours &&
          other.lastRefreshedAt == this.lastRefreshedAt &&
          other.lastResult == this.lastResult &&
          other.status == this.status &&
          other.refreshGeneration == this.refreshGeneration);
}

class PlaylistRemoteTableCompanion extends UpdateCompanion<PlaylistRemoteRow> {
  final Value<int> playlistId;
  final Value<String> pluginId;
  final Value<String> remoteId;
  final Value<String?> ownerName;
  final Value<bool> writable;
  final Value<bool> nameOverridden;
  final Value<bool> descriptionOverridden;
  final Value<bool> artworkOverridden;
  final Value<int?> refreshIntervalHours;
  final Value<DateTime?> lastRefreshedAt;
  final Value<PlaylistRefreshResult?> lastResult;
  final Value<PlaylistRemoteStatus> status;
  final Value<int> refreshGeneration;
  const PlaylistRemoteTableCompanion({
    this.playlistId = const Value.absent(),
    this.pluginId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.ownerName = const Value.absent(),
    this.writable = const Value.absent(),
    this.nameOverridden = const Value.absent(),
    this.descriptionOverridden = const Value.absent(),
    this.artworkOverridden = const Value.absent(),
    this.refreshIntervalHours = const Value.absent(),
    this.lastRefreshedAt = const Value.absent(),
    this.lastResult = const Value.absent(),
    this.status = const Value.absent(),
    this.refreshGeneration = const Value.absent(),
  });
  PlaylistRemoteTableCompanion.insert({
    this.playlistId = const Value.absent(),
    required String pluginId,
    required String remoteId,
    this.ownerName = const Value.absent(),
    this.writable = const Value.absent(),
    this.nameOverridden = const Value.absent(),
    this.descriptionOverridden = const Value.absent(),
    this.artworkOverridden = const Value.absent(),
    this.refreshIntervalHours = const Value.absent(),
    this.lastRefreshedAt = const Value.absent(),
    this.lastResult = const Value.absent(),
    this.status = const Value.absent(),
    this.refreshGeneration = const Value.absent(),
  }) : pluginId = Value(pluginId),
       remoteId = Value(remoteId);
  static Insertable<PlaylistRemoteRow> custom({
    Expression<int>? playlistId,
    Expression<String>? pluginId,
    Expression<String>? remoteId,
    Expression<String>? ownerName,
    Expression<bool>? writable,
    Expression<bool>? nameOverridden,
    Expression<bool>? descriptionOverridden,
    Expression<bool>? artworkOverridden,
    Expression<int>? refreshIntervalHours,
    Expression<int>? lastRefreshedAt,
    Expression<String>? lastResult,
    Expression<String>? status,
    Expression<int>? refreshGeneration,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (pluginId != null) 'plugin_id': pluginId,
      if (remoteId != null) 'remote_id': remoteId,
      if (ownerName != null) 'owner_name': ownerName,
      if (writable != null) 'writable': writable,
      if (nameOverridden != null) 'name_overridden': nameOverridden,
      if (descriptionOverridden != null)
        'description_overridden': descriptionOverridden,
      if (artworkOverridden != null) 'artwork_overridden': artworkOverridden,
      if (refreshIntervalHours != null)
        'refresh_interval_hours': refreshIntervalHours,
      if (lastRefreshedAt != null) 'last_refreshed_at': lastRefreshedAt,
      if (lastResult != null) 'last_result': lastResult,
      if (status != null) 'status': status,
      if (refreshGeneration != null) 'refresh_generation': refreshGeneration,
    });
  }

  PlaylistRemoteTableCompanion copyWith({
    Value<int>? playlistId,
    Value<String>? pluginId,
    Value<String>? remoteId,
    Value<String?>? ownerName,
    Value<bool>? writable,
    Value<bool>? nameOverridden,
    Value<bool>? descriptionOverridden,
    Value<bool>? artworkOverridden,
    Value<int?>? refreshIntervalHours,
    Value<DateTime?>? lastRefreshedAt,
    Value<PlaylistRefreshResult?>? lastResult,
    Value<PlaylistRemoteStatus>? status,
    Value<int>? refreshGeneration,
  }) {
    return PlaylistRemoteTableCompanion(
      playlistId: playlistId ?? this.playlistId,
      pluginId: pluginId ?? this.pluginId,
      remoteId: remoteId ?? this.remoteId,
      ownerName: ownerName ?? this.ownerName,
      writable: writable ?? this.writable,
      nameOverridden: nameOverridden ?? this.nameOverridden,
      descriptionOverridden:
          descriptionOverridden ?? this.descriptionOverridden,
      artworkOverridden: artworkOverridden ?? this.artworkOverridden,
      refreshIntervalHours: refreshIntervalHours ?? this.refreshIntervalHours,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      lastResult: lastResult ?? this.lastResult,
      status: status ?? this.status,
      refreshGeneration: refreshGeneration ?? this.refreshGeneration,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (ownerName.present) {
      map['owner_name'] = Variable<String>(ownerName.value);
    }
    if (writable.present) {
      map['writable'] = Variable<bool>(writable.value);
    }
    if (nameOverridden.present) {
      map['name_overridden'] = Variable<bool>(nameOverridden.value);
    }
    if (descriptionOverridden.present) {
      map['description_overridden'] = Variable<bool>(
        descriptionOverridden.value,
      );
    }
    if (artworkOverridden.present) {
      map['artwork_overridden'] = Variable<bool>(artworkOverridden.value);
    }
    if (refreshIntervalHours.present) {
      map['refresh_interval_hours'] = Variable<int>(refreshIntervalHours.value);
    }
    if (lastRefreshedAt.present) {
      map['last_refreshed_at'] = Variable<int>(
        $PlaylistRemoteTableTable.$converterlastRefreshedAtn.toSql(
          lastRefreshedAt.value,
        ),
      );
    }
    if (lastResult.present) {
      map['last_result'] = Variable<String>(
        $PlaylistRemoteTableTable.$converterlastResultn.toSql(lastResult.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $PlaylistRemoteTableTable.$converterstatus.toSql(status.value),
      );
    }
    if (refreshGeneration.present) {
      map['refresh_generation'] = Variable<int>(refreshGeneration.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistRemoteTableCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('pluginId: $pluginId, ')
          ..write('remoteId: $remoteId, ')
          ..write('ownerName: $ownerName, ')
          ..write('writable: $writable, ')
          ..write('nameOverridden: $nameOverridden, ')
          ..write('descriptionOverridden: $descriptionOverridden, ')
          ..write('artworkOverridden: $artworkOverridden, ')
          ..write('refreshIntervalHours: $refreshIntervalHours, ')
          ..write('lastRefreshedAt: $lastRefreshedAt, ')
          ..write('lastResult: $lastResult, ')
          ..write('status: $status, ')
          ..write('refreshGeneration: $refreshGeneration')
          ..write(')'))
        .toString();
  }
}

class $ChartSettingsTableTable extends ChartSettingsTable
    with TableInfo<$ChartSettingsTableTable, ChartSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChartSettingsTableTable(this.attachedDatabase, [this._alias]);
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
  );
  static const VerificationMeta _chartIdMeta = const VerificationMeta(
    'chartId',
  );
  @override
  late final GeneratedColumn<String> chartId = GeneratedColumn<String>(
    'chart_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [pluginId, chartId, enabled, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chart_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChartSettingsRow> instance, {
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
    if (data.containsKey('chart_id')) {
      context.handle(
        _chartIdMeta,
        chartId.isAcceptableOrUnknown(data['chart_id']!, _chartIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chartIdMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pluginId, chartId};
  @override
  ChartSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChartSettingsRow(
      pluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plugin_id'],
      )!,
      chartId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chart_id'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
    );
  }

  @override
  $ChartSettingsTableTable createAlias(String alias) {
    return $ChartSettingsTableTable(attachedDatabase, alias);
  }
}

class ChartSettingsRow extends DataClass
    implements Insertable<ChartSettingsRow> {
  final String pluginId;
  final String chartId;
  final bool? enabled;
  final int? sortOrder;
  const ChartSettingsRow({
    required this.pluginId,
    required this.chartId,
    this.enabled,
    this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['plugin_id'] = Variable<String>(pluginId);
    map['chart_id'] = Variable<String>(chartId);
    if (!nullToAbsent || enabled != null) {
      map['enabled'] = Variable<bool>(enabled);
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    return map;
  }

  ChartSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return ChartSettingsTableCompanion(
      pluginId: Value(pluginId),
      chartId: Value(chartId),
      enabled: enabled == null && nullToAbsent
          ? const Value.absent()
          : Value(enabled),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
    );
  }

  factory ChartSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChartSettingsRow(
      pluginId: serializer.fromJson<String>(json['pluginId']),
      chartId: serializer.fromJson<String>(json['chartId']),
      enabled: serializer.fromJson<bool?>(json['enabled']),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pluginId': serializer.toJson<String>(pluginId),
      'chartId': serializer.toJson<String>(chartId),
      'enabled': serializer.toJson<bool?>(enabled),
      'sortOrder': serializer.toJson<int?>(sortOrder),
    };
  }

  ChartSettingsRow copyWith({
    String? pluginId,
    String? chartId,
    Value<bool?> enabled = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
  }) => ChartSettingsRow(
    pluginId: pluginId ?? this.pluginId,
    chartId: chartId ?? this.chartId,
    enabled: enabled.present ? enabled.value : this.enabled,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
  );
  ChartSettingsRow copyWithCompanion(ChartSettingsTableCompanion data) {
    return ChartSettingsRow(
      pluginId: data.pluginId.present ? data.pluginId.value : this.pluginId,
      chartId: data.chartId.present ? data.chartId.value : this.chartId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChartSettingsRow(')
          ..write('pluginId: $pluginId, ')
          ..write('chartId: $chartId, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pluginId, chartId, enabled, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChartSettingsRow &&
          other.pluginId == this.pluginId &&
          other.chartId == this.chartId &&
          other.enabled == this.enabled &&
          other.sortOrder == this.sortOrder);
}

class ChartSettingsTableCompanion extends UpdateCompanion<ChartSettingsRow> {
  final Value<String> pluginId;
  final Value<String> chartId;
  final Value<bool?> enabled;
  final Value<int?> sortOrder;
  final Value<int> rowid;
  const ChartSettingsTableCompanion({
    this.pluginId = const Value.absent(),
    this.chartId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChartSettingsTableCompanion.insert({
    required String pluginId,
    required String chartId,
    this.enabled = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pluginId = Value(pluginId),
       chartId = Value(chartId);
  static Insertable<ChartSettingsRow> custom({
    Expression<String>? pluginId,
    Expression<String>? chartId,
    Expression<bool>? enabled,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pluginId != null) 'plugin_id': pluginId,
      if (chartId != null) 'chart_id': chartId,
      if (enabled != null) 'enabled': enabled,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChartSettingsTableCompanion copyWith({
    Value<String>? pluginId,
    Value<String>? chartId,
    Value<bool?>? enabled,
    Value<int?>? sortOrder,
    Value<int>? rowid,
  }) {
    return ChartSettingsTableCompanion(
      pluginId: pluginId ?? this.pluginId,
      chartId: chartId ?? this.chartId,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pluginId.present) {
      map['plugin_id'] = Variable<String>(pluginId.value);
    }
    if (chartId.present) {
      map['chart_id'] = Variable<String>(chartId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChartSettingsTableCompanion(')
          ..write('pluginId: $pluginId, ')
          ..write('chartId: $chartId, ')
          ..write('enabled: $enabled, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MatchResultsTableTable extends MatchResultsTable
    with TableInfo<$MatchResultsTableTable, MatchResultRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MatchResultsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _originPluginIdMeta = const VerificationMeta(
    'originPluginId',
  );
  @override
  late final GeneratedColumn<String> originPluginId = GeneratedColumn<String>(
    'origin_plugin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originIdMeta = const VerificationMeta(
    'originId',
  );
  @override
  late final GeneratedColumn<String> originId = GeneratedColumn<String>(
    'origin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistsMeta = const VerificationMeta(
    'artists',
  );
  @override
  late final GeneratedColumn<String> artists = GeneratedColumn<String>(
    'artists',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _selectedTrackKeyMeta = const VerificationMeta(
    'selectedTrackKey',
  );
  @override
  late final GeneratedColumn<String> selectedTrackKey = GeneratedColumn<String>(
    'selected_track_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (track_key) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userSelectedMeta = const VerificationMeta(
    'userSelected',
  );
  @override
  late final GeneratedColumn<bool> userSelected = GeneratedColumn<bool>(
    'user_selected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("user_selected" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    originPluginId,
    originId,
    title,
    artists,
    durationMs,
    selectedTrackKey,
    score,
    userSelected,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'match_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<MatchResultRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('origin_plugin_id')) {
      context.handle(
        _originPluginIdMeta,
        originPluginId.isAcceptableOrUnknown(
          data['origin_plugin_id']!,
          _originPluginIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originPluginIdMeta);
    }
    if (data.containsKey('origin_id')) {
      context.handle(
        _originIdMeta,
        originId.isAcceptableOrUnknown(data['origin_id']!, _originIdMeta),
      );
    } else if (isInserting) {
      context.missing(_originIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artists')) {
      context.handle(
        _artistsMeta,
        artists.isAcceptableOrUnknown(data['artists']!, _artistsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('selected_track_key')) {
      context.handle(
        _selectedTrackKeyMeta,
        selectedTrackKey.isAcceptableOrUnknown(
          data['selected_track_key']!,
          _selectedTrackKeyMeta,
        ),
      );
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    if (data.containsKey('user_selected')) {
      context.handle(
        _userSelectedMeta,
        userSelected.isAcceptableOrUnknown(
          data['user_selected']!,
          _userSelectedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {originPluginId, originId};
  @override
  MatchResultRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MatchResultRow(
      originPluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_plugin_id'],
      )!,
      originId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artists: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artists'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      selectedTrackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_track_key'],
      ),
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      ),
      userSelected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}user_selected'],
      )!,
    );
  }

  @override
  $MatchResultsTableTable createAlias(String alias) {
    return $MatchResultsTableTable(attachedDatabase, alias);
  }
}

class MatchResultRow extends DataClass implements Insertable<MatchResultRow> {
  final String originPluginId;
  final String originId;
  final String title;
  final String? artists;
  final int? durationMs;
  final String? selectedTrackKey;
  final double? score;
  final bool userSelected;
  const MatchResultRow({
    required this.originPluginId,
    required this.originId,
    required this.title,
    this.artists,
    this.durationMs,
    this.selectedTrackKey,
    this.score,
    required this.userSelected,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['origin_plugin_id'] = Variable<String>(originPluginId);
    map['origin_id'] = Variable<String>(originId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || artists != null) {
      map['artists'] = Variable<String>(artists);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || selectedTrackKey != null) {
      map['selected_track_key'] = Variable<String>(selectedTrackKey);
    }
    if (!nullToAbsent || score != null) {
      map['score'] = Variable<double>(score);
    }
    map['user_selected'] = Variable<bool>(userSelected);
    return map;
  }

  MatchResultsTableCompanion toCompanion(bool nullToAbsent) {
    return MatchResultsTableCompanion(
      originPluginId: Value(originPluginId),
      originId: Value(originId),
      title: Value(title),
      artists: artists == null && nullToAbsent
          ? const Value.absent()
          : Value(artists),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      selectedTrackKey: selectedTrackKey == null && nullToAbsent
          ? const Value.absent()
          : Value(selectedTrackKey),
      score: score == null && nullToAbsent
          ? const Value.absent()
          : Value(score),
      userSelected: Value(userSelected),
    );
  }

  factory MatchResultRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MatchResultRow(
      originPluginId: serializer.fromJson<String>(json['originPluginId']),
      originId: serializer.fromJson<String>(json['originId']),
      title: serializer.fromJson<String>(json['title']),
      artists: serializer.fromJson<String?>(json['artists']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      selectedTrackKey: serializer.fromJson<String?>(json['selectedTrackKey']),
      score: serializer.fromJson<double?>(json['score']),
      userSelected: serializer.fromJson<bool>(json['userSelected']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'originPluginId': serializer.toJson<String>(originPluginId),
      'originId': serializer.toJson<String>(originId),
      'title': serializer.toJson<String>(title),
      'artists': serializer.toJson<String?>(artists),
      'durationMs': serializer.toJson<int?>(durationMs),
      'selectedTrackKey': serializer.toJson<String?>(selectedTrackKey),
      'score': serializer.toJson<double?>(score),
      'userSelected': serializer.toJson<bool>(userSelected),
    };
  }

  MatchResultRow copyWith({
    String? originPluginId,
    String? originId,
    String? title,
    Value<String?> artists = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> selectedTrackKey = const Value.absent(),
    Value<double?> score = const Value.absent(),
    bool? userSelected,
  }) => MatchResultRow(
    originPluginId: originPluginId ?? this.originPluginId,
    originId: originId ?? this.originId,
    title: title ?? this.title,
    artists: artists.present ? artists.value : this.artists,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    selectedTrackKey: selectedTrackKey.present
        ? selectedTrackKey.value
        : this.selectedTrackKey,
    score: score.present ? score.value : this.score,
    userSelected: userSelected ?? this.userSelected,
  );
  MatchResultRow copyWithCompanion(MatchResultsTableCompanion data) {
    return MatchResultRow(
      originPluginId: data.originPluginId.present
          ? data.originPluginId.value
          : this.originPluginId,
      originId: data.originId.present ? data.originId.value : this.originId,
      title: data.title.present ? data.title.value : this.title,
      artists: data.artists.present ? data.artists.value : this.artists,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      selectedTrackKey: data.selectedTrackKey.present
          ? data.selectedTrackKey.value
          : this.selectedTrackKey,
      score: data.score.present ? data.score.value : this.score,
      userSelected: data.userSelected.present
          ? data.userSelected.value
          : this.userSelected,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MatchResultRow(')
          ..write('originPluginId: $originPluginId, ')
          ..write('originId: $originId, ')
          ..write('title: $title, ')
          ..write('artists: $artists, ')
          ..write('durationMs: $durationMs, ')
          ..write('selectedTrackKey: $selectedTrackKey, ')
          ..write('score: $score, ')
          ..write('userSelected: $userSelected')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    originPluginId,
    originId,
    title,
    artists,
    durationMs,
    selectedTrackKey,
    score,
    userSelected,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MatchResultRow &&
          other.originPluginId == this.originPluginId &&
          other.originId == this.originId &&
          other.title == this.title &&
          other.artists == this.artists &&
          other.durationMs == this.durationMs &&
          other.selectedTrackKey == this.selectedTrackKey &&
          other.score == this.score &&
          other.userSelected == this.userSelected);
}

class MatchResultsTableCompanion extends UpdateCompanion<MatchResultRow> {
  final Value<String> originPluginId;
  final Value<String> originId;
  final Value<String> title;
  final Value<String?> artists;
  final Value<int?> durationMs;
  final Value<String?> selectedTrackKey;
  final Value<double?> score;
  final Value<bool> userSelected;
  final Value<int> rowid;
  const MatchResultsTableCompanion({
    this.originPluginId = const Value.absent(),
    this.originId = const Value.absent(),
    this.title = const Value.absent(),
    this.artists = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.selectedTrackKey = const Value.absent(),
    this.score = const Value.absent(),
    this.userSelected = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MatchResultsTableCompanion.insert({
    required String originPluginId,
    required String originId,
    required String title,
    this.artists = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.selectedTrackKey = const Value.absent(),
    this.score = const Value.absent(),
    this.userSelected = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : originPluginId = Value(originPluginId),
       originId = Value(originId),
       title = Value(title);
  static Insertable<MatchResultRow> custom({
    Expression<String>? originPluginId,
    Expression<String>? originId,
    Expression<String>? title,
    Expression<String>? artists,
    Expression<int>? durationMs,
    Expression<String>? selectedTrackKey,
    Expression<double>? score,
    Expression<bool>? userSelected,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (originPluginId != null) 'origin_plugin_id': originPluginId,
      if (originId != null) 'origin_id': originId,
      if (title != null) 'title': title,
      if (artists != null) 'artists': artists,
      if (durationMs != null) 'duration_ms': durationMs,
      if (selectedTrackKey != null) 'selected_track_key': selectedTrackKey,
      if (score != null) 'score': score,
      if (userSelected != null) 'user_selected': userSelected,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MatchResultsTableCompanion copyWith({
    Value<String>? originPluginId,
    Value<String>? originId,
    Value<String>? title,
    Value<String?>? artists,
    Value<int?>? durationMs,
    Value<String?>? selectedTrackKey,
    Value<double?>? score,
    Value<bool>? userSelected,
    Value<int>? rowid,
  }) {
    return MatchResultsTableCompanion(
      originPluginId: originPluginId ?? this.originPluginId,
      originId: originId ?? this.originId,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      durationMs: durationMs ?? this.durationMs,
      selectedTrackKey: selectedTrackKey ?? this.selectedTrackKey,
      score: score ?? this.score,
      userSelected: userSelected ?? this.userSelected,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (originPluginId.present) {
      map['origin_plugin_id'] = Variable<String>(originPluginId.value);
    }
    if (originId.present) {
      map['origin_id'] = Variable<String>(originId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artists.present) {
      map['artists'] = Variable<String>(artists.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (selectedTrackKey.present) {
      map['selected_track_key'] = Variable<String>(selectedTrackKey.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (userSelected.present) {
      map['user_selected'] = Variable<bool>(userSelected.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MatchResultsTableCompanion(')
          ..write('originPluginId: $originPluginId, ')
          ..write('originId: $originId, ')
          ..write('title: $title, ')
          ..write('artists: $artists, ')
          ..write('durationMs: $durationMs, ')
          ..write('selectedTrackKey: $selectedTrackKey, ')
          ..write('score: $score, ')
          ..write('userSelected: $userSelected, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrackOriginsTableTable extends TrackOriginsTable
    with TableInfo<$TrackOriginsTableTable, TrackOriginRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackOriginsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (track_key) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _originPluginIdMeta = const VerificationMeta(
    'originPluginId',
  );
  @override
  late final GeneratedColumn<String> originPluginId = GeneratedColumn<String>(
    'origin_plugin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originIdMeta = const VerificationMeta(
    'originId',
  );
  @override
  late final GeneratedColumn<String> originId = GeneratedColumn<String>(
    'origin_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [trackKey, originPluginId, originId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_origins';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackOriginRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    if (data.containsKey('origin_plugin_id')) {
      context.handle(
        _originPluginIdMeta,
        originPluginId.isAcceptableOrUnknown(
          data['origin_plugin_id']!,
          _originPluginIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originPluginIdMeta);
    }
    if (data.containsKey('origin_id')) {
      context.handle(
        _originIdMeta,
        originId.isAcceptableOrUnknown(data['origin_id']!, _originIdMeta),
      );
    } else if (isInserting) {
      context.missing(_originIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackKey, originPluginId};
  @override
  TrackOriginRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackOriginRow(
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      originPluginId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_plugin_id'],
      )!,
      originId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin_id'],
      )!,
    );
  }

  @override
  $TrackOriginsTableTable createAlias(String alias) {
    return $TrackOriginsTableTable(attachedDatabase, alias);
  }
}

class TrackOriginRow extends DataClass implements Insertable<TrackOriginRow> {
  final String trackKey;
  final String originPluginId;
  final String originId;
  const TrackOriginRow({
    required this.trackKey,
    required this.originPluginId,
    required this.originId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_key'] = Variable<String>(trackKey);
    map['origin_plugin_id'] = Variable<String>(originPluginId);
    map['origin_id'] = Variable<String>(originId);
    return map;
  }

  TrackOriginsTableCompanion toCompanion(bool nullToAbsent) {
    return TrackOriginsTableCompanion(
      trackKey: Value(trackKey),
      originPluginId: Value(originPluginId),
      originId: Value(originId),
    );
  }

  factory TrackOriginRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackOriginRow(
      trackKey: serializer.fromJson<String>(json['trackKey']),
      originPluginId: serializer.fromJson<String>(json['originPluginId']),
      originId: serializer.fromJson<String>(json['originId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackKey': serializer.toJson<String>(trackKey),
      'originPluginId': serializer.toJson<String>(originPluginId),
      'originId': serializer.toJson<String>(originId),
    };
  }

  TrackOriginRow copyWith({
    String? trackKey,
    String? originPluginId,
    String? originId,
  }) => TrackOriginRow(
    trackKey: trackKey ?? this.trackKey,
    originPluginId: originPluginId ?? this.originPluginId,
    originId: originId ?? this.originId,
  );
  TrackOriginRow copyWithCompanion(TrackOriginsTableCompanion data) {
    return TrackOriginRow(
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      originPluginId: data.originPluginId.present
          ? data.originPluginId.value
          : this.originPluginId,
      originId: data.originId.present ? data.originId.value : this.originId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackOriginRow(')
          ..write('trackKey: $trackKey, ')
          ..write('originPluginId: $originPluginId, ')
          ..write('originId: $originId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(trackKey, originPluginId, originId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackOriginRow &&
          other.trackKey == this.trackKey &&
          other.originPluginId == this.originPluginId &&
          other.originId == this.originId);
}

class TrackOriginsTableCompanion extends UpdateCompanion<TrackOriginRow> {
  final Value<String> trackKey;
  final Value<String> originPluginId;
  final Value<String> originId;
  final Value<int> rowid;
  const TrackOriginsTableCompanion({
    this.trackKey = const Value.absent(),
    this.originPluginId = const Value.absent(),
    this.originId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrackOriginsTableCompanion.insert({
    required String trackKey,
    required String originPluginId,
    required String originId,
    this.rowid = const Value.absent(),
  }) : trackKey = Value(trackKey),
       originPluginId = Value(originPluginId),
       originId = Value(originId);
  static Insertable<TrackOriginRow> custom({
    Expression<String>? trackKey,
    Expression<String>? originPluginId,
    Expression<String>? originId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackKey != null) 'track_key': trackKey,
      if (originPluginId != null) 'origin_plugin_id': originPluginId,
      if (originId != null) 'origin_id': originId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrackOriginsTableCompanion copyWith({
    Value<String>? trackKey,
    Value<String>? originPluginId,
    Value<String>? originId,
    Value<int>? rowid,
  }) {
    return TrackOriginsTableCompanion(
      trackKey: trackKey ?? this.trackKey,
      originPluginId: originPluginId ?? this.originPluginId,
      originId: originId ?? this.originId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (originPluginId.present) {
      map['origin_plugin_id'] = Variable<String>(originPluginId.value);
    }
    if (originId.present) {
      map['origin_id'] = Variable<String>(originId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackOriginsTableCompanion(')
          ..write('trackKey: $trackKey, ')
          ..write('originPluginId: $originPluginId, ')
          ..write('originId: $originId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LegacyImportsTableTable extends LegacyImportsTable
    with TableInfo<$LegacyImportsTableTable, LegacyImportRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LegacyImportsTableTable(this.attachedDatabase, [this._alias]);
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
  @override
  late final GeneratedColumnWithTypeConverter<LegacyImportSource, String>
  source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<LegacyImportSource>(
        $LegacyImportsTableTable.$convertersource,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DateTime, int> importedAt =
      GeneratedColumn<int>(
        'imported_at',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DateTime>($LegacyImportsTableTable.$converterimportedAt);
  static const VerificationMeta _legacySchemaVersionMeta =
      const VerificationMeta('legacySchemaVersion');
  @override
  late final GeneratedColumn<int> legacySchemaVersion = GeneratedColumn<int>(
    'legacy_schema_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backupVersionMeta = const VerificationMeta(
    'backupVersion',
  );
  @override
  late final GeneratedColumn<int> backupVersion = GeneratedColumn<int>(
    'backup_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryJsonMeta = const VerificationMeta(
    'summaryJson',
  );
  @override
  late final GeneratedColumn<String> summaryJson = GeneratedColumn<String>(
    'summary_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acknowledgedMeta = const VerificationMeta(
    'acknowledged',
  );
  @override
  late final GeneratedColumn<bool> acknowledged = GeneratedColumn<bool>(
    'acknowledged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("acknowledged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    source,
    importedAt,
    legacySchemaVersion,
    backupVersion,
    summaryJson,
    acknowledged,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'legacy_imports';
  @override
  VerificationContext validateIntegrity(
    Insertable<LegacyImportRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('legacy_schema_version')) {
      context.handle(
        _legacySchemaVersionMeta,
        legacySchemaVersion.isAcceptableOrUnknown(
          data['legacy_schema_version']!,
          _legacySchemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('backup_version')) {
      context.handle(
        _backupVersionMeta,
        backupVersion.isAcceptableOrUnknown(
          data['backup_version']!,
          _backupVersionMeta,
        ),
      );
    }
    if (data.containsKey('summary_json')) {
      context.handle(
        _summaryJsonMeta,
        summaryJson.isAcceptableOrUnknown(
          data['summary_json']!,
          _summaryJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_summaryJsonMeta);
    }
    if (data.containsKey('acknowledged')) {
      context.handle(
        _acknowledgedMeta,
        acknowledged.isAcceptableOrUnknown(
          data['acknowledged']!,
          _acknowledgedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LegacyImportRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LegacyImportRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      source: $LegacyImportsTableTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      importedAt: $LegacyImportsTableTable.$converterimportedAt.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}imported_at'],
        )!,
      ),
      legacySchemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}legacy_schema_version'],
      ),
      backupVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}backup_version'],
      ),
      summaryJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary_json'],
      )!,
      acknowledged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}acknowledged'],
      )!,
    );
  }

  @override
  $LegacyImportsTableTable createAlias(String alias) {
    return $LegacyImportsTableTable(attachedDatabase, alias);
  }

  static TypeConverter<LegacyImportSource, String> $convertersource =
      const LegacyImportSourceConverter();
  static TypeConverter<DateTime, int> $converterimportedAt =
      const EpochMillisecondsConverter();
}

class LegacyImportRow extends DataClass implements Insertable<LegacyImportRow> {
  final int id;
  final LegacyImportSource source;
  final DateTime importedAt;

  /// 舊 `Settings.schemaVersion`（資料庫來源）；備份來源為空。
  final int? legacySchemaVersion;

  /// 備份檔的 `version`（備份來源）；資料庫來源為空。
  final int? backupVersion;
  final String summaryJson;
  final bool acknowledged;
  const LegacyImportRow({
    required this.id,
    required this.source,
    required this.importedAt,
    this.legacySchemaVersion,
    this.backupVersion,
    required this.summaryJson,
    required this.acknowledged,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['source'] = Variable<String>(
        $LegacyImportsTableTable.$convertersource.toSql(source),
      );
    }
    {
      map['imported_at'] = Variable<int>(
        $LegacyImportsTableTable.$converterimportedAt.toSql(importedAt),
      );
    }
    if (!nullToAbsent || legacySchemaVersion != null) {
      map['legacy_schema_version'] = Variable<int>(legacySchemaVersion);
    }
    if (!nullToAbsent || backupVersion != null) {
      map['backup_version'] = Variable<int>(backupVersion);
    }
    map['summary_json'] = Variable<String>(summaryJson);
    map['acknowledged'] = Variable<bool>(acknowledged);
    return map;
  }

  LegacyImportsTableCompanion toCompanion(bool nullToAbsent) {
    return LegacyImportsTableCompanion(
      id: Value(id),
      source: Value(source),
      importedAt: Value(importedAt),
      legacySchemaVersion: legacySchemaVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(legacySchemaVersion),
      backupVersion: backupVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(backupVersion),
      summaryJson: Value(summaryJson),
      acknowledged: Value(acknowledged),
    );
  }

  factory LegacyImportRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LegacyImportRow(
      id: serializer.fromJson<int>(json['id']),
      source: serializer.fromJson<LegacyImportSource>(json['source']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
      legacySchemaVersion: serializer.fromJson<int?>(
        json['legacySchemaVersion'],
      ),
      backupVersion: serializer.fromJson<int?>(json['backupVersion']),
      summaryJson: serializer.fromJson<String>(json['summaryJson']),
      acknowledged: serializer.fromJson<bool>(json['acknowledged']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'source': serializer.toJson<LegacyImportSource>(source),
      'importedAt': serializer.toJson<DateTime>(importedAt),
      'legacySchemaVersion': serializer.toJson<int?>(legacySchemaVersion),
      'backupVersion': serializer.toJson<int?>(backupVersion),
      'summaryJson': serializer.toJson<String>(summaryJson),
      'acknowledged': serializer.toJson<bool>(acknowledged),
    };
  }

  LegacyImportRow copyWith({
    int? id,
    LegacyImportSource? source,
    DateTime? importedAt,
    Value<int?> legacySchemaVersion = const Value.absent(),
    Value<int?> backupVersion = const Value.absent(),
    String? summaryJson,
    bool? acknowledged,
  }) => LegacyImportRow(
    id: id ?? this.id,
    source: source ?? this.source,
    importedAt: importedAt ?? this.importedAt,
    legacySchemaVersion: legacySchemaVersion.present
        ? legacySchemaVersion.value
        : this.legacySchemaVersion,
    backupVersion: backupVersion.present
        ? backupVersion.value
        : this.backupVersion,
    summaryJson: summaryJson ?? this.summaryJson,
    acknowledged: acknowledged ?? this.acknowledged,
  );
  LegacyImportRow copyWithCompanion(LegacyImportsTableCompanion data) {
    return LegacyImportRow(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      legacySchemaVersion: data.legacySchemaVersion.present
          ? data.legacySchemaVersion.value
          : this.legacySchemaVersion,
      backupVersion: data.backupVersion.present
          ? data.backupVersion.value
          : this.backupVersion,
      summaryJson: data.summaryJson.present
          ? data.summaryJson.value
          : this.summaryJson,
      acknowledged: data.acknowledged.present
          ? data.acknowledged.value
          : this.acknowledged,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LegacyImportRow(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('importedAt: $importedAt, ')
          ..write('legacySchemaVersion: $legacySchemaVersion, ')
          ..write('backupVersion: $backupVersion, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('acknowledged: $acknowledged')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    source,
    importedAt,
    legacySchemaVersion,
    backupVersion,
    summaryJson,
    acknowledged,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LegacyImportRow &&
          other.id == this.id &&
          other.source == this.source &&
          other.importedAt == this.importedAt &&
          other.legacySchemaVersion == this.legacySchemaVersion &&
          other.backupVersion == this.backupVersion &&
          other.summaryJson == this.summaryJson &&
          other.acknowledged == this.acknowledged);
}

class LegacyImportsTableCompanion extends UpdateCompanion<LegacyImportRow> {
  final Value<int> id;
  final Value<LegacyImportSource> source;
  final Value<DateTime> importedAt;
  final Value<int?> legacySchemaVersion;
  final Value<int?> backupVersion;
  final Value<String> summaryJson;
  final Value<bool> acknowledged;
  const LegacyImportsTableCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.legacySchemaVersion = const Value.absent(),
    this.backupVersion = const Value.absent(),
    this.summaryJson = const Value.absent(),
    this.acknowledged = const Value.absent(),
  });
  LegacyImportsTableCompanion.insert({
    this.id = const Value.absent(),
    required LegacyImportSource source,
    required DateTime importedAt,
    this.legacySchemaVersion = const Value.absent(),
    this.backupVersion = const Value.absent(),
    required String summaryJson,
    this.acknowledged = const Value.absent(),
  }) : source = Value(source),
       importedAt = Value(importedAt),
       summaryJson = Value(summaryJson);
  static Insertable<LegacyImportRow> custom({
    Expression<int>? id,
    Expression<String>? source,
    Expression<int>? importedAt,
    Expression<int>? legacySchemaVersion,
    Expression<int>? backupVersion,
    Expression<String>? summaryJson,
    Expression<bool>? acknowledged,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (importedAt != null) 'imported_at': importedAt,
      if (legacySchemaVersion != null)
        'legacy_schema_version': legacySchemaVersion,
      if (backupVersion != null) 'backup_version': backupVersion,
      if (summaryJson != null) 'summary_json': summaryJson,
      if (acknowledged != null) 'acknowledged': acknowledged,
    });
  }

  LegacyImportsTableCompanion copyWith({
    Value<int>? id,
    Value<LegacyImportSource>? source,
    Value<DateTime>? importedAt,
    Value<int?>? legacySchemaVersion,
    Value<int?>? backupVersion,
    Value<String>? summaryJson,
    Value<bool>? acknowledged,
  }) {
    return LegacyImportsTableCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      importedAt: importedAt ?? this.importedAt,
      legacySchemaVersion: legacySchemaVersion ?? this.legacySchemaVersion,
      backupVersion: backupVersion ?? this.backupVersion,
      summaryJson: summaryJson ?? this.summaryJson,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $LegacyImportsTableTable.$convertersource.toSql(source.value),
      );
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(
        $LegacyImportsTableTable.$converterimportedAt.toSql(importedAt.value),
      );
    }
    if (legacySchemaVersion.present) {
      map['legacy_schema_version'] = Variable<int>(legacySchemaVersion.value);
    }
    if (backupVersion.present) {
      map['backup_version'] = Variable<int>(backupVersion.value);
    }
    if (summaryJson.present) {
      map['summary_json'] = Variable<String>(summaryJson.value);
    }
    if (acknowledged.present) {
      map['acknowledged'] = Variable<bool>(acknowledged.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LegacyImportsTableCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('importedAt: $importedAt, ')
          ..write('legacySchemaVersion: $legacySchemaVersion, ')
          ..write('backupVersion: $backupVersion, ')
          ..write('summaryJson: $summaryJson, ')
          ..write('acknowledged: $acknowledged')
          ..write(')'))
        .toString();
  }
}

class $LegacyPlaylistIdsTableTable extends LegacyPlaylistIdsTable
    with TableInfo<$LegacyPlaylistIdsTableTable, LegacyPlaylistIdRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LegacyPlaylistIdsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _legacyImportIdMeta = const VerificationMeta(
    'legacyImportId',
  );
  @override
  late final GeneratedColumn<int> legacyImportId = GeneratedColumn<int>(
    'legacy_import_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES legacy_imports (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _legacyPlaylistIdMeta = const VerificationMeta(
    'legacyPlaylistId',
  );
  @override
  late final GeneratedColumn<int> legacyPlaylistId = GeneratedColumn<int>(
    'legacy_playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES playlists (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    legacyImportId,
    legacyPlaylistId,
    playlistId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'legacy_playlist_ids';
  @override
  VerificationContext validateIntegrity(
    Insertable<LegacyPlaylistIdRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('legacy_import_id')) {
      context.handle(
        _legacyImportIdMeta,
        legacyImportId.isAcceptableOrUnknown(
          data['legacy_import_id']!,
          _legacyImportIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_legacyImportIdMeta);
    }
    if (data.containsKey('legacy_playlist_id')) {
      context.handle(
        _legacyPlaylistIdMeta,
        legacyPlaylistId.isAcceptableOrUnknown(
          data['legacy_playlist_id']!,
          _legacyPlaylistIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_legacyPlaylistIdMeta);
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {legacyImportId, legacyPlaylistId};
  @override
  LegacyPlaylistIdRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LegacyPlaylistIdRow(
      legacyImportId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}legacy_import_id'],
      )!,
      legacyPlaylistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}legacy_playlist_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}playlist_id'],
      )!,
    );
  }

  @override
  $LegacyPlaylistIdsTableTable createAlias(String alias) {
    return $LegacyPlaylistIdsTableTable(attachedDatabase, alias);
  }
}

class LegacyPlaylistIdRow extends DataClass
    implements Insertable<LegacyPlaylistIdRow> {
  final int legacyImportId;
  final int legacyPlaylistId;
  final int playlistId;
  const LegacyPlaylistIdRow({
    required this.legacyImportId,
    required this.legacyPlaylistId,
    required this.playlistId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['legacy_import_id'] = Variable<int>(legacyImportId);
    map['legacy_playlist_id'] = Variable<int>(legacyPlaylistId);
    map['playlist_id'] = Variable<int>(playlistId);
    return map;
  }

  LegacyPlaylistIdsTableCompanion toCompanion(bool nullToAbsent) {
    return LegacyPlaylistIdsTableCompanion(
      legacyImportId: Value(legacyImportId),
      legacyPlaylistId: Value(legacyPlaylistId),
      playlistId: Value(playlistId),
    );
  }

  factory LegacyPlaylistIdRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LegacyPlaylistIdRow(
      legacyImportId: serializer.fromJson<int>(json['legacyImportId']),
      legacyPlaylistId: serializer.fromJson<int>(json['legacyPlaylistId']),
      playlistId: serializer.fromJson<int>(json['playlistId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'legacyImportId': serializer.toJson<int>(legacyImportId),
      'legacyPlaylistId': serializer.toJson<int>(legacyPlaylistId),
      'playlistId': serializer.toJson<int>(playlistId),
    };
  }

  LegacyPlaylistIdRow copyWith({
    int? legacyImportId,
    int? legacyPlaylistId,
    int? playlistId,
  }) => LegacyPlaylistIdRow(
    legacyImportId: legacyImportId ?? this.legacyImportId,
    legacyPlaylistId: legacyPlaylistId ?? this.legacyPlaylistId,
    playlistId: playlistId ?? this.playlistId,
  );
  LegacyPlaylistIdRow copyWithCompanion(LegacyPlaylistIdsTableCompanion data) {
    return LegacyPlaylistIdRow(
      legacyImportId: data.legacyImportId.present
          ? data.legacyImportId.value
          : this.legacyImportId,
      legacyPlaylistId: data.legacyPlaylistId.present
          ? data.legacyPlaylistId.value
          : this.legacyPlaylistId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LegacyPlaylistIdRow(')
          ..write('legacyImportId: $legacyImportId, ')
          ..write('legacyPlaylistId: $legacyPlaylistId, ')
          ..write('playlistId: $playlistId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(legacyImportId, legacyPlaylistId, playlistId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LegacyPlaylistIdRow &&
          other.legacyImportId == this.legacyImportId &&
          other.legacyPlaylistId == this.legacyPlaylistId &&
          other.playlistId == this.playlistId);
}

class LegacyPlaylistIdsTableCompanion
    extends UpdateCompanion<LegacyPlaylistIdRow> {
  final Value<int> legacyImportId;
  final Value<int> legacyPlaylistId;
  final Value<int> playlistId;
  final Value<int> rowid;
  const LegacyPlaylistIdsTableCompanion({
    this.legacyImportId = const Value.absent(),
    this.legacyPlaylistId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LegacyPlaylistIdsTableCompanion.insert({
    required int legacyImportId,
    required int legacyPlaylistId,
    required int playlistId,
    this.rowid = const Value.absent(),
  }) : legacyImportId = Value(legacyImportId),
       legacyPlaylistId = Value(legacyPlaylistId),
       playlistId = Value(playlistId);
  static Insertable<LegacyPlaylistIdRow> custom({
    Expression<int>? legacyImportId,
    Expression<int>? legacyPlaylistId,
    Expression<int>? playlistId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (legacyImportId != null) 'legacy_import_id': legacyImportId,
      if (legacyPlaylistId != null) 'legacy_playlist_id': legacyPlaylistId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LegacyPlaylistIdsTableCompanion copyWith({
    Value<int>? legacyImportId,
    Value<int>? legacyPlaylistId,
    Value<int>? playlistId,
    Value<int>? rowid,
  }) {
    return LegacyPlaylistIdsTableCompanion(
      legacyImportId: legacyImportId ?? this.legacyImportId,
      legacyPlaylistId: legacyPlaylistId ?? this.legacyPlaylistId,
      playlistId: playlistId ?? this.playlistId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (legacyImportId.present) {
      map['legacy_import_id'] = Variable<int>(legacyImportId.value);
    }
    if (legacyPlaylistId.present) {
      map['legacy_playlist_id'] = Variable<int>(legacyPlaylistId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LegacyPlaylistIdsTableCompanion(')
          ..write('legacyImportId: $legacyImportId, ')
          ..write('legacyPlaylistId: $legacyPlaylistId, ')
          ..write('playlistId: $playlistId, ')
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
  late final $NetworkSettingsTableTable networkSettingsTable =
      $NetworkSettingsTableTable(this);
  late final $PlaybackSettingsTableTable playbackSettingsTable =
      $PlaybackSettingsTableTable(this);
  late final $InstalledPluginsTableTable installedPluginsTable =
      $InstalledPluginsTableTable(this);
  late final $PluginIndexesTableTable pluginIndexesTable =
      $PluginIndexesTableTable(this);
  late final $PluginStorageTableTable pluginStorageTable =
      $PluginStorageTableTable(this);
  late final $TracksTableTable tracksTable = $TracksTableTable(this);
  late final $QueueEntriesTableTable queueEntriesTable =
      $QueueEntriesTableTable(this);
  late final $PlayerStateTableTable playerStateTable = $PlayerStateTableTable(
    this,
  );
  late final $PlayHistoryTableTable playHistoryTable = $PlayHistoryTableTable(
    this,
  );
  late final $LayoutStateTableTable layoutStateTable = $LayoutStateTableTable(
    this,
  );
  late final $AccountsTableTable accountsTable = $AccountsTableTable(this);
  late final $SourceSettingsTableTable sourceSettingsTable =
      $SourceSettingsTableTable(this);
  late final $DeveloperSettingsTableTable developerSettingsTable =
      $DeveloperSettingsTableTable(this);
  late final $SchedulerRunsTableTable schedulerRunsTable =
      $SchedulerRunsTableTable(this);
  late final $RadioStationsTableTable radioStationsTable =
      $RadioStationsTableTable(this);
  late final $PlaylistsTableTable playlistsTable = $PlaylistsTableTable(this);
  late final $PlaylistEntriesTableTable playlistEntriesTable =
      $PlaylistEntriesTableTable(this);
  late final $PlaylistRemoteTableTable playlistRemoteTable =
      $PlaylistRemoteTableTable(this);
  late final $ChartSettingsTableTable chartSettingsTable =
      $ChartSettingsTableTable(this);
  late final $MatchResultsTableTable matchResultsTable =
      $MatchResultsTableTable(this);
  late final $TrackOriginsTableTable trackOriginsTable =
      $TrackOriginsTableTable(this);
  late final $LegacyImportsTableTable legacyImportsTable =
      $LegacyImportsTableTable(this);
  late final $LegacyPlaylistIdsTableTable legacyPlaylistIdsTable =
      $LegacyPlaylistIdsTableTable(this);
  late final Index queueEntriesTrackKey = Index(
    'queue_entries_track_key',
    'CREATE INDEX queue_entries_track_key ON queue_entries (track_key)',
  );
  late final Index playHistoryPlayedAt = Index(
    'play_history_played_at',
    'CREATE INDEX play_history_played_at ON play_history (played_at)',
  );
  late final Index playHistoryTrackKey = Index(
    'play_history_track_key',
    'CREATE INDEX play_history_track_key ON play_history (track_key)',
  );
  late final Index playlistEntriesPlaylist = Index(
    'playlist_entries_playlist',
    'CREATE INDEX playlist_entries_playlist ON playlist_entries (playlist_id, position)',
  );
  late final Index playlistEntriesTrackKey = Index(
    'playlist_entries_track_key',
    'CREATE INDEX playlist_entries_track_key ON playlist_entries (track_key)',
  );
  late final Index matchResultsSelected = Index(
    'match_results_selected',
    'CREATE INDEX match_results_selected ON match_results (selected_track_key)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    appearanceSettingsTable,
    networkSettingsTable,
    playbackSettingsTable,
    installedPluginsTable,
    pluginIndexesTable,
    pluginStorageTable,
    tracksTable,
    queueEntriesTable,
    playerStateTable,
    playHistoryTable,
    layoutStateTable,
    accountsTable,
    sourceSettingsTable,
    developerSettingsTable,
    schedulerRunsTable,
    radioStationsTable,
    playlistsTable,
    playlistEntriesTable,
    playlistRemoteTable,
    chartSettingsTable,
    matchResultsTable,
    trackOriginsTable,
    legacyImportsTable,
    legacyPlaylistIdsTable,
    queueEntriesTrackKey,
    playHistoryPlayedAt,
    playHistoryTrackKey,
    playlistEntriesPlaylist,
    playlistEntriesTrackKey,
    matchResultsSelected,
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
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'playlists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playlist_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'playlists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playlist_remote', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tracks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('track_origins', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'legacy_imports',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('legacy_playlist_ids', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'playlists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('legacy_playlist_ids', kind: UpdateKind.delete)],
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
typedef $$NetworkSettingsTableTableCreateCompanionBuilder =
    NetworkSettingsTableCompanion Function({
      Value<int> id,
      Value<int?> cacheLimitMb,
      Value<int?> radioStatusIntervalMinutes,
      Value<int?> chartRefreshIntervalMinutes,
    });
typedef $$NetworkSettingsTableTableUpdateCompanionBuilder =
    NetworkSettingsTableCompanion Function({
      Value<int> id,
      Value<int?> cacheLimitMb,
      Value<int?> radioStatusIntervalMinutes,
      Value<int?> chartRefreshIntervalMinutes,
    });

class $$NetworkSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $NetworkSettingsTableTable> {
  $$NetworkSettingsTableTableFilterComposer({
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

  ColumnFilters<int> get cacheLimitMb => $composableBuilder(
    column: $table.cacheLimitMb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get radioStatusIntervalMinutes => $composableBuilder(
    column: $table.radioStatusIntervalMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chartRefreshIntervalMinutes => $composableBuilder(
    column: $table.chartRefreshIntervalMinutes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NetworkSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $NetworkSettingsTableTable> {
  $$NetworkSettingsTableTableOrderingComposer({
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

  ColumnOrderings<int> get cacheLimitMb => $composableBuilder(
    column: $table.cacheLimitMb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get radioStatusIntervalMinutes => $composableBuilder(
    column: $table.radioStatusIntervalMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chartRefreshIntervalMinutes => $composableBuilder(
    column: $table.chartRefreshIntervalMinutes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NetworkSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $NetworkSettingsTableTable> {
  $$NetworkSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get cacheLimitMb => $composableBuilder(
    column: $table.cacheLimitMb,
    builder: (column) => column,
  );

  GeneratedColumn<int> get radioStatusIntervalMinutes => $composableBuilder(
    column: $table.radioStatusIntervalMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chartRefreshIntervalMinutes => $composableBuilder(
    column: $table.chartRefreshIntervalMinutes,
    builder: (column) => column,
  );
}

class $$NetworkSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NetworkSettingsTableTable,
          NetworkSettingsRow,
          $$NetworkSettingsTableTableFilterComposer,
          $$NetworkSettingsTableTableOrderingComposer,
          $$NetworkSettingsTableTableAnnotationComposer,
          $$NetworkSettingsTableTableCreateCompanionBuilder,
          $$NetworkSettingsTableTableUpdateCompanionBuilder,
          (
            NetworkSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $NetworkSettingsTableTable,
              NetworkSettingsRow
            >,
          ),
          NetworkSettingsRow,
          PrefetchHooks Function()
        > {
  $$NetworkSettingsTableTableTableManager(
    _$AppDatabase db,
    $NetworkSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NetworkSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NetworkSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NetworkSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cacheLimitMb = const Value.absent(),
                Value<int?> radioStatusIntervalMinutes = const Value.absent(),
                Value<int?> chartRefreshIntervalMinutes = const Value.absent(),
              }) => NetworkSettingsTableCompanion(
                id: id,
                cacheLimitMb: cacheLimitMb,
                radioStatusIntervalMinutes: radioStatusIntervalMinutes,
                chartRefreshIntervalMinutes: chartRefreshIntervalMinutes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cacheLimitMb = const Value.absent(),
                Value<int?> radioStatusIntervalMinutes = const Value.absent(),
                Value<int?> chartRefreshIntervalMinutes = const Value.absent(),
              }) => NetworkSettingsTableCompanion.insert(
                id: id,
                cacheLimitMb: cacheLimitMb,
                radioStatusIntervalMinutes: radioStatusIntervalMinutes,
                chartRefreshIntervalMinutes: chartRefreshIntervalMinutes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NetworkSettingsTableTable, NetworkSettingsRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $NetworkSettingsTableTable,
                    NetworkSettingsRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NetworkSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NetworkSettingsTableTable,
      NetworkSettingsRow,
      $$NetworkSettingsTableTableFilterComposer,
      $$NetworkSettingsTableTableOrderingComposer,
      $$NetworkSettingsTableTableAnnotationComposer,
      $$NetworkSettingsTableTableCreateCompanionBuilder,
      $$NetworkSettingsTableTableUpdateCompanionBuilder,
      (
        NetworkSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $NetworkSettingsTableTable,
          NetworkSettingsRow
        >,
      ),
      NetworkSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$PlaybackSettingsTableTableCreateCompanionBuilder =
    PlaybackSettingsTableCompanion Function({
      Value<int> id,
      Value<AudioQuality?> audioQuality,
      Value<AudioFormatPriority?> audioFormatPriority,
      Value<bool?> rememberPosition,
      Value<int?> tempPlayRewindSeconds,
      Value<bool?> skipPreviewClips,
      Value<String?> outputDeviceId,
      Value<String?> outputDeviceName,
      Value<int?> restartRewindSeconds,
      Value<int?> playHistoryLimit,
      Value<bool?> autoScrollToCurrent,
    });
typedef $$PlaybackSettingsTableTableUpdateCompanionBuilder =
    PlaybackSettingsTableCompanion Function({
      Value<int> id,
      Value<AudioQuality?> audioQuality,
      Value<AudioFormatPriority?> audioFormatPriority,
      Value<bool?> rememberPosition,
      Value<int?> tempPlayRewindSeconds,
      Value<bool?> skipPreviewClips,
      Value<String?> outputDeviceId,
      Value<String?> outputDeviceName,
      Value<int?> restartRewindSeconds,
      Value<int?> playHistoryLimit,
      Value<bool?> autoScrollToCurrent,
    });

class $$PlaybackSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackSettingsTableTable> {
  $$PlaybackSettingsTableTableFilterComposer({
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

  ColumnWithTypeConverterFilters<AudioQuality?, AudioQuality, String>
  get audioQuality => $composableBuilder(
    column: $table.audioQuality,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    AudioFormatPriority?,
    AudioFormatPriority,
    String
  >
  get audioFormatPriority => $composableBuilder(
    column: $table.audioFormatPriority,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get rememberPosition => $composableBuilder(
    column: $table.rememberPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tempPlayRewindSeconds => $composableBuilder(
    column: $table.tempPlayRewindSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get skipPreviewClips => $composableBuilder(
    column: $table.skipPreviewClips,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outputDeviceId => $composableBuilder(
    column: $table.outputDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outputDeviceName => $composableBuilder(
    column: $table.outputDeviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get restartRewindSeconds => $composableBuilder(
    column: $table.restartRewindSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playHistoryLimit => $composableBuilder(
    column: $table.playHistoryLimit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoScrollToCurrent => $composableBuilder(
    column: $table.autoScrollToCurrent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackSettingsTableTable> {
  $$PlaybackSettingsTableTableOrderingComposer({
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

  ColumnOrderings<String> get audioQuality => $composableBuilder(
    column: $table.audioQuality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioFormatPriority => $composableBuilder(
    column: $table.audioFormatPriority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get rememberPosition => $composableBuilder(
    column: $table.rememberPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tempPlayRewindSeconds => $composableBuilder(
    column: $table.tempPlayRewindSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get skipPreviewClips => $composableBuilder(
    column: $table.skipPreviewClips,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outputDeviceId => $composableBuilder(
    column: $table.outputDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outputDeviceName => $composableBuilder(
    column: $table.outputDeviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get restartRewindSeconds => $composableBuilder(
    column: $table.restartRewindSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playHistoryLimit => $composableBuilder(
    column: $table.playHistoryLimit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoScrollToCurrent => $composableBuilder(
    column: $table.autoScrollToCurrent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackSettingsTableTable> {
  $$PlaybackSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AudioQuality?, String> get audioQuality =>
      $composableBuilder(
        column: $table.audioQuality,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<AudioFormatPriority?, String>
  get audioFormatPriority => $composableBuilder(
    column: $table.audioFormatPriority,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get rememberPosition => $composableBuilder(
    column: $table.rememberPosition,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tempPlayRewindSeconds => $composableBuilder(
    column: $table.tempPlayRewindSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get skipPreviewClips => $composableBuilder(
    column: $table.skipPreviewClips,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outputDeviceId => $composableBuilder(
    column: $table.outputDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get outputDeviceName => $composableBuilder(
    column: $table.outputDeviceName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get restartRewindSeconds => $composableBuilder(
    column: $table.restartRewindSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playHistoryLimit => $composableBuilder(
    column: $table.playHistoryLimit,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoScrollToCurrent => $composableBuilder(
    column: $table.autoScrollToCurrent,
    builder: (column) => column,
  );
}

class $$PlaybackSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackSettingsTableTable,
          PlaybackSettingsRow,
          $$PlaybackSettingsTableTableFilterComposer,
          $$PlaybackSettingsTableTableOrderingComposer,
          $$PlaybackSettingsTableTableAnnotationComposer,
          $$PlaybackSettingsTableTableCreateCompanionBuilder,
          $$PlaybackSettingsTableTableUpdateCompanionBuilder,
          (
            PlaybackSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $PlaybackSettingsTableTable,
              PlaybackSettingsRow
            >,
          ),
          PlaybackSettingsRow,
          PrefetchHooks Function()
        > {
  $$PlaybackSettingsTableTableTableManager(
    _$AppDatabase db,
    $PlaybackSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackSettingsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PlaybackSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaybackSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<AudioQuality?> audioQuality = const Value.absent(),
                Value<AudioFormatPriority?> audioFormatPriority =
                    const Value.absent(),
                Value<bool?> rememberPosition = const Value.absent(),
                Value<int?> tempPlayRewindSeconds = const Value.absent(),
                Value<bool?> skipPreviewClips = const Value.absent(),
                Value<String?> outputDeviceId = const Value.absent(),
                Value<String?> outputDeviceName = const Value.absent(),
                Value<int?> restartRewindSeconds = const Value.absent(),
                Value<int?> playHistoryLimit = const Value.absent(),
                Value<bool?> autoScrollToCurrent = const Value.absent(),
              }) => PlaybackSettingsTableCompanion(
                id: id,
                audioQuality: audioQuality,
                audioFormatPriority: audioFormatPriority,
                rememberPosition: rememberPosition,
                tempPlayRewindSeconds: tempPlayRewindSeconds,
                skipPreviewClips: skipPreviewClips,
                outputDeviceId: outputDeviceId,
                outputDeviceName: outputDeviceName,
                restartRewindSeconds: restartRewindSeconds,
                playHistoryLimit: playHistoryLimit,
                autoScrollToCurrent: autoScrollToCurrent,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<AudioQuality?> audioQuality = const Value.absent(),
                Value<AudioFormatPriority?> audioFormatPriority =
                    const Value.absent(),
                Value<bool?> rememberPosition = const Value.absent(),
                Value<int?> tempPlayRewindSeconds = const Value.absent(),
                Value<bool?> skipPreviewClips = const Value.absent(),
                Value<String?> outputDeviceId = const Value.absent(),
                Value<String?> outputDeviceName = const Value.absent(),
                Value<int?> restartRewindSeconds = const Value.absent(),
                Value<int?> playHistoryLimit = const Value.absent(),
                Value<bool?> autoScrollToCurrent = const Value.absent(),
              }) => PlaybackSettingsTableCompanion.insert(
                id: id,
                audioQuality: audioQuality,
                audioFormatPriority: audioFormatPriority,
                rememberPosition: rememberPosition,
                tempPlayRewindSeconds: tempPlayRewindSeconds,
                skipPreviewClips: skipPreviewClips,
                outputDeviceId: outputDeviceId,
                outputDeviceName: outputDeviceName,
                restartRewindSeconds: restartRewindSeconds,
                playHistoryLimit: playHistoryLimit,
                autoScrollToCurrent: autoScrollToCurrent,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaybackSettingsTableTable, PlaybackSettingsRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $PlaybackSettingsTableTable,
                    PlaybackSettingsRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackSettingsTableTable,
      PlaybackSettingsRow,
      $$PlaybackSettingsTableTableFilterComposer,
      $$PlaybackSettingsTableTableOrderingComposer,
      $$PlaybackSettingsTableTableAnnotationComposer,
      $$PlaybackSettingsTableTableCreateCompanionBuilder,
      $$PlaybackSettingsTableTableUpdateCompanionBuilder,
      (
        PlaybackSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $PlaybackSettingsTableTable,
          PlaybackSettingsRow
        >,
      ),
      PlaybackSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$InstalledPluginsTableTableCreateCompanionBuilder =
    InstalledPluginsTableCompanion Function({
      required String id,
      required String version,
      required String manifestJson,
      required String script,
      required DateTime installedAt,
      Value<bool> enabled,
      Value<String?> sourceIndexUrl,
      Value<String?> checksJson,
      Value<bool> fromDevFolder,
      Value<int> rowid,
    });
typedef $$InstalledPluginsTableTableUpdateCompanionBuilder =
    InstalledPluginsTableCompanion Function({
      Value<String> id,
      Value<String> version,
      Value<String> manifestJson,
      Value<String> script,
      Value<DateTime> installedAt,
      Value<bool> enabled,
      Value<String?> sourceIndexUrl,
      Value<String?> checksJson,
      Value<bool> fromDevFolder,
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

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceIndexUrl => $composableBuilder(
    column: $table.sourceIndexUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksJson => $composableBuilder(
    column: $table.checksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fromDevFolder => $composableBuilder(
    column: $table.fromDevFolder,
    builder: (column) => ColumnFilters(column),
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

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceIndexUrl => $composableBuilder(
    column: $table.sourceIndexUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksJson => $composableBuilder(
    column: $table.checksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fromDevFolder => $composableBuilder(
    column: $table.fromDevFolder,
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

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get sourceIndexUrl => $composableBuilder(
    column: $table.sourceIndexUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checksJson => $composableBuilder(
    column: $table.checksJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get fromDevFolder => $composableBuilder(
    column: $table.fromDevFolder,
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
                Value<bool> enabled = const Value.absent(),
                Value<String?> sourceIndexUrl = const Value.absent(),
                Value<String?> checksJson = const Value.absent(),
                Value<bool> fromDevFolder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstalledPluginsTableCompanion(
                id: id,
                version: version,
                manifestJson: manifestJson,
                script: script,
                installedAt: installedAt,
                enabled: enabled,
                sourceIndexUrl: sourceIndexUrl,
                checksJson: checksJson,
                fromDevFolder: fromDevFolder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String version,
                required String manifestJson,
                required String script,
                required DateTime installedAt,
                Value<bool> enabled = const Value.absent(),
                Value<String?> sourceIndexUrl = const Value.absent(),
                Value<String?> checksJson = const Value.absent(),
                Value<bool> fromDevFolder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstalledPluginsTableCompanion.insert(
                id: id,
                version: version,
                manifestJson: manifestJson,
                script: script,
                installedAt: installedAt,
                enabled: enabled,
                sourceIndexUrl: sourceIndexUrl,
                checksJson: checksJson,
                fromDevFolder: fromDevFolder,
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
typedef $$PluginIndexesTableTableCreateCompanionBuilder =
    PluginIndexesTableCompanion Function({
      required String url,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$PluginIndexesTableTableUpdateCompanionBuilder =
    PluginIndexesTableCompanion Function({
      Value<String> url,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$PluginIndexesTableTableFilterComposer
    extends Composer<_$AppDatabase, $PluginIndexesTableTable> {
  $$PluginIndexesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get addedAt =>
      $composableBuilder(
        column: $table.addedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$PluginIndexesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PluginIndexesTableTable> {
  $$PluginIndexesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PluginIndexesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PluginIndexesTableTable> {
  $$PluginIndexesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$PluginIndexesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PluginIndexesTableTable,
          PluginIndexRow,
          $$PluginIndexesTableTableFilterComposer,
          $$PluginIndexesTableTableOrderingComposer,
          $$PluginIndexesTableTableAnnotationComposer,
          $$PluginIndexesTableTableCreateCompanionBuilder,
          $$PluginIndexesTableTableUpdateCompanionBuilder,
          (
            PluginIndexRow,
            BaseReferences<
              _$AppDatabase,
              $PluginIndexesTableTable,
              PluginIndexRow
            >,
          ),
          PluginIndexRow,
          PrefetchHooks Function()
        > {
  $$PluginIndexesTableTableTableManager(
    _$AppDatabase db,
    $PluginIndexesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PluginIndexesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PluginIndexesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PluginIndexesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PluginIndexesTableCompanion(
                url: url,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => PluginIndexesTableCompanion.insert(
                url: url,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PluginIndexesTableTable, PluginIndexRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PluginIndexesTableTable,
                    PluginIndexRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PluginIndexesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PluginIndexesTableTable,
      PluginIndexRow,
      $$PluginIndexesTableTableFilterComposer,
      $$PluginIndexesTableTableOrderingComposer,
      $$PluginIndexesTableTableAnnotationComposer,
      $$PluginIndexesTableTableCreateCompanionBuilder,
      $$PluginIndexesTableTableUpdateCompanionBuilder,
      (
        PluginIndexRow,
        BaseReferences<_$AppDatabase, $PluginIndexesTableTable, PluginIndexRow>,
      ),
      PluginIndexRow,
      PrefetchHooks Function()
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
typedef $$TracksTableTableCreateCompanionBuilder =
    TracksTableCompanion Function({
      required String trackKey,
      required String sourceTypeId,
      required String sourceId,
      Value<int?> cid,
      required String title,
      Value<String?> uploader,
      Value<int?> durationMs,
      Value<String?> artworkJson,
      required DateTime updatedAt,
      Value<int?> partIndex,
      Value<String?> parentTitle,
      Value<int> rowid,
    });
typedef $$TracksTableTableUpdateCompanionBuilder =
    TracksTableCompanion Function({
      Value<String> trackKey,
      Value<String> sourceTypeId,
      Value<String> sourceId,
      Value<int?> cid,
      Value<String> title,
      Value<String?> uploader,
      Value<int?> durationMs,
      Value<String?> artworkJson,
      Value<DateTime> updatedAt,
      Value<int?> partIndex,
      Value<String?> parentTitle,
      Value<int> rowid,
    });

final class $$TracksTableTableReferences
    extends BaseReferences<_$AppDatabase, $TracksTableTable, TrackRow> {
  $$TracksTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$QueueEntriesTableTable, List<QueueEntryRow>>
  _queueEntriesTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.queueEntriesTable,
        aliasName: 'tracks__track_key__queue_entries__track_key',
      );

  $$QueueEntriesTableTableProcessedTableManager get queueEntriesTableRefs {
    final manager =
        $$QueueEntriesTableTableTableManager(
          $_db,
          $_db.queueEntriesTable,
        ).filter(
          (f) =>
              f.trackKey.trackKey.sqlEquals($_itemColumn<String>('track_key')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _queueEntriesTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlayHistoryTableTable, List<PlayHistoryRow>>
  _playHistoryTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.playHistoryTable,
    aliasName: 'tracks__track_key__play_history__track_key',
  );

  $$PlayHistoryTableTableProcessedTableManager get playHistoryTableRefs {
    final manager =
        $$PlayHistoryTableTableTableManager($_db, $_db.playHistoryTable).filter(
          (f) =>
              f.trackKey.trackKey.sqlEquals($_itemColumn<String>('track_key')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _playHistoryTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlaylistEntriesTableTable, List<PlaylistEntryRow>>
  _playlistEntriesTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.playlistEntriesTable,
        aliasName: 'tracks__track_key__playlist_entries__track_key',
      );

  $$PlaylistEntriesTableTableProcessedTableManager
  get playlistEntriesTableRefs {
    final manager =
        $$PlaylistEntriesTableTableTableManager(
          $_db,
          $_db.playlistEntriesTable,
        ).filter(
          (f) =>
              f.trackKey.trackKey.sqlEquals($_itemColumn<String>('track_key')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _playlistEntriesTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MatchResultsTableTable, List<MatchResultRow>>
  _matchResultsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.matchResultsTable,
        aliasName: 'tracks__track_key__match_results__selected_track_key',
      );

  $$MatchResultsTableTableProcessedTableManager get matchResultsTableRefs {
    final manager =
        $$MatchResultsTableTableTableManager(
          $_db,
          $_db.matchResultsTable,
        ).filter(
          (f) => f.selectedTrackKey.trackKey.sqlEquals(
            $_itemColumn<String>('track_key')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _matchResultsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TrackOriginsTableTable, List<TrackOriginRow>>
  _trackOriginsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.trackOriginsTable,
        aliasName: 'tracks__track_key__track_origins__track_key',
      );

  $$TrackOriginsTableTableProcessedTableManager get trackOriginsTableRefs {
    final manager =
        $$TrackOriginsTableTableTableManager(
          $_db,
          $_db.trackOriginsTable,
        ).filter(
          (f) =>
              f.trackKey.trackKey.sqlEquals($_itemColumn<String>('track_key')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _trackOriginsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TracksTableTableFilterComposer
    extends Composer<_$AppDatabase, $TracksTableTable> {
  $$TracksTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackKey => $composableBuilder(
    column: $table.trackKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceTypeId => $composableBuilder(
    column: $table.sourceTypeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cid => $composableBuilder(
    column: $table.cid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploader => $composableBuilder(
    column: $table.uploader,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get partIndex => $composableBuilder(
    column: $table.partIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentTitle => $composableBuilder(
    column: $table.parentTitle,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> queueEntriesTableRefs(
    Expression<bool> Function($$QueueEntriesTableTableFilterComposer f) f,
  ) {
    final $$QueueEntriesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.queueEntriesTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QueueEntriesTableTableFilterComposer(
            $db: $db,
            $table: $db.queueEntriesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playHistoryTableRefs(
    Expression<bool> Function($$PlayHistoryTableTableFilterComposer f) f,
  ) {
    final $$PlayHistoryTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.playHistoryTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayHistoryTableTableFilterComposer(
            $db: $db,
            $table: $db.playHistoryTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playlistEntriesTableRefs(
    Expression<bool> Function($$PlaylistEntriesTableTableFilterComposer f) f,
  ) {
    final $$PlaylistEntriesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.playlistEntriesTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistEntriesTableTableFilterComposer(
            $db: $db,
            $table: $db.playlistEntriesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> matchResultsTableRefs(
    Expression<bool> Function($$MatchResultsTableTableFilterComposer f) f,
  ) {
    final $$MatchResultsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.matchResultsTable,
      getReferencedColumn: (t) => t.selectedTrackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MatchResultsTableTableFilterComposer(
            $db: $db,
            $table: $db.matchResultsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> trackOriginsTableRefs(
    Expression<bool> Function($$TrackOriginsTableTableFilterComposer f) f,
  ) {
    final $$TrackOriginsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.trackOriginsTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackOriginsTableTableFilterComposer(
            $db: $db,
            $table: $db.trackOriginsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TracksTableTableOrderingComposer
    extends Composer<_$AppDatabase, $TracksTableTable> {
  $$TracksTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackKey => $composableBuilder(
    column: $table.trackKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceTypeId => $composableBuilder(
    column: $table.sourceTypeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cid => $composableBuilder(
    column: $table.cid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploader => $composableBuilder(
    column: $table.uploader,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partIndex => $composableBuilder(
    column: $table.partIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentTitle => $composableBuilder(
    column: $table.parentTitle,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $TracksTableTable> {
  $$TracksTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackKey =>
      $composableBuilder(column: $table.trackKey, builder: (column) => column);

  GeneratedColumn<String> get sourceTypeId => $composableBuilder(
    column: $table.sourceTypeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get cid =>
      $composableBuilder(column: $table.cid, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get uploader =>
      $composableBuilder(column: $table.uploader, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get partIndex =>
      $composableBuilder(column: $table.partIndex, builder: (column) => column);

  GeneratedColumn<String> get parentTitle => $composableBuilder(
    column: $table.parentTitle,
    builder: (column) => column,
  );

  Expression<T> queueEntriesTableRefs<T extends Object>(
    Expression<T> Function($$QueueEntriesTableTableAnnotationComposer a) f,
  ) {
    final $$QueueEntriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.trackKey,
          referencedTable: $db.queueEntriesTable,
          getReferencedColumn: (t) => t.trackKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$QueueEntriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.queueEntriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> playHistoryTableRefs<T extends Object>(
    Expression<T> Function($$PlayHistoryTableTableAnnotationComposer a) f,
  ) {
    final $$PlayHistoryTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.playHistoryTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlayHistoryTableTableAnnotationComposer(
            $db: $db,
            $table: $db.playHistoryTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> playlistEntriesTableRefs<T extends Object>(
    Expression<T> Function($$PlaylistEntriesTableTableAnnotationComposer a) f,
  ) {
    final $$PlaylistEntriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.trackKey,
          referencedTable: $db.playlistEntriesTable,
          getReferencedColumn: (t) => t.trackKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlaylistEntriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.playlistEntriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> matchResultsTableRefs<T extends Object>(
    Expression<T> Function($$MatchResultsTableTableAnnotationComposer a) f,
  ) {
    final $$MatchResultsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.trackKey,
          referencedTable: $db.matchResultsTable,
          getReferencedColumn: (t) => t.selectedTrackKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MatchResultsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.matchResultsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> trackOriginsTableRefs<T extends Object>(
    Expression<T> Function($$TrackOriginsTableTableAnnotationComposer a) f,
  ) {
    final $$TrackOriginsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.trackKey,
          referencedTable: $db.trackOriginsTable,
          getReferencedColumn: (t) => t.trackKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TrackOriginsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.trackOriginsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TracksTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TracksTableTable,
          TrackRow,
          $$TracksTableTableFilterComposer,
          $$TracksTableTableOrderingComposer,
          $$TracksTableTableAnnotationComposer,
          $$TracksTableTableCreateCompanionBuilder,
          $$TracksTableTableUpdateCompanionBuilder,
          (TrackRow, $$TracksTableTableReferences),
          TrackRow,
          PrefetchHooks Function({
            bool queueEntriesTableRefs,
            bool playHistoryTableRefs,
            bool playlistEntriesTableRefs,
            bool matchResultsTableRefs,
            bool trackOriginsTableRefs,
          })
        > {
  $$TracksTableTableTableManager(_$AppDatabase db, $TracksTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackKey = const Value.absent(),
                Value<String> sourceTypeId = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<int?> cid = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> uploader = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> artworkJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int?> partIndex = const Value.absent(),
                Value<String?> parentTitle = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksTableCompanion(
                trackKey: trackKey,
                sourceTypeId: sourceTypeId,
                sourceId: sourceId,
                cid: cid,
                title: title,
                uploader: uploader,
                durationMs: durationMs,
                artworkJson: artworkJson,
                updatedAt: updatedAt,
                partIndex: partIndex,
                parentTitle: parentTitle,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackKey,
                required String sourceTypeId,
                required String sourceId,
                Value<int?> cid = const Value.absent(),
                required String title,
                Value<String?> uploader = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> artworkJson = const Value.absent(),
                required DateTime updatedAt,
                Value<int?> partIndex = const Value.absent(),
                Value<String?> parentTitle = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TracksTableCompanion.insert(
                trackKey: trackKey,
                sourceTypeId: sourceTypeId,
                sourceId: sourceId,
                cid: cid,
                title: title,
                uploader: uploader,
                durationMs: durationMs,
                artworkJson: artworkJson,
                updatedAt: updatedAt,
                partIndex: partIndex,
                parentTitle: parentTitle,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TracksTableTable, TrackRow>(table),
                  $$TracksTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                queueEntriesTableRefs = false,
                playHistoryTableRefs = false,
                playlistEntriesTableRefs = false,
                matchResultsTableRefs = false,
                trackOriginsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (queueEntriesTableRefs) db.queueEntriesTable,
                    if (playHistoryTableRefs) db.playHistoryTable,
                    if (playlistEntriesTableRefs) db.playlistEntriesTable,
                    if (matchResultsTableRefs) db.matchResultsTable,
                    if (trackOriginsTableRefs) db.trackOriginsTable,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (queueEntriesTableRefs)
                        await $_getPrefetchedData<
                          TrackRow,
                          $TracksTableTable,
                          QueueEntryRow
                        >(
                          currentTable: table,
                          referencedTable: $$TracksTableTableReferences
                              ._queueEntriesTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TracksTableTableReferences(
                                db,
                                table,
                                p0,
                              ).queueEntriesTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.trackKey == item.trackKey,
                              ),
                          typedResults: items,
                        ),
                      if (playHistoryTableRefs)
                        await $_getPrefetchedData<
                          TrackRow,
                          $TracksTableTable,
                          PlayHistoryRow
                        >(
                          currentTable: table,
                          referencedTable: $$TracksTableTableReferences
                              ._playHistoryTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TracksTableTableReferences(
                                db,
                                table,
                                p0,
                              ).playHistoryTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.trackKey == item.trackKey,
                              ),
                          typedResults: items,
                        ),
                      if (playlistEntriesTableRefs)
                        await $_getPrefetchedData<
                          TrackRow,
                          $TracksTableTable,
                          PlaylistEntryRow
                        >(
                          currentTable: table,
                          referencedTable: $$TracksTableTableReferences
                              ._playlistEntriesTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TracksTableTableReferences(
                                db,
                                table,
                                p0,
                              ).playlistEntriesTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.trackKey == item.trackKey,
                              ),
                          typedResults: items,
                        ),
                      if (matchResultsTableRefs)
                        await $_getPrefetchedData<
                          TrackRow,
                          $TracksTableTable,
                          MatchResultRow
                        >(
                          currentTable: table,
                          referencedTable: $$TracksTableTableReferences
                              ._matchResultsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TracksTableTableReferences(
                                db,
                                table,
                                p0,
                              ).matchResultsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.selectedTrackKey == item.trackKey,
                              ),
                          typedResults: items,
                        ),
                      if (trackOriginsTableRefs)
                        await $_getPrefetchedData<
                          TrackRow,
                          $TracksTableTable,
                          TrackOriginRow
                        >(
                          currentTable: table,
                          referencedTable: $$TracksTableTableReferences
                              ._trackOriginsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TracksTableTableReferences(
                                db,
                                table,
                                p0,
                              ).trackOriginsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.trackKey == item.trackKey,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TracksTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TracksTableTable,
      TrackRow,
      $$TracksTableTableFilterComposer,
      $$TracksTableTableOrderingComposer,
      $$TracksTableTableAnnotationComposer,
      $$TracksTableTableCreateCompanionBuilder,
      $$TracksTableTableUpdateCompanionBuilder,
      (TrackRow, $$TracksTableTableReferences),
      TrackRow,
      PrefetchHooks Function({
        bool queueEntriesTableRefs,
        bool playHistoryTableRefs,
        bool playlistEntriesTableRefs,
        bool matchResultsTableRefs,
        bool trackOriginsTableRefs,
      })
    >;
typedef $$QueueEntriesTableTableCreateCompanionBuilder =
    QueueEntriesTableCompanion Function({
      Value<int> position,
      required String trackKey,
      Value<int?> shuffleRank,
    });
typedef $$QueueEntriesTableTableUpdateCompanionBuilder =
    QueueEntriesTableCompanion Function({
      Value<int> position,
      Value<String> trackKey,
      Value<int?> shuffleRank,
    });

final class $$QueueEntriesTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $QueueEntriesTableTable, QueueEntryRow> {
  $$QueueEntriesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TracksTableTable _trackKeyTable(_$AppDatabase db) =>
      db.tracksTable.createAlias('queue_entries__track_key__tracks__track_key');

  $$TracksTableTableProcessedTableManager get trackKey {
    final $_column = $_itemColumn<String>('track_key')!;

    final manager = $$TracksTableTableTableManager(
      $_db,
      $_db.tracksTable,
    ).filter((f) => f.trackKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$QueueEntriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $QueueEntriesTableTable> {
  $$QueueEntriesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get shuffleRank => $composableBuilder(
    column: $table.shuffleRank,
    builder: (column) => ColumnFilters(column),
  );

  $$TracksTableTableFilterComposer get trackKey {
    final $$TracksTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableFilterComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueEntriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $QueueEntriesTableTable> {
  $$QueueEntriesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get shuffleRank => $composableBuilder(
    column: $table.shuffleRank,
    builder: (column) => ColumnOrderings(column),
  );

  $$TracksTableTableOrderingComposer get trackKey {
    final $$TracksTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableOrderingComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueEntriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueueEntriesTableTable> {
  $$QueueEntriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get shuffleRank => $composableBuilder(
    column: $table.shuffleRank,
    builder: (column) => column,
  );

  $$TracksTableTableAnnotationComposer get trackKey {
    final $$TracksTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableAnnotationComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueEntriesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueueEntriesTableTable,
          QueueEntryRow,
          $$QueueEntriesTableTableFilterComposer,
          $$QueueEntriesTableTableOrderingComposer,
          $$QueueEntriesTableTableAnnotationComposer,
          $$QueueEntriesTableTableCreateCompanionBuilder,
          $$QueueEntriesTableTableUpdateCompanionBuilder,
          (QueueEntryRow, $$QueueEntriesTableTableReferences),
          QueueEntryRow,
          PrefetchHooks Function({bool trackKey})
        > {
  $$QueueEntriesTableTableTableManager(
    _$AppDatabase db,
    $QueueEntriesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueEntriesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueEntriesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueEntriesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> position = const Value.absent(),
                Value<String> trackKey = const Value.absent(),
                Value<int?> shuffleRank = const Value.absent(),
              }) => QueueEntriesTableCompanion(
                position: position,
                trackKey: trackKey,
                shuffleRank: shuffleRank,
              ),
          createCompanionCallback:
              ({
                Value<int> position = const Value.absent(),
                required String trackKey,
                Value<int?> shuffleRank = const Value.absent(),
              }) => QueueEntriesTableCompanion.insert(
                position: position,
                trackKey: trackKey,
                shuffleRank: shuffleRank,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QueueEntriesTableTable, QueueEntryRow>(table),
                  $$QueueEntriesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackKey = false}) {
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
                    if (trackKey) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.trackKey,
                        referencedTable: $$QueueEntriesTableTableReferences
                            ._trackKeyTable(db),
                        referencedColumn: $$QueueEntriesTableTableReferences
                            ._trackKeyTable(db)
                            .trackKey,
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

typedef $$QueueEntriesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueueEntriesTableTable,
      QueueEntryRow,
      $$QueueEntriesTableTableFilterComposer,
      $$QueueEntriesTableTableOrderingComposer,
      $$QueueEntriesTableTableAnnotationComposer,
      $$QueueEntriesTableTableCreateCompanionBuilder,
      $$QueueEntriesTableTableUpdateCompanionBuilder,
      (QueueEntryRow, $$QueueEntriesTableTableReferences),
      QueueEntryRow,
      PrefetchHooks Function({bool trackKey})
    >;
typedef $$PlayerStateTableTableCreateCompanionBuilder =
    PlayerStateTableCompanion Function({
      Value<int> id,
      Value<int?> currentPosition,
      required int positionMs,
      required LoopMode loopMode,
      required bool shuffleEnabled,
      required double volume,
      required bool muted,
      Value<PlayerMode?> mode,
      Value<String?> mixPluginId,
      Value<String?> mixId,
      Value<String?> mixTitle,
      Value<String?> mixCursor,
      required DateTime updatedAt,
    });
typedef $$PlayerStateTableTableUpdateCompanionBuilder =
    PlayerStateTableCompanion Function({
      Value<int> id,
      Value<int?> currentPosition,
      Value<int> positionMs,
      Value<LoopMode> loopMode,
      Value<bool> shuffleEnabled,
      Value<double> volume,
      Value<bool> muted,
      Value<PlayerMode?> mode,
      Value<String?> mixPluginId,
      Value<String?> mixId,
      Value<String?> mixTitle,
      Value<String?> mixCursor,
      Value<DateTime> updatedAt,
    });

class $$PlayerStateTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlayerStateTableTable> {
  $$PlayerStateTableTableFilterComposer({
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

  ColumnFilters<int> get currentPosition => $composableBuilder(
    column: $table.currentPosition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LoopMode, LoopMode, String> get loopMode =>
      $composableBuilder(
        column: $table.loopMode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get shuffleEnabled => $composableBuilder(
    column: $table.shuffleEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PlayerMode?, PlayerMode, String> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get mixPluginId => $composableBuilder(
    column: $table.mixPluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixId => $composableBuilder(
    column: $table.mixId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixTitle => $composableBuilder(
    column: $table.mixTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixCursor => $composableBuilder(
    column: $table.mixCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$PlayerStateTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayerStateTableTable> {
  $$PlayerStateTableTableOrderingComposer({
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

  ColumnOrderings<int> get currentPosition => $composableBuilder(
    column: $table.currentPosition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loopMode => $composableBuilder(
    column: $table.loopMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shuffleEnabled => $composableBuilder(
    column: $table.shuffleEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get muted => $composableBuilder(
    column: $table.muted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixPluginId => $composableBuilder(
    column: $table.mixPluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixId => $composableBuilder(
    column: $table.mixId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixTitle => $composableBuilder(
    column: $table.mixTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixCursor => $composableBuilder(
    column: $table.mixCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayerStateTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayerStateTableTable> {
  $$PlayerStateTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get currentPosition => $composableBuilder(
    column: $table.currentPosition,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<LoopMode, String> get loopMode =>
      $composableBuilder(column: $table.loopMode, builder: (column) => column);

  GeneratedColumn<bool> get shuffleEnabled => $composableBuilder(
    column: $table.shuffleEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  GeneratedColumn<bool> get muted =>
      $composableBuilder(column: $table.muted, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PlayerMode?, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get mixPluginId => $composableBuilder(
    column: $table.mixPluginId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mixId =>
      $composableBuilder(column: $table.mixId, builder: (column) => column);

  GeneratedColumn<String> get mixTitle =>
      $composableBuilder(column: $table.mixTitle, builder: (column) => column);

  GeneratedColumn<String> get mixCursor =>
      $composableBuilder(column: $table.mixCursor, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlayerStateTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayerStateTableTable,
          PlayerStateRow,
          $$PlayerStateTableTableFilterComposer,
          $$PlayerStateTableTableOrderingComposer,
          $$PlayerStateTableTableAnnotationComposer,
          $$PlayerStateTableTableCreateCompanionBuilder,
          $$PlayerStateTableTableUpdateCompanionBuilder,
          (
            PlayerStateRow,
            BaseReferences<
              _$AppDatabase,
              $PlayerStateTableTable,
              PlayerStateRow
            >,
          ),
          PlayerStateRow,
          PrefetchHooks Function()
        > {
  $$PlayerStateTableTableTableManager(
    _$AppDatabase db,
    $PlayerStateTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayerStateTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayerStateTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayerStateTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> currentPosition = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<LoopMode> loopMode = const Value.absent(),
                Value<bool> shuffleEnabled = const Value.absent(),
                Value<double> volume = const Value.absent(),
                Value<bool> muted = const Value.absent(),
                Value<PlayerMode?> mode = const Value.absent(),
                Value<String?> mixPluginId = const Value.absent(),
                Value<String?> mixId = const Value.absent(),
                Value<String?> mixTitle = const Value.absent(),
                Value<String?> mixCursor = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlayerStateTableCompanion(
                id: id,
                currentPosition: currentPosition,
                positionMs: positionMs,
                loopMode: loopMode,
                shuffleEnabled: shuffleEnabled,
                volume: volume,
                muted: muted,
                mode: mode,
                mixPluginId: mixPluginId,
                mixId: mixId,
                mixTitle: mixTitle,
                mixCursor: mixCursor,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> currentPosition = const Value.absent(),
                required int positionMs,
                required LoopMode loopMode,
                required bool shuffleEnabled,
                required double volume,
                required bool muted,
                Value<PlayerMode?> mode = const Value.absent(),
                Value<String?> mixPluginId = const Value.absent(),
                Value<String?> mixId = const Value.absent(),
                Value<String?> mixTitle = const Value.absent(),
                Value<String?> mixCursor = const Value.absent(),
                required DateTime updatedAt,
              }) => PlayerStateTableCompanion.insert(
                id: id,
                currentPosition: currentPosition,
                positionMs: positionMs,
                loopMode: loopMode,
                shuffleEnabled: shuffleEnabled,
                volume: volume,
                muted: muted,
                mode: mode,
                mixPluginId: mixPluginId,
                mixId: mixId,
                mixTitle: mixTitle,
                mixCursor: mixCursor,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlayerStateTableTable, PlayerStateRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlayerStateTableTable,
                    PlayerStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayerStateTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayerStateTableTable,
      PlayerStateRow,
      $$PlayerStateTableTableFilterComposer,
      $$PlayerStateTableTableOrderingComposer,
      $$PlayerStateTableTableAnnotationComposer,
      $$PlayerStateTableTableCreateCompanionBuilder,
      $$PlayerStateTableTableUpdateCompanionBuilder,
      (
        PlayerStateRow,
        BaseReferences<_$AppDatabase, $PlayerStateTableTable, PlayerStateRow>,
      ),
      PlayerStateRow,
      PrefetchHooks Function()
    >;
typedef $$PlayHistoryTableTableCreateCompanionBuilder =
    PlayHistoryTableCompanion Function({
      Value<int> id,
      required String trackKey,
      required DateTime playedAt,
    });
typedef $$PlayHistoryTableTableUpdateCompanionBuilder =
    PlayHistoryTableCompanion Function({
      Value<int> id,
      Value<String> trackKey,
      Value<DateTime> playedAt,
    });

final class $$PlayHistoryTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $PlayHistoryTableTable, PlayHistoryRow> {
  $$PlayHistoryTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TracksTableTable _trackKeyTable(_$AppDatabase db) =>
      db.tracksTable.createAlias('play_history__track_key__tracks__track_key');

  $$TracksTableTableProcessedTableManager get trackKey {
    final $_column = $_itemColumn<String>('track_key')!;

    final manager = $$TracksTableTableTableManager(
      $_db,
      $_db.tracksTable,
    ).filter((f) => f.trackKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlayHistoryTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlayHistoryTableTable> {
  $$PlayHistoryTableTableFilterComposer({
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

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get playedAt =>
      $composableBuilder(
        column: $table.playedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  $$TracksTableTableFilterComposer get trackKey {
    final $$TracksTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableFilterComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlayHistoryTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayHistoryTableTable> {
  $$PlayHistoryTableTableOrderingComposer({
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

  ColumnOrderings<int> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$TracksTableTableOrderingComposer get trackKey {
    final $$TracksTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableOrderingComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlayHistoryTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayHistoryTableTable> {
  $$PlayHistoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  $$TracksTableTableAnnotationComposer get trackKey {
    final $$TracksTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableAnnotationComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlayHistoryTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayHistoryTableTable,
          PlayHistoryRow,
          $$PlayHistoryTableTableFilterComposer,
          $$PlayHistoryTableTableOrderingComposer,
          $$PlayHistoryTableTableAnnotationComposer,
          $$PlayHistoryTableTableCreateCompanionBuilder,
          $$PlayHistoryTableTableUpdateCompanionBuilder,
          (PlayHistoryRow, $$PlayHistoryTableTableReferences),
          PlayHistoryRow,
          PrefetchHooks Function({bool trackKey})
        > {
  $$PlayHistoryTableTableTableManager(
    _$AppDatabase db,
    $PlayHistoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayHistoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayHistoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayHistoryTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> trackKey = const Value.absent(),
                Value<DateTime> playedAt = const Value.absent(),
              }) => PlayHistoryTableCompanion(
                id: id,
                trackKey: trackKey,
                playedAt: playedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String trackKey,
                required DateTime playedAt,
              }) => PlayHistoryTableCompanion.insert(
                id: id,
                trackKey: trackKey,
                playedAt: playedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlayHistoryTableTable, PlayHistoryRow>(table),
                  $$PlayHistoryTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackKey = false}) {
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
                    if (trackKey) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.trackKey,
                        referencedTable: $$PlayHistoryTableTableReferences
                            ._trackKeyTable(db),
                        referencedColumn: $$PlayHistoryTableTableReferences
                            ._trackKeyTable(db)
                            .trackKey,
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

typedef $$PlayHistoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayHistoryTableTable,
      PlayHistoryRow,
      $$PlayHistoryTableTableFilterComposer,
      $$PlayHistoryTableTableOrderingComposer,
      $$PlayHistoryTableTableAnnotationComposer,
      $$PlayHistoryTableTableCreateCompanionBuilder,
      $$PlayHistoryTableTableUpdateCompanionBuilder,
      (PlayHistoryRow, $$PlayHistoryTableTableReferences),
      PlayHistoryRow,
      PrefetchHooks Function({bool trackKey})
    >;
typedef $$LayoutStateTableTableCreateCompanionBuilder =
    LayoutStateTableCompanion Function({
      Value<int> id,
      Value<PlayerTab?> playerTab,
      Value<bool?> panelExpanded,
      Value<double?> panelWidth,
    });
typedef $$LayoutStateTableTableUpdateCompanionBuilder =
    LayoutStateTableCompanion Function({
      Value<int> id,
      Value<PlayerTab?> playerTab,
      Value<bool?> panelExpanded,
      Value<double?> panelWidth,
    });

class $$LayoutStateTableTableFilterComposer
    extends Composer<_$AppDatabase, $LayoutStateTableTable> {
  $$LayoutStateTableTableFilterComposer({
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

  ColumnWithTypeConverterFilters<PlayerTab?, PlayerTab, String> get playerTab =>
      $composableBuilder(
        column: $table.playerTab,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get panelExpanded => $composableBuilder(
    column: $table.panelExpanded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get panelWidth => $composableBuilder(
    column: $table.panelWidth,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LayoutStateTableTableOrderingComposer
    extends Composer<_$AppDatabase, $LayoutStateTableTable> {
  $$LayoutStateTableTableOrderingComposer({
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

  ColumnOrderings<String> get playerTab => $composableBuilder(
    column: $table.playerTab,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get panelExpanded => $composableBuilder(
    column: $table.panelExpanded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get panelWidth => $composableBuilder(
    column: $table.panelWidth,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LayoutStateTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $LayoutStateTableTable> {
  $$LayoutStateTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PlayerTab?, String> get playerTab =>
      $composableBuilder(column: $table.playerTab, builder: (column) => column);

  GeneratedColumn<bool> get panelExpanded => $composableBuilder(
    column: $table.panelExpanded,
    builder: (column) => column,
  );

  GeneratedColumn<double> get panelWidth => $composableBuilder(
    column: $table.panelWidth,
    builder: (column) => column,
  );
}

class $$LayoutStateTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LayoutStateTableTable,
          LayoutStateRow,
          $$LayoutStateTableTableFilterComposer,
          $$LayoutStateTableTableOrderingComposer,
          $$LayoutStateTableTableAnnotationComposer,
          $$LayoutStateTableTableCreateCompanionBuilder,
          $$LayoutStateTableTableUpdateCompanionBuilder,
          (
            LayoutStateRow,
            BaseReferences<
              _$AppDatabase,
              $LayoutStateTableTable,
              LayoutStateRow
            >,
          ),
          LayoutStateRow,
          PrefetchHooks Function()
        > {
  $$LayoutStateTableTableTableManager(
    _$AppDatabase db,
    $LayoutStateTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LayoutStateTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LayoutStateTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LayoutStateTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<PlayerTab?> playerTab = const Value.absent(),
                Value<bool?> panelExpanded = const Value.absent(),
                Value<double?> panelWidth = const Value.absent(),
              }) => LayoutStateTableCompanion(
                id: id,
                playerTab: playerTab,
                panelExpanded: panelExpanded,
                panelWidth: panelWidth,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<PlayerTab?> playerTab = const Value.absent(),
                Value<bool?> panelExpanded = const Value.absent(),
                Value<double?> panelWidth = const Value.absent(),
              }) => LayoutStateTableCompanion.insert(
                id: id,
                playerTab: playerTab,
                panelExpanded: panelExpanded,
                panelWidth: panelWidth,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LayoutStateTableTable, LayoutStateRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LayoutStateTableTable,
                    LayoutStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LayoutStateTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LayoutStateTableTable,
      LayoutStateRow,
      $$LayoutStateTableTableFilterComposer,
      $$LayoutStateTableTableOrderingComposer,
      $$LayoutStateTableTableAnnotationComposer,
      $$LayoutStateTableTableCreateCompanionBuilder,
      $$LayoutStateTableTableUpdateCompanionBuilder,
      (
        LayoutStateRow,
        BaseReferences<_$AppDatabase, $LayoutStateTableTable, LayoutStateRow>,
      ),
      LayoutStateRow,
      PrefetchHooks Function()
    >;
typedef $$AccountsTableTableCreateCompanionBuilder =
    AccountsTableCompanion Function({
      required String pluginId,
      required String userId,
      required String displayName,
      Value<String?> avatarJson,
      required AccountStatus status,
      required DateTime loggedInAt,
      Value<DateTime?> lastRefreshAt,
      Value<RefreshResult?> lastRefreshResult,
      Value<int> rowid,
    });
typedef $$AccountsTableTableUpdateCompanionBuilder =
    AccountsTableCompanion Function({
      Value<String> pluginId,
      Value<String> userId,
      Value<String> displayName,
      Value<String?> avatarJson,
      Value<AccountStatus> status,
      Value<DateTime> loggedInAt,
      Value<DateTime?> lastRefreshAt,
      Value<RefreshResult?> lastRefreshResult,
      Value<int> rowid,
    });

class $$AccountsTableTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTableTable> {
  $$AccountsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarJson => $composableBuilder(
    column: $table.avatarJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AccountStatus, AccountStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get loggedInAt =>
      $composableBuilder(
        column: $table.loggedInAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int> get lastRefreshAt =>
      $composableBuilder(
        column: $table.lastRefreshAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<RefreshResult?, RefreshResult, String>
  get lastRefreshResult => $composableBuilder(
    column: $table.lastRefreshResult,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$AccountsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTableTable> {
  $$AccountsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarJson => $composableBuilder(
    column: $table.avatarJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loggedInAt => $composableBuilder(
    column: $table.loggedInAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRefreshAt => $composableBuilder(
    column: $table.lastRefreshAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRefreshResult => $composableBuilder(
    column: $table.lastRefreshResult,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTableTable> {
  $$AccountsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarJson => $composableBuilder(
    column: $table.avatarJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<AccountStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get loggedInAt =>
      $composableBuilder(
        column: $table.loggedInAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastRefreshAt =>
      $composableBuilder(
        column: $table.lastRefreshAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<RefreshResult?, String>
  get lastRefreshResult => $composableBuilder(
    column: $table.lastRefreshResult,
    builder: (column) => column,
  );
}

class $$AccountsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTableTable,
          AccountRow,
          $$AccountsTableTableFilterComposer,
          $$AccountsTableTableOrderingComposer,
          $$AccountsTableTableAnnotationComposer,
          $$AccountsTableTableCreateCompanionBuilder,
          $$AccountsTableTableUpdateCompanionBuilder,
          (
            AccountRow,
            BaseReferences<_$AppDatabase, $AccountsTableTable, AccountRow>,
          ),
          AccountRow,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableTableManager(_$AppDatabase db, $AccountsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pluginId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> avatarJson = const Value.absent(),
                Value<AccountStatus> status = const Value.absent(),
                Value<DateTime> loggedInAt = const Value.absent(),
                Value<DateTime?> lastRefreshAt = const Value.absent(),
                Value<RefreshResult?> lastRefreshResult = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsTableCompanion(
                pluginId: pluginId,
                userId: userId,
                displayName: displayName,
                avatarJson: avatarJson,
                status: status,
                loggedInAt: loggedInAt,
                lastRefreshAt: lastRefreshAt,
                lastRefreshResult: lastRefreshResult,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pluginId,
                required String userId,
                required String displayName,
                Value<String?> avatarJson = const Value.absent(),
                required AccountStatus status,
                required DateTime loggedInAt,
                Value<DateTime?> lastRefreshAt = const Value.absent(),
                Value<RefreshResult?> lastRefreshResult = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsTableCompanion.insert(
                pluginId: pluginId,
                userId: userId,
                displayName: displayName,
                avatarJson: avatarJson,
                status: status,
                loggedInAt: loggedInAt,
                lastRefreshAt: lastRefreshAt,
                lastRefreshResult: lastRefreshResult,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AccountsTableTable, AccountRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AccountsTableTable,
                    AccountRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTableTable,
      AccountRow,
      $$AccountsTableTableFilterComposer,
      $$AccountsTableTableOrderingComposer,
      $$AccountsTableTableAnnotationComposer,
      $$AccountsTableTableCreateCompanionBuilder,
      $$AccountsTableTableUpdateCompanionBuilder,
      (
        AccountRow,
        BaseReferences<_$AppDatabase, $AccountsTableTable, AccountRow>,
      ),
      AccountRow,
      PrefetchHooks Function()
    >;
typedef $$SourceSettingsTableTableCreateCompanionBuilder =
    SourceSettingsTableCompanion Function({
      required String pluginId,
      Value<bool?> browseAsLoggedIn,
      Value<bool?> matchTarget,
      Value<int?> matchRank,
      Value<int> rowid,
    });
typedef $$SourceSettingsTableTableUpdateCompanionBuilder =
    SourceSettingsTableCompanion Function({
      Value<String> pluginId,
      Value<bool?> browseAsLoggedIn,
      Value<bool?> matchTarget,
      Value<int?> matchRank,
      Value<int> rowid,
    });

class $$SourceSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SourceSettingsTableTable> {
  $$SourceSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get browseAsLoggedIn => $composableBuilder(
    column: $table.browseAsLoggedIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get matchTarget => $composableBuilder(
    column: $table.matchTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get matchRank => $composableBuilder(
    column: $table.matchRank,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourceSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SourceSettingsTableTable> {
  $$SourceSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get browseAsLoggedIn => $composableBuilder(
    column: $table.browseAsLoggedIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get matchTarget => $composableBuilder(
    column: $table.matchTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get matchRank => $composableBuilder(
    column: $table.matchRank,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourceSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourceSettingsTableTable> {
  $$SourceSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumn<bool> get browseAsLoggedIn => $composableBuilder(
    column: $table.browseAsLoggedIn,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get matchTarget => $composableBuilder(
    column: $table.matchTarget,
    builder: (column) => column,
  );

  GeneratedColumn<int> get matchRank =>
      $composableBuilder(column: $table.matchRank, builder: (column) => column);
}

class $$SourceSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourceSettingsTableTable,
          SourceSettingsRow,
          $$SourceSettingsTableTableFilterComposer,
          $$SourceSettingsTableTableOrderingComposer,
          $$SourceSettingsTableTableAnnotationComposer,
          $$SourceSettingsTableTableCreateCompanionBuilder,
          $$SourceSettingsTableTableUpdateCompanionBuilder,
          (
            SourceSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $SourceSettingsTableTable,
              SourceSettingsRow
            >,
          ),
          SourceSettingsRow,
          PrefetchHooks Function()
        > {
  $$SourceSettingsTableTableTableManager(
    _$AppDatabase db,
    $SourceSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourceSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourceSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SourceSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> pluginId = const Value.absent(),
                Value<bool?> browseAsLoggedIn = const Value.absent(),
                Value<bool?> matchTarget = const Value.absent(),
                Value<int?> matchRank = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceSettingsTableCompanion(
                pluginId: pluginId,
                browseAsLoggedIn: browseAsLoggedIn,
                matchTarget: matchTarget,
                matchRank: matchRank,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pluginId,
                Value<bool?> browseAsLoggedIn = const Value.absent(),
                Value<bool?> matchTarget = const Value.absent(),
                Value<int?> matchRank = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceSettingsTableCompanion.insert(
                pluginId: pluginId,
                browseAsLoggedIn: browseAsLoggedIn,
                matchTarget: matchTarget,
                matchRank: matchRank,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourceSettingsTableTable, SourceSettingsRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $SourceSettingsTableTable,
                    SourceSettingsRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourceSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourceSettingsTableTable,
      SourceSettingsRow,
      $$SourceSettingsTableTableFilterComposer,
      $$SourceSettingsTableTableOrderingComposer,
      $$SourceSettingsTableTableAnnotationComposer,
      $$SourceSettingsTableTableCreateCompanionBuilder,
      $$SourceSettingsTableTableUpdateCompanionBuilder,
      (
        SourceSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $SourceSettingsTableTable,
          SourceSettingsRow
        >,
      ),
      SourceSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$DeveloperSettingsTableTableCreateCompanionBuilder =
    DeveloperSettingsTableCompanion Function({
      Value<int> id,
      Value<bool?> developerMode,
      Value<LogLevelSetting?> logLevel,
      Value<String?> pluginDevFolder,
      Value<bool?> reportReminderDismissed,
    });
typedef $$DeveloperSettingsTableTableUpdateCompanionBuilder =
    DeveloperSettingsTableCompanion Function({
      Value<int> id,
      Value<bool?> developerMode,
      Value<LogLevelSetting?> logLevel,
      Value<String?> pluginDevFolder,
      Value<bool?> reportReminderDismissed,
    });

class $$DeveloperSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DeveloperSettingsTableTable> {
  $$DeveloperSettingsTableTableFilterComposer({
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

  ColumnFilters<bool> get developerMode => $composableBuilder(
    column: $table.developerMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LogLevelSetting?, LogLevelSetting, String>
  get logLevel => $composableBuilder(
    column: $table.logLevel,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get pluginDevFolder => $composableBuilder(
    column: $table.pluginDevFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reportReminderDismissed => $composableBuilder(
    column: $table.reportReminderDismissed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeveloperSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DeveloperSettingsTableTable> {
  $$DeveloperSettingsTableTableOrderingComposer({
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

  ColumnOrderings<bool> get developerMode => $composableBuilder(
    column: $table.developerMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logLevel => $composableBuilder(
    column: $table.logLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pluginDevFolder => $composableBuilder(
    column: $table.pluginDevFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reportReminderDismissed => $composableBuilder(
    column: $table.reportReminderDismissed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeveloperSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeveloperSettingsTableTable> {
  $$DeveloperSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get developerMode => $composableBuilder(
    column: $table.developerMode,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<LogLevelSetting?, String> get logLevel =>
      $composableBuilder(column: $table.logLevel, builder: (column) => column);

  GeneratedColumn<String> get pluginDevFolder => $composableBuilder(
    column: $table.pluginDevFolder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reportReminderDismissed => $composableBuilder(
    column: $table.reportReminderDismissed,
    builder: (column) => column,
  );
}

class $$DeveloperSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeveloperSettingsTableTable,
          DeveloperSettingsRow,
          $$DeveloperSettingsTableTableFilterComposer,
          $$DeveloperSettingsTableTableOrderingComposer,
          $$DeveloperSettingsTableTableAnnotationComposer,
          $$DeveloperSettingsTableTableCreateCompanionBuilder,
          $$DeveloperSettingsTableTableUpdateCompanionBuilder,
          (
            DeveloperSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $DeveloperSettingsTableTable,
              DeveloperSettingsRow
            >,
          ),
          DeveloperSettingsRow,
          PrefetchHooks Function()
        > {
  $$DeveloperSettingsTableTableTableManager(
    _$AppDatabase db,
    $DeveloperSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeveloperSettingsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DeveloperSettingsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DeveloperSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool?> developerMode = const Value.absent(),
                Value<LogLevelSetting?> logLevel = const Value.absent(),
                Value<String?> pluginDevFolder = const Value.absent(),
                Value<bool?> reportReminderDismissed = const Value.absent(),
              }) => DeveloperSettingsTableCompanion(
                id: id,
                developerMode: developerMode,
                logLevel: logLevel,
                pluginDevFolder: pluginDevFolder,
                reportReminderDismissed: reportReminderDismissed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool?> developerMode = const Value.absent(),
                Value<LogLevelSetting?> logLevel = const Value.absent(),
                Value<String?> pluginDevFolder = const Value.absent(),
                Value<bool?> reportReminderDismissed = const Value.absent(),
              }) => DeveloperSettingsTableCompanion.insert(
                id: id,
                developerMode: developerMode,
                logLevel: logLevel,
                pluginDevFolder: pluginDevFolder,
                reportReminderDismissed: reportReminderDismissed,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $DeveloperSettingsTableTable,
                    DeveloperSettingsRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DeveloperSettingsTableTable,
                    DeveloperSettingsRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeveloperSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeveloperSettingsTableTable,
      DeveloperSettingsRow,
      $$DeveloperSettingsTableTableFilterComposer,
      $$DeveloperSettingsTableTableOrderingComposer,
      $$DeveloperSettingsTableTableAnnotationComposer,
      $$DeveloperSettingsTableTableCreateCompanionBuilder,
      $$DeveloperSettingsTableTableUpdateCompanionBuilder,
      (
        DeveloperSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $DeveloperSettingsTableTable,
          DeveloperSettingsRow
        >,
      ),
      DeveloperSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$SchedulerRunsTableTableCreateCompanionBuilder =
    SchedulerRunsTableCompanion Function({
      required String jobId,
      required DateTime lastSuccessAt,
      Value<int> rowid,
    });
typedef $$SchedulerRunsTableTableUpdateCompanionBuilder =
    SchedulerRunsTableCompanion Function({
      Value<String> jobId,
      Value<DateTime> lastSuccessAt,
      Value<int> rowid,
    });

class $$SchedulerRunsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SchedulerRunsTableTable> {
  $$SchedulerRunsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get lastSuccessAt =>
      $composableBuilder(
        column: $table.lastSuccessAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$SchedulerRunsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SchedulerRunsTableTable> {
  $$SchedulerRunsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSuccessAt => $composableBuilder(
    column: $table.lastSuccessAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SchedulerRunsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchedulerRunsTableTable> {
  $$SchedulerRunsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get lastSuccessAt =>
      $composableBuilder(
        column: $table.lastSuccessAt,
        builder: (column) => column,
      );
}

class $$SchedulerRunsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchedulerRunsTableTable,
          SchedulerRunRow,
          $$SchedulerRunsTableTableFilterComposer,
          $$SchedulerRunsTableTableOrderingComposer,
          $$SchedulerRunsTableTableAnnotationComposer,
          $$SchedulerRunsTableTableCreateCompanionBuilder,
          $$SchedulerRunsTableTableUpdateCompanionBuilder,
          (
            SchedulerRunRow,
            BaseReferences<
              _$AppDatabase,
              $SchedulerRunsTableTable,
              SchedulerRunRow
            >,
          ),
          SchedulerRunRow,
          PrefetchHooks Function()
        > {
  $$SchedulerRunsTableTableTableManager(
    _$AppDatabase db,
    $SchedulerRunsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchedulerRunsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchedulerRunsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchedulerRunsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> jobId = const Value.absent(),
                Value<DateTime> lastSuccessAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchedulerRunsTableCompanion(
                jobId: jobId,
                lastSuccessAt: lastSuccessAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String jobId,
                required DateTime lastSuccessAt,
                Value<int> rowid = const Value.absent(),
              }) => SchedulerRunsTableCompanion.insert(
                jobId: jobId,
                lastSuccessAt: lastSuccessAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SchedulerRunsTableTable, SchedulerRunRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SchedulerRunsTableTable,
                    SchedulerRunRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SchedulerRunsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchedulerRunsTableTable,
      SchedulerRunRow,
      $$SchedulerRunsTableTableFilterComposer,
      $$SchedulerRunsTableTableOrderingComposer,
      $$SchedulerRunsTableTableAnnotationComposer,
      $$SchedulerRunsTableTableCreateCompanionBuilder,
      $$SchedulerRunsTableTableUpdateCompanionBuilder,
      (
        SchedulerRunRow,
        BaseReferences<
          _$AppDatabase,
          $SchedulerRunsTableTable,
          SchedulerRunRow
        >,
      ),
      SchedulerRunRow,
      PrefetchHooks Function()
    >;
typedef $$RadioStationsTableTableCreateCompanionBuilder =
    RadioStationsTableCompanion Function({
      Value<int> id,
      required String pluginId,
      required String roomId,
      required String title,
      Value<String?> hostName,
      Value<String?> artworkJson,
      required int sortOrder,
      required DateTime addedAt,
      Value<RadioLiveStatus?> liveStatus,
      Value<String?> liveTitle,
      Value<DateTime?> statusCheckedAt,
    });
typedef $$RadioStationsTableTableUpdateCompanionBuilder =
    RadioStationsTableCompanion Function({
      Value<int> id,
      Value<String> pluginId,
      Value<String> roomId,
      Value<String> title,
      Value<String?> hostName,
      Value<String?> artworkJson,
      Value<int> sortOrder,
      Value<DateTime> addedAt,
      Value<RadioLiveStatus?> liveStatus,
      Value<String?> liveTitle,
      Value<DateTime?> statusCheckedAt,
    });

class $$RadioStationsTableTableFilterComposer
    extends Composer<_$AppDatabase, $RadioStationsTableTable> {
  $$RadioStationsTableTableFilterComposer({
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

  ColumnFilters<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostName => $composableBuilder(
    column: $table.hostName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get addedAt =>
      $composableBuilder(
        column: $table.addedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<RadioLiveStatus?, RadioLiveStatus, String>
  get liveStatus => $composableBuilder(
    column: $table.liveStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get liveTitle => $composableBuilder(
    column: $table.liveTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get statusCheckedAt => $composableBuilder(
    column: $table.statusCheckedAt,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$RadioStationsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $RadioStationsTableTable> {
  $$RadioStationsTableTableOrderingComposer({
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

  ColumnOrderings<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostName => $composableBuilder(
    column: $table.hostName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get liveStatus => $composableBuilder(
    column: $table.liveStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get liveTitle => $composableBuilder(
    column: $table.liveTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statusCheckedAt => $composableBuilder(
    column: $table.statusCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RadioStationsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $RadioStationsTableTable> {
  $$RadioStationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get hostName =>
      $composableBuilder(column: $table.hostName, builder: (column) => column);

  GeneratedColumn<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RadioLiveStatus?, String> get liveStatus =>
      $composableBuilder(
        column: $table.liveStatus,
        builder: (column) => column,
      );

  GeneratedColumn<String> get liveTitle =>
      $composableBuilder(column: $table.liveTitle, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime?, int> get statusCheckedAt =>
      $composableBuilder(
        column: $table.statusCheckedAt,
        builder: (column) => column,
      );
}

class $$RadioStationsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RadioStationsTableTable,
          RadioStationRow,
          $$RadioStationsTableTableFilterComposer,
          $$RadioStationsTableTableOrderingComposer,
          $$RadioStationsTableTableAnnotationComposer,
          $$RadioStationsTableTableCreateCompanionBuilder,
          $$RadioStationsTableTableUpdateCompanionBuilder,
          (
            RadioStationRow,
            BaseReferences<
              _$AppDatabase,
              $RadioStationsTableTable,
              RadioStationRow
            >,
          ),
          RadioStationRow,
          PrefetchHooks Function()
        > {
  $$RadioStationsTableTableTableManager(
    _$AppDatabase db,
    $RadioStationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RadioStationsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RadioStationsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RadioStationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> pluginId = const Value.absent(),
                Value<String> roomId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> hostName = const Value.absent(),
                Value<String?> artworkJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<RadioLiveStatus?> liveStatus = const Value.absent(),
                Value<String?> liveTitle = const Value.absent(),
                Value<DateTime?> statusCheckedAt = const Value.absent(),
              }) => RadioStationsTableCompanion(
                id: id,
                pluginId: pluginId,
                roomId: roomId,
                title: title,
                hostName: hostName,
                artworkJson: artworkJson,
                sortOrder: sortOrder,
                addedAt: addedAt,
                liveStatus: liveStatus,
                liveTitle: liveTitle,
                statusCheckedAt: statusCheckedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String pluginId,
                required String roomId,
                required String title,
                Value<String?> hostName = const Value.absent(),
                Value<String?> artworkJson = const Value.absent(),
                required int sortOrder,
                required DateTime addedAt,
                Value<RadioLiveStatus?> liveStatus = const Value.absent(),
                Value<String?> liveTitle = const Value.absent(),
                Value<DateTime?> statusCheckedAt = const Value.absent(),
              }) => RadioStationsTableCompanion.insert(
                id: id,
                pluginId: pluginId,
                roomId: roomId,
                title: title,
                hostName: hostName,
                artworkJson: artworkJson,
                sortOrder: sortOrder,
                addedAt: addedAt,
                liveStatus: liveStatus,
                liveTitle: liveTitle,
                statusCheckedAt: statusCheckedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RadioStationsTableTable, RadioStationRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RadioStationsTableTable,
                    RadioStationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RadioStationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RadioStationsTableTable,
      RadioStationRow,
      $$RadioStationsTableTableFilterComposer,
      $$RadioStationsTableTableOrderingComposer,
      $$RadioStationsTableTableAnnotationComposer,
      $$RadioStationsTableTableCreateCompanionBuilder,
      $$RadioStationsTableTableUpdateCompanionBuilder,
      (
        RadioStationRow,
        BaseReferences<
          _$AppDatabase,
          $RadioStationsTableTable,
          RadioStationRow
        >,
      ),
      RadioStationRow,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableTableCreateCompanionBuilder =
    PlaylistsTableCompanion Function({
      Value<int> id,
      required PlaylistKind kind,
      required String name,
      Value<String?> description,
      Value<String?> artworkJson,
      required int sortOrder,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> mixPluginId,
      Value<String?> mixSeedSourceId,
      Value<int?> mixSeedCid,
    });
typedef $$PlaylistsTableTableUpdateCompanionBuilder =
    PlaylistsTableCompanion Function({
      Value<int> id,
      Value<PlaylistKind> kind,
      Value<String> name,
      Value<String?> description,
      Value<String?> artworkJson,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> mixPluginId,
      Value<String?> mixSeedSourceId,
      Value<int?> mixSeedCid,
    });

final class $$PlaylistsTableTableReferences
    extends BaseReferences<_$AppDatabase, $PlaylistsTableTable, PlaylistRow> {
  $$PlaylistsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$PlaylistEntriesTableTable, List<PlaylistEntryRow>>
  _playlistEntriesTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.playlistEntriesTable,
        aliasName: 'playlists__id__playlist_entries__playlist_id',
      );

  $$PlaylistEntriesTableTableProcessedTableManager
  get playlistEntriesTableRefs {
    final manager = $$PlaylistEntriesTableTableTableManager(
      $_db,
      $_db.playlistEntriesTable,
    ).filter((f) => f.playlistId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _playlistEntriesTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlaylistRemoteTableTable, List<PlaylistRemoteRow>>
  _playlistRemoteTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.playlistRemoteTable,
        aliasName: 'playlists__id__playlist_remote__playlist_id',
      );

  $$PlaylistRemoteTableTableProcessedTableManager get playlistRemoteTableRefs {
    final manager = $$PlaylistRemoteTableTableTableManager(
      $_db,
      $_db.playlistRemoteTable,
    ).filter((f) => f.playlistId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _playlistRemoteTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $LegacyPlaylistIdsTableTable,
    List<LegacyPlaylistIdRow>
  >
  _legacyPlaylistIdsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.legacyPlaylistIdsTable,
        aliasName: 'playlists__id__legacy_playlist_ids__playlist_id',
      );

  $$LegacyPlaylistIdsTableTableProcessedTableManager
  get legacyPlaylistIdsTableRefs {
    final manager = $$LegacyPlaylistIdsTableTableTableManager(
      $_db,
      $_db.legacyPlaylistIdsTable,
    ).filter((f) => f.playlistId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _legacyPlaylistIdsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PlaylistsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableFilterComposer({
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

  ColumnWithTypeConverterFilters<PlaylistKind, PlaylistKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get createdAt =>
      $composableBuilder(
        column: $table.createdAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get updatedAt =>
      $composableBuilder(
        column: $table.updatedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get mixPluginId => $composableBuilder(
    column: $table.mixPluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mixSeedSourceId => $composableBuilder(
    column: $table.mixSeedSourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mixSeedCid => $composableBuilder(
    column: $table.mixSeedCid,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> playlistEntriesTableRefs(
    Expression<bool> Function($$PlaylistEntriesTableTableFilterComposer f) f,
  ) {
    final $$PlaylistEntriesTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistEntriesTable,
      getReferencedColumn: (t) => t.playlistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistEntriesTableTableFilterComposer(
            $db: $db,
            $table: $db.playlistEntriesTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playlistRemoteTableRefs(
    Expression<bool> Function($$PlaylistRemoteTableTableFilterComposer f) f,
  ) {
    final $$PlaylistRemoteTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistRemoteTable,
      getReferencedColumn: (t) => t.playlistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistRemoteTableTableFilterComposer(
            $db: $db,
            $table: $db.playlistRemoteTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> legacyPlaylistIdsTableRefs(
    Expression<bool> Function($$LegacyPlaylistIdsTableTableFilterComposer f) f,
  ) {
    final $$LegacyPlaylistIdsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.legacyPlaylistIdsTable,
          getReferencedColumn: (t) => t.playlistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LegacyPlaylistIdsTableTableFilterComposer(
                $db: $db,
                $table: $db.legacyPlaylistIdsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$PlaylistsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixPluginId => $composableBuilder(
    column: $table.mixPluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mixSeedSourceId => $composableBuilder(
    column: $table.mixSeedSourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mixSeedCid => $composableBuilder(
    column: $table.mixSeedCid,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTableTable> {
  $$PlaylistsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<PlaylistKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkJson => $composableBuilder(
    column: $table.artworkJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get mixPluginId => $composableBuilder(
    column: $table.mixPluginId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mixSeedSourceId => $composableBuilder(
    column: $table.mixSeedSourceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get mixSeedCid => $composableBuilder(
    column: $table.mixSeedCid,
    builder: (column) => column,
  );

  Expression<T> playlistEntriesTableRefs<T extends Object>(
    Expression<T> Function($$PlaylistEntriesTableTableAnnotationComposer a) f,
  ) {
    final $$PlaylistEntriesTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.playlistEntriesTable,
          getReferencedColumn: (t) => t.playlistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlaylistEntriesTableTableAnnotationComposer(
                $db: $db,
                $table: $db.playlistEntriesTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> playlistRemoteTableRefs<T extends Object>(
    Expression<T> Function($$PlaylistRemoteTableTableAnnotationComposer a) f,
  ) {
    final $$PlaylistRemoteTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.playlistRemoteTable,
          getReferencedColumn: (t) => t.playlistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlaylistRemoteTableTableAnnotationComposer(
                $db: $db,
                $table: $db.playlistRemoteTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> legacyPlaylistIdsTableRefs<T extends Object>(
    Expression<T> Function($$LegacyPlaylistIdsTableTableAnnotationComposer a) f,
  ) {
    final $$LegacyPlaylistIdsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.legacyPlaylistIdsTable,
          getReferencedColumn: (t) => t.playlistId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LegacyPlaylistIdsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.legacyPlaylistIdsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$PlaylistsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTableTable,
          PlaylistRow,
          $$PlaylistsTableTableFilterComposer,
          $$PlaylistsTableTableOrderingComposer,
          $$PlaylistsTableTableAnnotationComposer,
          $$PlaylistsTableTableCreateCompanionBuilder,
          $$PlaylistsTableTableUpdateCompanionBuilder,
          (PlaylistRow, $$PlaylistsTableTableReferences),
          PlaylistRow,
          PrefetchHooks Function({
            bool playlistEntriesTableRefs,
            bool playlistRemoteTableRefs,
            bool legacyPlaylistIdsTableRefs,
          })
        > {
  $$PlaylistsTableTableTableManager(
    _$AppDatabase db,
    $PlaylistsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<PlaylistKind> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> artworkJson = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> mixPluginId = const Value.absent(),
                Value<String?> mixSeedSourceId = const Value.absent(),
                Value<int?> mixSeedCid = const Value.absent(),
              }) => PlaylistsTableCompanion(
                id: id,
                kind: kind,
                name: name,
                description: description,
                artworkJson: artworkJson,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mixPluginId: mixPluginId,
                mixSeedSourceId: mixSeedSourceId,
                mixSeedCid: mixSeedCid,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required PlaylistKind kind,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> artworkJson = const Value.absent(),
                required int sortOrder,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> mixPluginId = const Value.absent(),
                Value<String?> mixSeedSourceId = const Value.absent(),
                Value<int?> mixSeedCid = const Value.absent(),
              }) => PlaylistsTableCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                description: description,
                artworkJson: artworkJson,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mixPluginId: mixPluginId,
                mixSeedSourceId: mixSeedSourceId,
                mixSeedCid: mixSeedCid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistsTableTable, PlaylistRow>(table),
                  $$PlaylistsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                playlistEntriesTableRefs = false,
                playlistRemoteTableRefs = false,
                legacyPlaylistIdsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (playlistEntriesTableRefs) db.playlistEntriesTable,
                    if (playlistRemoteTableRefs) db.playlistRemoteTable,
                    if (legacyPlaylistIdsTableRefs) db.legacyPlaylistIdsTable,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (playlistEntriesTableRefs)
                        await $_getPrefetchedData<
                          PlaylistRow,
                          $PlaylistsTableTable,
                          PlaylistEntryRow
                        >(
                          currentTable: table,
                          referencedTable: $$PlaylistsTableTableReferences
                              ._playlistEntriesTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PlaylistsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).playlistEntriesTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.playlistId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (playlistRemoteTableRefs)
                        await $_getPrefetchedData<
                          PlaylistRow,
                          $PlaylistsTableTable,
                          PlaylistRemoteRow
                        >(
                          currentTable: table,
                          referencedTable: $$PlaylistsTableTableReferences
                              ._playlistRemoteTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PlaylistsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).playlistRemoteTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.playlistId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (legacyPlaylistIdsTableRefs)
                        await $_getPrefetchedData<
                          PlaylistRow,
                          $PlaylistsTableTable,
                          LegacyPlaylistIdRow
                        >(
                          currentTable: table,
                          referencedTable: $$PlaylistsTableTableReferences
                              ._legacyPlaylistIdsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PlaylistsTableTableReferences(
                                db,
                                table,
                                p0,
                              ).legacyPlaylistIdsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.playlistId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PlaylistsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTableTable,
      PlaylistRow,
      $$PlaylistsTableTableFilterComposer,
      $$PlaylistsTableTableOrderingComposer,
      $$PlaylistsTableTableAnnotationComposer,
      $$PlaylistsTableTableCreateCompanionBuilder,
      $$PlaylistsTableTableUpdateCompanionBuilder,
      (PlaylistRow, $$PlaylistsTableTableReferences),
      PlaylistRow,
      PrefetchHooks Function({
        bool playlistEntriesTableRefs,
        bool playlistRemoteTableRefs,
        bool legacyPlaylistIdsTableRefs,
      })
    >;
typedef $$PlaylistEntriesTableTableCreateCompanionBuilder =
    PlaylistEntriesTableCompanion Function({
      Value<int> id,
      required int playlistId,
      required int position,
      required String trackKey,
      Value<String?> remoteItemId,
      Value<bool> unavailable,
      Value<int> seenGeneration,
    });
typedef $$PlaylistEntriesTableTableUpdateCompanionBuilder =
    PlaylistEntriesTableCompanion Function({
      Value<int> id,
      Value<int> playlistId,
      Value<int> position,
      Value<String> trackKey,
      Value<String?> remoteItemId,
      Value<bool> unavailable,
      Value<int> seenGeneration,
    });

final class $$PlaylistEntriesTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PlaylistEntriesTableTable,
          PlaylistEntryRow
        > {
  $$PlaylistEntriesTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PlaylistsTableTable _playlistIdTable(_$AppDatabase db) => db
      .playlistsTable
      .createAlias('playlist_entries__playlist_id__playlists__id');

  $$PlaylistsTableTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<int>('playlist_id')!;

    final manager = $$PlaylistsTableTableTableManager(
      $_db,
      $_db.playlistsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TracksTableTable _trackKeyTable(_$AppDatabase db) => db.tracksTable
      .createAlias('playlist_entries__track_key__tracks__track_key');

  $$TracksTableTableProcessedTableManager get trackKey {
    final $_column = $_itemColumn<String>('track_key')!;

    final manager = $$TracksTableTableTableManager(
      $_db,
      $_db.tracksTable,
    ).filter((f) => f.trackKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlaylistEntriesTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTableTable> {
  $$PlaylistEntriesTableTableFilterComposer({
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

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteItemId => $composableBuilder(
    column: $table.remoteItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unavailable => $composableBuilder(
    column: $table.unavailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seenGeneration => $composableBuilder(
    column: $table.seenGeneration,
    builder: (column) => ColumnFilters(column),
  );

  $$PlaylistsTableTableFilterComposer get playlistId {
    final $$PlaylistsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableFilterComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TracksTableTableFilterComposer get trackKey {
    final $$TracksTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableFilterComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistEntriesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTableTable> {
  $$PlaylistEntriesTableTableOrderingComposer({
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

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteItemId => $composableBuilder(
    column: $table.remoteItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unavailable => $composableBuilder(
    column: $table.unavailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seenGeneration => $composableBuilder(
    column: $table.seenGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlaylistsTableTableOrderingComposer get playlistId {
    final $$PlaylistsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableOrderingComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TracksTableTableOrderingComposer get trackKey {
    final $$TracksTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableOrderingComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistEntriesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistEntriesTableTable> {
  $$PlaylistEntriesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get remoteItemId => $composableBuilder(
    column: $table.remoteItemId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get unavailable => $composableBuilder(
    column: $table.unavailable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seenGeneration => $composableBuilder(
    column: $table.seenGeneration,
    builder: (column) => column,
  );

  $$PlaylistsTableTableAnnotationComposer get playlistId {
    final $$PlaylistsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TracksTableTableAnnotationComposer get trackKey {
    final $$TracksTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableAnnotationComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistEntriesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistEntriesTableTable,
          PlaylistEntryRow,
          $$PlaylistEntriesTableTableFilterComposer,
          $$PlaylistEntriesTableTableOrderingComposer,
          $$PlaylistEntriesTableTableAnnotationComposer,
          $$PlaylistEntriesTableTableCreateCompanionBuilder,
          $$PlaylistEntriesTableTableUpdateCompanionBuilder,
          (PlaylistEntryRow, $$PlaylistEntriesTableTableReferences),
          PlaylistEntryRow,
          PrefetchHooks Function({bool playlistId, bool trackKey})
        > {
  $$PlaylistEntriesTableTableTableManager(
    _$AppDatabase db,
    $PlaylistEntriesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistEntriesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistEntriesTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaylistEntriesTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> playlistId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> trackKey = const Value.absent(),
                Value<String?> remoteItemId = const Value.absent(),
                Value<bool> unavailable = const Value.absent(),
                Value<int> seenGeneration = const Value.absent(),
              }) => PlaylistEntriesTableCompanion(
                id: id,
                playlistId: playlistId,
                position: position,
                trackKey: trackKey,
                remoteItemId: remoteItemId,
                unavailable: unavailable,
                seenGeneration: seenGeneration,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int playlistId,
                required int position,
                required String trackKey,
                Value<String?> remoteItemId = const Value.absent(),
                Value<bool> unavailable = const Value.absent(),
                Value<int> seenGeneration = const Value.absent(),
              }) => PlaylistEntriesTableCompanion.insert(
                id: id,
                playlistId: playlistId,
                position: position,
                trackKey: trackKey,
                remoteItemId: remoteItemId,
                unavailable: unavailable,
                seenGeneration: seenGeneration,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistEntriesTableTable, PlaylistEntryRow>(
                    table,
                  ),
                  $$PlaylistEntriesTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({playlistId = false, trackKey = false}) {
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
                    if (playlistId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.playlistId,
                        referencedTable: $$PlaylistEntriesTableTableReferences
                            ._playlistIdTable(db),
                        referencedColumn: $$PlaylistEntriesTableTableReferences
                            ._playlistIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (trackKey) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.trackKey,
                        referencedTable: $$PlaylistEntriesTableTableReferences
                            ._trackKeyTable(db),
                        referencedColumn: $$PlaylistEntriesTableTableReferences
                            ._trackKeyTable(db)
                            .trackKey,
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

typedef $$PlaylistEntriesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistEntriesTableTable,
      PlaylistEntryRow,
      $$PlaylistEntriesTableTableFilterComposer,
      $$PlaylistEntriesTableTableOrderingComposer,
      $$PlaylistEntriesTableTableAnnotationComposer,
      $$PlaylistEntriesTableTableCreateCompanionBuilder,
      $$PlaylistEntriesTableTableUpdateCompanionBuilder,
      (PlaylistEntryRow, $$PlaylistEntriesTableTableReferences),
      PlaylistEntryRow,
      PrefetchHooks Function({bool playlistId, bool trackKey})
    >;
typedef $$PlaylistRemoteTableTableCreateCompanionBuilder =
    PlaylistRemoteTableCompanion Function({
      Value<int> playlistId,
      required String pluginId,
      required String remoteId,
      Value<String?> ownerName,
      Value<bool> writable,
      Value<bool> nameOverridden,
      Value<bool> descriptionOverridden,
      Value<bool> artworkOverridden,
      Value<int?> refreshIntervalHours,
      Value<DateTime?> lastRefreshedAt,
      Value<PlaylistRefreshResult?> lastResult,
      Value<PlaylistRemoteStatus> status,
      Value<int> refreshGeneration,
    });
typedef $$PlaylistRemoteTableTableUpdateCompanionBuilder =
    PlaylistRemoteTableCompanion Function({
      Value<int> playlistId,
      Value<String> pluginId,
      Value<String> remoteId,
      Value<String?> ownerName,
      Value<bool> writable,
      Value<bool> nameOverridden,
      Value<bool> descriptionOverridden,
      Value<bool> artworkOverridden,
      Value<int?> refreshIntervalHours,
      Value<DateTime?> lastRefreshedAt,
      Value<PlaylistRefreshResult?> lastResult,
      Value<PlaylistRemoteStatus> status,
      Value<int> refreshGeneration,
    });

final class $$PlaylistRemoteTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PlaylistRemoteTableTable,
          PlaylistRemoteRow
        > {
  $$PlaylistRemoteTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PlaylistsTableTable _playlistIdTable(_$AppDatabase db) => db
      .playlistsTable
      .createAlias('playlist_remote__playlist_id__playlists__id');

  $$PlaylistsTableTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<int>('playlist_id')!;

    final manager = $$PlaylistsTableTableTableManager(
      $_db,
      $_db.playlistsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlaylistRemoteTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistRemoteTableTable> {
  $$PlaylistRemoteTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerName => $composableBuilder(
    column: $table.ownerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get writable => $composableBuilder(
    column: $table.writable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get nameOverridden => $composableBuilder(
    column: $table.nameOverridden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get descriptionOverridden => $composableBuilder(
    column: $table.descriptionOverridden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get artworkOverridden => $composableBuilder(
    column: $table.artworkOverridden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get refreshIntervalHours => $composableBuilder(
    column: $table.refreshIntervalHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime?, DateTime, int>
  get lastRefreshedAt => $composableBuilder(
    column: $table.lastRefreshedAt,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    PlaylistRefreshResult?,
    PlaylistRefreshResult,
    String
  >
  get lastResult => $composableBuilder(
    column: $table.lastResult,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    PlaylistRemoteStatus,
    PlaylistRemoteStatus,
    String
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get refreshGeneration => $composableBuilder(
    column: $table.refreshGeneration,
    builder: (column) => ColumnFilters(column),
  );

  $$PlaylistsTableTableFilterComposer get playlistId {
    final $$PlaylistsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableFilterComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistRemoteTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistRemoteTableTable> {
  $$PlaylistRemoteTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerName => $composableBuilder(
    column: $table.ownerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get writable => $composableBuilder(
    column: $table.writable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get nameOverridden => $composableBuilder(
    column: $table.nameOverridden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get descriptionOverridden => $composableBuilder(
    column: $table.descriptionOverridden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get artworkOverridden => $composableBuilder(
    column: $table.artworkOverridden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get refreshIntervalHours => $composableBuilder(
    column: $table.refreshIntervalHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRefreshedAt => $composableBuilder(
    column: $table.lastRefreshedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastResult => $composableBuilder(
    column: $table.lastResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get refreshGeneration => $composableBuilder(
    column: $table.refreshGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlaylistsTableTableOrderingComposer get playlistId {
    final $$PlaylistsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableOrderingComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistRemoteTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistRemoteTableTable> {
  $$PlaylistRemoteTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get ownerName =>
      $composableBuilder(column: $table.ownerName, builder: (column) => column);

  GeneratedColumn<bool> get writable =>
      $composableBuilder(column: $table.writable, builder: (column) => column);

  GeneratedColumn<bool> get nameOverridden => $composableBuilder(
    column: $table.nameOverridden,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get descriptionOverridden => $composableBuilder(
    column: $table.descriptionOverridden,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get artworkOverridden => $composableBuilder(
    column: $table.artworkOverridden,
    builder: (column) => column,
  );

  GeneratedColumn<int> get refreshIntervalHours => $composableBuilder(
    column: $table.refreshIntervalHours,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DateTime?, int> get lastRefreshedAt =>
      $composableBuilder(
        column: $table.lastRefreshedAt,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<PlaylistRefreshResult?, String>
  get lastResult => $composableBuilder(
    column: $table.lastResult,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PlaylistRemoteStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get refreshGeneration => $composableBuilder(
    column: $table.refreshGeneration,
    builder: (column) => column,
  );

  $$PlaylistsTableTableAnnotationComposer get playlistId {
    final $$PlaylistsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistRemoteTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistRemoteTableTable,
          PlaylistRemoteRow,
          $$PlaylistRemoteTableTableFilterComposer,
          $$PlaylistRemoteTableTableOrderingComposer,
          $$PlaylistRemoteTableTableAnnotationComposer,
          $$PlaylistRemoteTableTableCreateCompanionBuilder,
          $$PlaylistRemoteTableTableUpdateCompanionBuilder,
          (PlaylistRemoteRow, $$PlaylistRemoteTableTableReferences),
          PlaylistRemoteRow,
          PrefetchHooks Function({bool playlistId})
        > {
  $$PlaylistRemoteTableTableTableManager(
    _$AppDatabase db,
    $PlaylistRemoteTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistRemoteTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistRemoteTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaylistRemoteTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> playlistId = const Value.absent(),
                Value<String> pluginId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String?> ownerName = const Value.absent(),
                Value<bool> writable = const Value.absent(),
                Value<bool> nameOverridden = const Value.absent(),
                Value<bool> descriptionOverridden = const Value.absent(),
                Value<bool> artworkOverridden = const Value.absent(),
                Value<int?> refreshIntervalHours = const Value.absent(),
                Value<DateTime?> lastRefreshedAt = const Value.absent(),
                Value<PlaylistRefreshResult?> lastResult = const Value.absent(),
                Value<PlaylistRemoteStatus> status = const Value.absent(),
                Value<int> refreshGeneration = const Value.absent(),
              }) => PlaylistRemoteTableCompanion(
                playlistId: playlistId,
                pluginId: pluginId,
                remoteId: remoteId,
                ownerName: ownerName,
                writable: writable,
                nameOverridden: nameOverridden,
                descriptionOverridden: descriptionOverridden,
                artworkOverridden: artworkOverridden,
                refreshIntervalHours: refreshIntervalHours,
                lastRefreshedAt: lastRefreshedAt,
                lastResult: lastResult,
                status: status,
                refreshGeneration: refreshGeneration,
              ),
          createCompanionCallback:
              ({
                Value<int> playlistId = const Value.absent(),
                required String pluginId,
                required String remoteId,
                Value<String?> ownerName = const Value.absent(),
                Value<bool> writable = const Value.absent(),
                Value<bool> nameOverridden = const Value.absent(),
                Value<bool> descriptionOverridden = const Value.absent(),
                Value<bool> artworkOverridden = const Value.absent(),
                Value<int?> refreshIntervalHours = const Value.absent(),
                Value<DateTime?> lastRefreshedAt = const Value.absent(),
                Value<PlaylistRefreshResult?> lastResult = const Value.absent(),
                Value<PlaylistRemoteStatus> status = const Value.absent(),
                Value<int> refreshGeneration = const Value.absent(),
              }) => PlaylistRemoteTableCompanion.insert(
                playlistId: playlistId,
                pluginId: pluginId,
                remoteId: remoteId,
                ownerName: ownerName,
                writable: writable,
                nameOverridden: nameOverridden,
                descriptionOverridden: descriptionOverridden,
                artworkOverridden: artworkOverridden,
                refreshIntervalHours: refreshIntervalHours,
                lastRefreshedAt: lastRefreshedAt,
                lastResult: lastResult,
                status: status,
                refreshGeneration: refreshGeneration,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaylistRemoteTableTable, PlaylistRemoteRow>(
                    table,
                  ),
                  $$PlaylistRemoteTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({playlistId = false}) {
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
                    if (playlistId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.playlistId,
                        referencedTable: $$PlaylistRemoteTableTableReferences
                            ._playlistIdTable(db),
                        referencedColumn: $$PlaylistRemoteTableTableReferences
                            ._playlistIdTable(db)
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

typedef $$PlaylistRemoteTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistRemoteTableTable,
      PlaylistRemoteRow,
      $$PlaylistRemoteTableTableFilterComposer,
      $$PlaylistRemoteTableTableOrderingComposer,
      $$PlaylistRemoteTableTableAnnotationComposer,
      $$PlaylistRemoteTableTableCreateCompanionBuilder,
      $$PlaylistRemoteTableTableUpdateCompanionBuilder,
      (PlaylistRemoteRow, $$PlaylistRemoteTableTableReferences),
      PlaylistRemoteRow,
      PrefetchHooks Function({bool playlistId})
    >;
typedef $$ChartSettingsTableTableCreateCompanionBuilder =
    ChartSettingsTableCompanion Function({
      required String pluginId,
      required String chartId,
      Value<bool?> enabled,
      Value<int?> sortOrder,
      Value<int> rowid,
    });
typedef $$ChartSettingsTableTableUpdateCompanionBuilder =
    ChartSettingsTableCompanion Function({
      Value<String> pluginId,
      Value<String> chartId,
      Value<bool?> enabled,
      Value<int?> sortOrder,
      Value<int> rowid,
    });

class $$ChartSettingsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ChartSettingsTableTable> {
  $$ChartSettingsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chartId => $composableBuilder(
    column: $table.chartId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChartSettingsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ChartSettingsTableTable> {
  $$ChartSettingsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pluginId => $composableBuilder(
    column: $table.pluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chartId => $composableBuilder(
    column: $table.chartId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChartSettingsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChartSettingsTableTable> {
  $$ChartSettingsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pluginId =>
      $composableBuilder(column: $table.pluginId, builder: (column) => column);

  GeneratedColumn<String> get chartId =>
      $composableBuilder(column: $table.chartId, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$ChartSettingsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChartSettingsTableTable,
          ChartSettingsRow,
          $$ChartSettingsTableTableFilterComposer,
          $$ChartSettingsTableTableOrderingComposer,
          $$ChartSettingsTableTableAnnotationComposer,
          $$ChartSettingsTableTableCreateCompanionBuilder,
          $$ChartSettingsTableTableUpdateCompanionBuilder,
          (
            ChartSettingsRow,
            BaseReferences<
              _$AppDatabase,
              $ChartSettingsTableTable,
              ChartSettingsRow
            >,
          ),
          ChartSettingsRow,
          PrefetchHooks Function()
        > {
  $$ChartSettingsTableTableTableManager(
    _$AppDatabase db,
    $ChartSettingsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChartSettingsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChartSettingsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChartSettingsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> pluginId = const Value.absent(),
                Value<String> chartId = const Value.absent(),
                Value<bool?> enabled = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChartSettingsTableCompanion(
                pluginId: pluginId,
                chartId: chartId,
                enabled: enabled,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pluginId,
                required String chartId,
                Value<bool?> enabled = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChartSettingsTableCompanion.insert(
                pluginId: pluginId,
                chartId: chartId,
                enabled: enabled,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChartSettingsTableTable, ChartSettingsRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ChartSettingsTableTable,
                    ChartSettingsRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChartSettingsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChartSettingsTableTable,
      ChartSettingsRow,
      $$ChartSettingsTableTableFilterComposer,
      $$ChartSettingsTableTableOrderingComposer,
      $$ChartSettingsTableTableAnnotationComposer,
      $$ChartSettingsTableTableCreateCompanionBuilder,
      $$ChartSettingsTableTableUpdateCompanionBuilder,
      (
        ChartSettingsRow,
        BaseReferences<
          _$AppDatabase,
          $ChartSettingsTableTable,
          ChartSettingsRow
        >,
      ),
      ChartSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$MatchResultsTableTableCreateCompanionBuilder =
    MatchResultsTableCompanion Function({
      required String originPluginId,
      required String originId,
      required String title,
      Value<String?> artists,
      Value<int?> durationMs,
      Value<String?> selectedTrackKey,
      Value<double?> score,
      Value<bool> userSelected,
      Value<int> rowid,
    });
typedef $$MatchResultsTableTableUpdateCompanionBuilder =
    MatchResultsTableCompanion Function({
      Value<String> originPluginId,
      Value<String> originId,
      Value<String> title,
      Value<String?> artists,
      Value<int?> durationMs,
      Value<String?> selectedTrackKey,
      Value<double?> score,
      Value<bool> userSelected,
      Value<int> rowid,
    });

final class $$MatchResultsTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $MatchResultsTableTable, MatchResultRow> {
  $$MatchResultsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TracksTableTable _selectedTrackKeyTable(_$AppDatabase db) => db
      .tracksTable
      .createAlias('match_results__selected_track_key__tracks__track_key');

  $$TracksTableTableProcessedTableManager? get selectedTrackKey {
    final $_column = $_itemColumn<String>('selected_track_key');
    if ($_column == null) return null;
    final manager = $$TracksTableTableTableManager(
      $_db,
      $_db.tracksTable,
    ).filter((f) => f.trackKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_selectedTrackKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MatchResultsTableTableFilterComposer
    extends Composer<_$AppDatabase, $MatchResultsTableTable> {
  $$MatchResultsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get originPluginId => $composableBuilder(
    column: $table.originPluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originId => $composableBuilder(
    column: $table.originId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artists => $composableBuilder(
    column: $table.artists,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get userSelected => $composableBuilder(
    column: $table.userSelected,
    builder: (column) => ColumnFilters(column),
  );

  $$TracksTableTableFilterComposer get selectedTrackKey {
    final $$TracksTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.selectedTrackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableFilterComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MatchResultsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $MatchResultsTableTable> {
  $$MatchResultsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get originPluginId => $composableBuilder(
    column: $table.originPluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originId => $composableBuilder(
    column: $table.originId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artists => $composableBuilder(
    column: $table.artists,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get userSelected => $composableBuilder(
    column: $table.userSelected,
    builder: (column) => ColumnOrderings(column),
  );

  $$TracksTableTableOrderingComposer get selectedTrackKey {
    final $$TracksTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.selectedTrackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableOrderingComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MatchResultsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $MatchResultsTableTable> {
  $$MatchResultsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get originPluginId => $composableBuilder(
    column: $table.originPluginId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originId =>
      $composableBuilder(column: $table.originId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artists =>
      $composableBuilder(column: $table.artists, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<bool> get userSelected => $composableBuilder(
    column: $table.userSelected,
    builder: (column) => column,
  );

  $$TracksTableTableAnnotationComposer get selectedTrackKey {
    final $$TracksTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.selectedTrackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableAnnotationComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MatchResultsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MatchResultsTableTable,
          MatchResultRow,
          $$MatchResultsTableTableFilterComposer,
          $$MatchResultsTableTableOrderingComposer,
          $$MatchResultsTableTableAnnotationComposer,
          $$MatchResultsTableTableCreateCompanionBuilder,
          $$MatchResultsTableTableUpdateCompanionBuilder,
          (MatchResultRow, $$MatchResultsTableTableReferences),
          MatchResultRow,
          PrefetchHooks Function({bool selectedTrackKey})
        > {
  $$MatchResultsTableTableTableManager(
    _$AppDatabase db,
    $MatchResultsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MatchResultsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MatchResultsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MatchResultsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> originPluginId = const Value.absent(),
                Value<String> originId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> artists = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> selectedTrackKey = const Value.absent(),
                Value<double?> score = const Value.absent(),
                Value<bool> userSelected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MatchResultsTableCompanion(
                originPluginId: originPluginId,
                originId: originId,
                title: title,
                artists: artists,
                durationMs: durationMs,
                selectedTrackKey: selectedTrackKey,
                score: score,
                userSelected: userSelected,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String originPluginId,
                required String originId,
                required String title,
                Value<String?> artists = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> selectedTrackKey = const Value.absent(),
                Value<double?> score = const Value.absent(),
                Value<bool> userSelected = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MatchResultsTableCompanion.insert(
                originPluginId: originPluginId,
                originId: originId,
                title: title,
                artists: artists,
                durationMs: durationMs,
                selectedTrackKey: selectedTrackKey,
                score: score,
                userSelected: userSelected,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MatchResultsTableTable, MatchResultRow>(table),
                  $$MatchResultsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({selectedTrackKey = false}) {
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
                    if (selectedTrackKey) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.selectedTrackKey,
                        referencedTable: $$MatchResultsTableTableReferences
                            ._selectedTrackKeyTable(db),
                        referencedColumn: $$MatchResultsTableTableReferences
                            ._selectedTrackKeyTable(db)
                            .trackKey,
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

typedef $$MatchResultsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MatchResultsTableTable,
      MatchResultRow,
      $$MatchResultsTableTableFilterComposer,
      $$MatchResultsTableTableOrderingComposer,
      $$MatchResultsTableTableAnnotationComposer,
      $$MatchResultsTableTableCreateCompanionBuilder,
      $$MatchResultsTableTableUpdateCompanionBuilder,
      (MatchResultRow, $$MatchResultsTableTableReferences),
      MatchResultRow,
      PrefetchHooks Function({bool selectedTrackKey})
    >;
typedef $$TrackOriginsTableTableCreateCompanionBuilder =
    TrackOriginsTableCompanion Function({
      required String trackKey,
      required String originPluginId,
      required String originId,
      Value<int> rowid,
    });
typedef $$TrackOriginsTableTableUpdateCompanionBuilder =
    TrackOriginsTableCompanion Function({
      Value<String> trackKey,
      Value<String> originPluginId,
      Value<String> originId,
      Value<int> rowid,
    });

final class $$TrackOriginsTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $TrackOriginsTableTable, TrackOriginRow> {
  $$TrackOriginsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $TracksTableTable _trackKeyTable(_$AppDatabase db) =>
      db.tracksTable.createAlias('track_origins__track_key__tracks__track_key');

  $$TracksTableTableProcessedTableManager get trackKey {
    final $_column = $_itemColumn<String>('track_key')!;

    final manager = $$TracksTableTableTableManager(
      $_db,
      $_db.tracksTable,
    ).filter((f) => f.trackKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TrackOriginsTableTableFilterComposer
    extends Composer<_$AppDatabase, $TrackOriginsTableTable> {
  $$TrackOriginsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get originPluginId => $composableBuilder(
    column: $table.originPluginId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originId => $composableBuilder(
    column: $table.originId,
    builder: (column) => ColumnFilters(column),
  );

  $$TracksTableTableFilterComposer get trackKey {
    final $$TracksTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableFilterComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackOriginsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $TrackOriginsTableTable> {
  $$TrackOriginsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get originPluginId => $composableBuilder(
    column: $table.originPluginId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originId => $composableBuilder(
    column: $table.originId,
    builder: (column) => ColumnOrderings(column),
  );

  $$TracksTableTableOrderingComposer get trackKey {
    final $$TracksTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableOrderingComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackOriginsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrackOriginsTableTable> {
  $$TrackOriginsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get originPluginId => $composableBuilder(
    column: $table.originPluginId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originId =>
      $composableBuilder(column: $table.originId, builder: (column) => column);

  $$TracksTableTableAnnotationComposer get trackKey {
    final $$TracksTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackKey,
      referencedTable: $db.tracksTable,
      getReferencedColumn: (t) => t.trackKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableTableAnnotationComposer(
            $db: $db,
            $table: $db.tracksTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackOriginsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrackOriginsTableTable,
          TrackOriginRow,
          $$TrackOriginsTableTableFilterComposer,
          $$TrackOriginsTableTableOrderingComposer,
          $$TrackOriginsTableTableAnnotationComposer,
          $$TrackOriginsTableTableCreateCompanionBuilder,
          $$TrackOriginsTableTableUpdateCompanionBuilder,
          (TrackOriginRow, $$TrackOriginsTableTableReferences),
          TrackOriginRow,
          PrefetchHooks Function({bool trackKey})
        > {
  $$TrackOriginsTableTableTableManager(
    _$AppDatabase db,
    $TrackOriginsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackOriginsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackOriginsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackOriginsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> trackKey = const Value.absent(),
                Value<String> originPluginId = const Value.absent(),
                Value<String> originId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrackOriginsTableCompanion(
                trackKey: trackKey,
                originPluginId: originPluginId,
                originId: originId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackKey,
                required String originPluginId,
                required String originId,
                Value<int> rowid = const Value.absent(),
              }) => TrackOriginsTableCompanion.insert(
                trackKey: trackKey,
                originPluginId: originPluginId,
                originId: originId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TrackOriginsTableTable, TrackOriginRow>(table),
                  $$TrackOriginsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackKey = false}) {
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
                    if (trackKey) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.trackKey,
                        referencedTable: $$TrackOriginsTableTableReferences
                            ._trackKeyTable(db),
                        referencedColumn: $$TrackOriginsTableTableReferences
                            ._trackKeyTable(db)
                            .trackKey,
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

typedef $$TrackOriginsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrackOriginsTableTable,
      TrackOriginRow,
      $$TrackOriginsTableTableFilterComposer,
      $$TrackOriginsTableTableOrderingComposer,
      $$TrackOriginsTableTableAnnotationComposer,
      $$TrackOriginsTableTableCreateCompanionBuilder,
      $$TrackOriginsTableTableUpdateCompanionBuilder,
      (TrackOriginRow, $$TrackOriginsTableTableReferences),
      TrackOriginRow,
      PrefetchHooks Function({bool trackKey})
    >;
typedef $$LegacyImportsTableTableCreateCompanionBuilder =
    LegacyImportsTableCompanion Function({
      Value<int> id,
      required LegacyImportSource source,
      required DateTime importedAt,
      Value<int?> legacySchemaVersion,
      Value<int?> backupVersion,
      required String summaryJson,
      Value<bool> acknowledged,
    });
typedef $$LegacyImportsTableTableUpdateCompanionBuilder =
    LegacyImportsTableCompanion Function({
      Value<int> id,
      Value<LegacyImportSource> source,
      Value<DateTime> importedAt,
      Value<int?> legacySchemaVersion,
      Value<int?> backupVersion,
      Value<String> summaryJson,
      Value<bool> acknowledged,
    });

final class $$LegacyImportsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $LegacyImportsTableTable,
          LegacyImportRow
        > {
  $$LegacyImportsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $LegacyPlaylistIdsTableTable,
    List<LegacyPlaylistIdRow>
  >
  _legacyPlaylistIdsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.legacyPlaylistIdsTable,
        aliasName: 'legacy_imports__id__legacy_playlist_ids__legacy_import_id',
      );

  $$LegacyPlaylistIdsTableTableProcessedTableManager
  get legacyPlaylistIdsTableRefs {
    final manager = $$LegacyPlaylistIdsTableTableTableManager(
      $_db,
      $_db.legacyPlaylistIdsTable,
    ).filter((f) => f.legacyImportId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _legacyPlaylistIdsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LegacyImportsTableTableFilterComposer
    extends Composer<_$AppDatabase, $LegacyImportsTableTable> {
  $$LegacyImportsTableTableFilterComposer({
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

  ColumnWithTypeConverterFilters<LegacyImportSource, LegacyImportSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<DateTime, DateTime, int> get importedAt =>
      $composableBuilder(
        column: $table.importedAt,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get legacySchemaVersion => $composableBuilder(
    column: $table.legacySchemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> legacyPlaylistIdsTableRefs(
    Expression<bool> Function($$LegacyPlaylistIdsTableTableFilterComposer f) f,
  ) {
    final $$LegacyPlaylistIdsTableTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.legacyPlaylistIdsTable,
          getReferencedColumn: (t) => t.legacyImportId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LegacyPlaylistIdsTableTableFilterComposer(
                $db: $db,
                $table: $db.legacyPlaylistIdsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$LegacyImportsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $LegacyImportsTableTable> {
  $$LegacyImportsTableTableOrderingComposer({
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

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get legacySchemaVersion => $composableBuilder(
    column: $table.legacySchemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LegacyImportsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $LegacyImportsTableTable> {
  $$LegacyImportsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LegacyImportSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DateTime, int> get importedAt =>
      $composableBuilder(
        column: $table.importedAt,
        builder: (column) => column,
      );

  GeneratedColumn<int> get legacySchemaVersion => $composableBuilder(
    column: $table.legacySchemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get backupVersion => $composableBuilder(
    column: $table.backupVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summaryJson => $composableBuilder(
    column: $table.summaryJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => column,
  );

  Expression<T> legacyPlaylistIdsTableRefs<T extends Object>(
    Expression<T> Function($$LegacyPlaylistIdsTableTableAnnotationComposer a) f,
  ) {
    final $$LegacyPlaylistIdsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.legacyPlaylistIdsTable,
          getReferencedColumn: (t) => t.legacyImportId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LegacyPlaylistIdsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.legacyPlaylistIdsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$LegacyImportsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LegacyImportsTableTable,
          LegacyImportRow,
          $$LegacyImportsTableTableFilterComposer,
          $$LegacyImportsTableTableOrderingComposer,
          $$LegacyImportsTableTableAnnotationComposer,
          $$LegacyImportsTableTableCreateCompanionBuilder,
          $$LegacyImportsTableTableUpdateCompanionBuilder,
          (LegacyImportRow, $$LegacyImportsTableTableReferences),
          LegacyImportRow,
          PrefetchHooks Function({bool legacyPlaylistIdsTableRefs})
        > {
  $$LegacyImportsTableTableTableManager(
    _$AppDatabase db,
    $LegacyImportsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LegacyImportsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LegacyImportsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LegacyImportsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<LegacyImportSource> source = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<int?> legacySchemaVersion = const Value.absent(),
                Value<int?> backupVersion = const Value.absent(),
                Value<String> summaryJson = const Value.absent(),
                Value<bool> acknowledged = const Value.absent(),
              }) => LegacyImportsTableCompanion(
                id: id,
                source: source,
                importedAt: importedAt,
                legacySchemaVersion: legacySchemaVersion,
                backupVersion: backupVersion,
                summaryJson: summaryJson,
                acknowledged: acknowledged,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required LegacyImportSource source,
                required DateTime importedAt,
                Value<int?> legacySchemaVersion = const Value.absent(),
                Value<int?> backupVersion = const Value.absent(),
                required String summaryJson,
                Value<bool> acknowledged = const Value.absent(),
              }) => LegacyImportsTableCompanion.insert(
                id: id,
                source: source,
                importedAt: importedAt,
                legacySchemaVersion: legacySchemaVersion,
                backupVersion: backupVersion,
                summaryJson: summaryJson,
                acknowledged: acknowledged,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LegacyImportsTableTable, LegacyImportRow>(table),
                  $$LegacyImportsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({legacyPlaylistIdsTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (legacyPlaylistIdsTableRefs) db.legacyPlaylistIdsTable,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (legacyPlaylistIdsTableRefs)
                    await $_getPrefetchedData<
                      LegacyImportRow,
                      $LegacyImportsTableTable,
                      LegacyPlaylistIdRow
                    >(
                      currentTable: table,
                      referencedTable: $$LegacyImportsTableTableReferences
                          ._legacyPlaylistIdsTableRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LegacyImportsTableTableReferences(
                            db,
                            table,
                            p0,
                          ).legacyPlaylistIdsTableRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.legacyImportId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LegacyImportsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LegacyImportsTableTable,
      LegacyImportRow,
      $$LegacyImportsTableTableFilterComposer,
      $$LegacyImportsTableTableOrderingComposer,
      $$LegacyImportsTableTableAnnotationComposer,
      $$LegacyImportsTableTableCreateCompanionBuilder,
      $$LegacyImportsTableTableUpdateCompanionBuilder,
      (LegacyImportRow, $$LegacyImportsTableTableReferences),
      LegacyImportRow,
      PrefetchHooks Function({bool legacyPlaylistIdsTableRefs})
    >;
typedef $$LegacyPlaylistIdsTableTableCreateCompanionBuilder =
    LegacyPlaylistIdsTableCompanion Function({
      required int legacyImportId,
      required int legacyPlaylistId,
      required int playlistId,
      Value<int> rowid,
    });
typedef $$LegacyPlaylistIdsTableTableUpdateCompanionBuilder =
    LegacyPlaylistIdsTableCompanion Function({
      Value<int> legacyImportId,
      Value<int> legacyPlaylistId,
      Value<int> playlistId,
      Value<int> rowid,
    });

final class $$LegacyPlaylistIdsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $LegacyPlaylistIdsTableTable,
          LegacyPlaylistIdRow
        > {
  $$LegacyPlaylistIdsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LegacyImportsTableTable _legacyImportIdTable(_$AppDatabase db) => db
      .legacyImportsTable
      .createAlias('legacy_playlist_ids__legacy_import_id__legacy_imports__id');

  $$LegacyImportsTableTableProcessedTableManager get legacyImportId {
    final $_column = $_itemColumn<int>('legacy_import_id')!;

    final manager = $$LegacyImportsTableTableTableManager(
      $_db,
      $_db.legacyImportsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_legacyImportIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PlaylistsTableTable _playlistIdTable(_$AppDatabase db) => db
      .playlistsTable
      .createAlias('legacy_playlist_ids__playlist_id__playlists__id');

  $$PlaylistsTableTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<int>('playlist_id')!;

    final manager = $$PlaylistsTableTableTableManager(
      $_db,
      $_db.playlistsTable,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LegacyPlaylistIdsTableTableFilterComposer
    extends Composer<_$AppDatabase, $LegacyPlaylistIdsTableTable> {
  $$LegacyPlaylistIdsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get legacyPlaylistId => $composableBuilder(
    column: $table.legacyPlaylistId,
    builder: (column) => ColumnFilters(column),
  );

  $$LegacyImportsTableTableFilterComposer get legacyImportId {
    final $$LegacyImportsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.legacyImportId,
      referencedTable: $db.legacyImportsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LegacyImportsTableTableFilterComposer(
            $db: $db,
            $table: $db.legacyImportsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PlaylistsTableTableFilterComposer get playlistId {
    final $$PlaylistsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableFilterComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LegacyPlaylistIdsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $LegacyPlaylistIdsTableTable> {
  $$LegacyPlaylistIdsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get legacyPlaylistId => $composableBuilder(
    column: $table.legacyPlaylistId,
    builder: (column) => ColumnOrderings(column),
  );

  $$LegacyImportsTableTableOrderingComposer get legacyImportId {
    final $$LegacyImportsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.legacyImportId,
      referencedTable: $db.legacyImportsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LegacyImportsTableTableOrderingComposer(
            $db: $db,
            $table: $db.legacyImportsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PlaylistsTableTableOrderingComposer get playlistId {
    final $$PlaylistsTableTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableOrderingComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LegacyPlaylistIdsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $LegacyPlaylistIdsTableTable> {
  $$LegacyPlaylistIdsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get legacyPlaylistId => $composableBuilder(
    column: $table.legacyPlaylistId,
    builder: (column) => column,
  );

  $$LegacyImportsTableTableAnnotationComposer get legacyImportId {
    final $$LegacyImportsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.legacyImportId,
          referencedTable: $db.legacyImportsTable,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LegacyImportsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.legacyImportsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$PlaylistsTableTableAnnotationComposer get playlistId {
    final $$PlaylistsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlistsTable,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LegacyPlaylistIdsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LegacyPlaylistIdsTableTable,
          LegacyPlaylistIdRow,
          $$LegacyPlaylistIdsTableTableFilterComposer,
          $$LegacyPlaylistIdsTableTableOrderingComposer,
          $$LegacyPlaylistIdsTableTableAnnotationComposer,
          $$LegacyPlaylistIdsTableTableCreateCompanionBuilder,
          $$LegacyPlaylistIdsTableTableUpdateCompanionBuilder,
          (LegacyPlaylistIdRow, $$LegacyPlaylistIdsTableTableReferences),
          LegacyPlaylistIdRow,
          PrefetchHooks Function({bool legacyImportId, bool playlistId})
        > {
  $$LegacyPlaylistIdsTableTableTableManager(
    _$AppDatabase db,
    $LegacyPlaylistIdsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LegacyPlaylistIdsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LegacyPlaylistIdsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LegacyPlaylistIdsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> legacyImportId = const Value.absent(),
                Value<int> legacyPlaylistId = const Value.absent(),
                Value<int> playlistId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LegacyPlaylistIdsTableCompanion(
                legacyImportId: legacyImportId,
                legacyPlaylistId: legacyPlaylistId,
                playlistId: playlistId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int legacyImportId,
                required int legacyPlaylistId,
                required int playlistId,
                Value<int> rowid = const Value.absent(),
              }) => LegacyPlaylistIdsTableCompanion.insert(
                legacyImportId: legacyImportId,
                legacyPlaylistId: legacyPlaylistId,
                playlistId: playlistId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LegacyPlaylistIdsTableTable,
                    LegacyPlaylistIdRow
                  >(table),
                  $$LegacyPlaylistIdsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({legacyImportId = false, playlistId = false}) {
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
                        if (legacyImportId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.legacyImportId,
                            referencedTable:
                                $$LegacyPlaylistIdsTableTableReferences
                                    ._legacyImportIdTable(db),
                            referencedColumn:
                                $$LegacyPlaylistIdsTableTableReferences
                                    ._legacyImportIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (playlistId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.playlistId,
                            referencedTable:
                                $$LegacyPlaylistIdsTableTableReferences
                                    ._playlistIdTable(db),
                            referencedColumn:
                                $$LegacyPlaylistIdsTableTableReferences
                                    ._playlistIdTable(db)
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

typedef $$LegacyPlaylistIdsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LegacyPlaylistIdsTableTable,
      LegacyPlaylistIdRow,
      $$LegacyPlaylistIdsTableTableFilterComposer,
      $$LegacyPlaylistIdsTableTableOrderingComposer,
      $$LegacyPlaylistIdsTableTableAnnotationComposer,
      $$LegacyPlaylistIdsTableTableCreateCompanionBuilder,
      $$LegacyPlaylistIdsTableTableUpdateCompanionBuilder,
      (LegacyPlaylistIdRow, $$LegacyPlaylistIdsTableTableReferences),
      LegacyPlaylistIdRow,
      PrefetchHooks Function({bool legacyImportId, bool playlistId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AppearanceSettingsTableTableTableManager get appearanceSettingsTable =>
      $$AppearanceSettingsTableTableTableManager(
        _db,
        _db.appearanceSettingsTable,
      );
  $$NetworkSettingsTableTableTableManager get networkSettingsTable =>
      $$NetworkSettingsTableTableTableManager(_db, _db.networkSettingsTable);
  $$PlaybackSettingsTableTableTableManager get playbackSettingsTable =>
      $$PlaybackSettingsTableTableTableManager(_db, _db.playbackSettingsTable);
  $$InstalledPluginsTableTableTableManager get installedPluginsTable =>
      $$InstalledPluginsTableTableTableManager(_db, _db.installedPluginsTable);
  $$PluginIndexesTableTableTableManager get pluginIndexesTable =>
      $$PluginIndexesTableTableTableManager(_db, _db.pluginIndexesTable);
  $$PluginStorageTableTableTableManager get pluginStorageTable =>
      $$PluginStorageTableTableTableManager(_db, _db.pluginStorageTable);
  $$TracksTableTableTableManager get tracksTable =>
      $$TracksTableTableTableManager(_db, _db.tracksTable);
  $$QueueEntriesTableTableTableManager get queueEntriesTable =>
      $$QueueEntriesTableTableTableManager(_db, _db.queueEntriesTable);
  $$PlayerStateTableTableTableManager get playerStateTable =>
      $$PlayerStateTableTableTableManager(_db, _db.playerStateTable);
  $$PlayHistoryTableTableTableManager get playHistoryTable =>
      $$PlayHistoryTableTableTableManager(_db, _db.playHistoryTable);
  $$LayoutStateTableTableTableManager get layoutStateTable =>
      $$LayoutStateTableTableTableManager(_db, _db.layoutStateTable);
  $$AccountsTableTableTableManager get accountsTable =>
      $$AccountsTableTableTableManager(_db, _db.accountsTable);
  $$SourceSettingsTableTableTableManager get sourceSettingsTable =>
      $$SourceSettingsTableTableTableManager(_db, _db.sourceSettingsTable);
  $$DeveloperSettingsTableTableTableManager get developerSettingsTable =>
      $$DeveloperSettingsTableTableTableManager(
        _db,
        _db.developerSettingsTable,
      );
  $$SchedulerRunsTableTableTableManager get schedulerRunsTable =>
      $$SchedulerRunsTableTableTableManager(_db, _db.schedulerRunsTable);
  $$RadioStationsTableTableTableManager get radioStationsTable =>
      $$RadioStationsTableTableTableManager(_db, _db.radioStationsTable);
  $$PlaylistsTableTableTableManager get playlistsTable =>
      $$PlaylistsTableTableTableManager(_db, _db.playlistsTable);
  $$PlaylistEntriesTableTableTableManager get playlistEntriesTable =>
      $$PlaylistEntriesTableTableTableManager(_db, _db.playlistEntriesTable);
  $$PlaylistRemoteTableTableTableManager get playlistRemoteTable =>
      $$PlaylistRemoteTableTableTableManager(_db, _db.playlistRemoteTable);
  $$ChartSettingsTableTableTableManager get chartSettingsTable =>
      $$ChartSettingsTableTableTableManager(_db, _db.chartSettingsTable);
  $$MatchResultsTableTableTableManager get matchResultsTable =>
      $$MatchResultsTableTableTableManager(_db, _db.matchResultsTable);
  $$TrackOriginsTableTableTableManager get trackOriginsTable =>
      $$TrackOriginsTableTableTableManager(_db, _db.trackOriginsTable);
  $$LegacyImportsTableTableTableManager get legacyImportsTable =>
      $$LegacyImportsTableTableTableManager(_db, _db.legacyImportsTable);
  $$LegacyPlaylistIdsTableTableTableManager get legacyPlaylistIdsTable =>
      $$LegacyPlaylistIdsTableTableTableManager(
        _db,
        _db.legacyPlaylistIdsTable,
      );
}
