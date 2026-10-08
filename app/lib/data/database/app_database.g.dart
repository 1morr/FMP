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
  @override
  List<GeneratedColumn> get $columns => [id, cacheLimitMb];
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
  const NetworkSettingsRow({required this.id, this.cacheLimitMb});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cacheLimitMb != null) {
      map['cache_limit_mb'] = Variable<int>(cacheLimitMb);
    }
    return map;
  }

  NetworkSettingsTableCompanion toCompanion(bool nullToAbsent) {
    return NetworkSettingsTableCompanion(
      id: Value(id),
      cacheLimitMb: cacheLimitMb == null && nullToAbsent
          ? const Value.absent()
          : Value(cacheLimitMb),
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
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cacheLimitMb': serializer.toJson<int?>(cacheLimitMb),
    };
  }

  NetworkSettingsRow copyWith({
    int? id,
    Value<int?> cacheLimitMb = const Value.absent(),
  }) => NetworkSettingsRow(
    id: id ?? this.id,
    cacheLimitMb: cacheLimitMb.present ? cacheLimitMb.value : this.cacheLimitMb,
  );
  NetworkSettingsRow copyWithCompanion(NetworkSettingsTableCompanion data) {
    return NetworkSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      cacheLimitMb: data.cacheLimitMb.present
          ? data.cacheLimitMb.value
          : this.cacheLimitMb,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NetworkSettingsRow(')
          ..write('id: $id, ')
          ..write('cacheLimitMb: $cacheLimitMb')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cacheLimitMb);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkSettingsRow &&
          other.id == this.id &&
          other.cacheLimitMb == this.cacheLimitMb);
}

class NetworkSettingsTableCompanion
    extends UpdateCompanion<NetworkSettingsRow> {
  final Value<int> id;
  final Value<int?> cacheLimitMb;
  const NetworkSettingsTableCompanion({
    this.id = const Value.absent(),
    this.cacheLimitMb = const Value.absent(),
  });
  NetworkSettingsTableCompanion.insert({
    this.id = const Value.absent(),
    this.cacheLimitMb = const Value.absent(),
  });
  static Insertable<NetworkSettingsRow> custom({
    Expression<int>? id,
    Expression<int>? cacheLimitMb,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cacheLimitMb != null) 'cache_limit_mb': cacheLimitMb,
    });
  }

  NetworkSettingsTableCompanion copyWith({
    Value<int>? id,
    Value<int?>? cacheLimitMb,
  }) {
    return NetworkSettingsTableCompanion(
      id: id ?? this.id,
      cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
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
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NetworkSettingsTableCompanion(')
          ..write('id: $id, ')
          ..write('cacheLimitMb: $cacheLimitMb')
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
  const InstalledPluginRow({
    required this.id,
    required this.version,
    required this.manifestJson,
    required this.script,
    required this.installedAt,
    required this.enabled,
    this.sourceIndexUrl,
    this.checksJson,
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
          ..write('checksJson: $checksJson')
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
          other.checksJson == this.checksJson);
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
          ..write('updatedAt: $updatedAt')
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
          other.updatedAt == this.updatedAt);
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
  final DateTime updatedAt;
  const PlayerStateRow({
    required this.id,
    this.currentPosition,
    required this.positionMs,
    required this.loopMode,
    required this.shuffleEnabled,
    required this.volume,
    required this.muted,
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
  final Value<DateTime> updatedAt;
  const PlayerStateTableCompanion({
    this.id = const Value.absent(),
    this.currentPosition = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.loopMode = const Value.absent(),
    this.shuffleEnabled = const Value.absent(),
    this.volume = const Value.absent(),
    this.muted = const Value.absent(),
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
    queueEntriesTrackKey,
    playHistoryPlayedAt,
    playHistoryTrackKey,
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
typedef $$NetworkSettingsTableTableCreateCompanionBuilder =
    NetworkSettingsTableCompanion Function({
      Value<int> id,
      Value<int?> cacheLimitMb,
    });
typedef $$NetworkSettingsTableTableUpdateCompanionBuilder =
    NetworkSettingsTableCompanion Function({
      Value<int> id,
      Value<int?> cacheLimitMb,
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
              }) => NetworkSettingsTableCompanion(
                id: id,
                cacheLimitMb: cacheLimitMb,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> cacheLimitMb = const Value.absent(),
              }) => NetworkSettingsTableCompanion.insert(
                id: id,
                cacheLimitMb: cacheLimitMb,
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
              ({queueEntriesTableRefs = false, playHistoryTableRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (queueEntriesTableRefs) db.queueEntriesTable,
                    if (playHistoryTableRefs) db.playHistoryTable,
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
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlayerStateTableCompanion(
                id: id,
                currentPosition: currentPosition,
                positionMs: positionMs,
                loopMode: loopMode,
                shuffleEnabled: shuffleEnabled,
                volume: volume,
                muted: muted,
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
                required DateTime updatedAt,
              }) => PlayerStateTableCompanion.insert(
                id: id,
                currentPosition: currentPosition,
                positionMs: positionMs,
                loopMode: loopMode,
                shuffleEnabled: shuffleEnabled,
                volume: volume,
                muted: muted,
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
}
