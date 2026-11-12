import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/core/redaction/redact.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

import 'no_network.dart';

/// 插件契約測試的 fixture（plan §3）：一個插件能力的一個案例，
/// `plugins/<插件 id>/fixtures/<插件能力>/<案例>.json`。
///
/// 格式照 VCR 的 cassette（一串請求與回應），加上呼叫插件能力的參數：
///
/// ```json
/// {
///   "input": {"query": "lemon"},
///   "recorded": "2026-11-12",
///   "interactions": [
///     {
///       "request": {"method": "GET", "url": "https://…"},
///       "response": {"status": 200, "headers": {"content-type": "…"}, "body": "…"}
///     }
///   ]
/// }
/// ```
class PluginFixture {
  PluginFixture({
    required this.input,
    required this.interactions,
    this.recorded,
  });

  /// 解析 fixture；只有 `input` 的檔是還沒錄的新案例。格式不對時丟
  /// [FormatException]。
  factory PluginFixture.parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic> || json['input'] is! Map) {
      throw const FormatException('a fixture needs an "input" object');
    }
    final interactions = json['interactions'] ?? const <Object>[];
    if (interactions is! List) {
      throw const FormatException('"interactions" must be a list');
    }
    return PluginFixture(
      input: Map<String, Object?>.from(json['input'] as Map),
      recorded: json['recorded'] as String?,
      interactions: [
        for (final i in interactions) Interaction._fromJson(i as Map),
      ],
    );
  }

  /// 插件能力的參數，和宿主傳給插件的一樣（例如 search 的 `query`）。
  final Map<String, Object?> input;

  /// 錄製的日期（`YYYY-MM-DD`）。
  final String? recorded;

  final List<Interaction> interactions;

  /// 回應內文只留 [keep] 列的欄位（[keepFields]）的副本。內文不是 JSON 時
  /// 丟 [FormatException]：裁不了，就不該寫檔。
  PluginFixture trimmed(List<String> keep) => PluginFixture(
    input: input,
    recorded: recorded,
    interactions: [
      for (final i in interactions)
        Interaction(
          method: i.method,
          url: i.url,
          status: i.status,
          headers: i.headers,
          body: jsonEncode(keepFields(jsonDecode(i.body), keep)),
        ),
    ],
  );

  /// 寫檔用的文字：兩格縮排、結尾換行。
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert({
        'input': input,
        'recorded': ?recorded,
        'interactions': [for (final i in interactions) i._toJson()],
      })}\n';
}

/// 一次請求與它的回應。[url] 與 [body] 是遮蔽過的文字。
class Interaction {
  const Interaction({
    required this.method,
    required this.url,
    required this.status,
    required this.headers,
    required this.body,
  });

  factory Interaction._fromJson(Map<dynamic, dynamic> json) {
    try {
      final request = json['request'] as Map;
      final response = json['response'] as Map;
      return Interaction(
        method: request['method'] as String,
        url: request['url'] as String,
        status: response['status'] as int,
        headers: Map<String, String>.from(
          response['headers'] as Map? ?? const {},
        ),
        body: response['body'] as String,
      );
    } on TypeError {
      throw const FormatException('an interaction needs request and response');
    }
  }

  final String method;
  final String url;
  final int status;

  /// 名稱小寫。
  final Map<String, String> headers;
  final String body;

  String get request => '$method $url';

  Map<String, Object?> _toJson() => {
    'request': {'method': method, 'url': url},
    'response': {'status': status, 'headers': headers, 'body': body},
  };
}

/// 用 [fixture] 回應宿主網路的請求，零聯網。請求以方法加遮蔽後的網址比對
/// （fixture 裡的網址錄製時已遮蔽，[redact] 對遮過的文字結果不變），每筆只
/// 用一次。對不上的請求記在 [unmatched]，那次請求失敗。
///
/// 不比對請求的 header 與 body（目前宿主網路只有 GET）。網址裡每次都變、又
/// 不遮的參數（例如 B 站 WBI 簽名的 `wts`、`w_rid`）會讓重播永遠對不上：
/// 用到這種端點的插件能力要先決定怎麼比對。
class FixtureReplay implements HttpClientAdapter {
  FixtureReplay(this.fixture);

  final PluginFixture fixture;
  final unmatched = <String>[];
  final _used = <int>{};

  /// 沒被用到的錄製請求。
  List<Interaction> get unused => [
    for (final (i, interaction) in fixture.interactions.indexed)
      if (!_used.contains(i)) interaction,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = redact(options.uri.toString());
    for (final (i, interaction) in fixture.interactions.indexed) {
      if (!_used.contains(i) &&
          interaction.method == options.method &&
          interaction.url == url) {
        _used.add(i);
        return ResponseBody.fromString(
          interaction.body,
          interaction.status,
          headers: {
            for (final MapEntry(:key, :value) in interaction.headers.entries)
              key: [value],
          },
        );
      }
    }
    final request = '${options.method} $url';
    unmatched.add(request);
    throw StateError('no fixture for $request');
  }

  @override
  void close({bool force = false}) {}
}

/// 對 [plugin] 呼叫 [capability]，回傳違反契約的地方。插件或音源失敗時
/// 照原樣丟出 `AppError`；[input] 的形狀不對時丟 [FormatException]。
///
/// 新增插件能力時這個 switch 不完整、編譯不過，提醒要補它的契約。
Future<List<String>> checkContract(
  Plugin plugin,
  PluginCapability capability,
  Map<String, Object?> input,
) async {
  switch (capability) {
    case PluginCapability.search:
      final query = input['query'];
      if (query is! String) {
        throw const FormatException('search input needs a "query" string');
      }
      return searchContractViolations(
        plugin.manifest.id,
        await plugin.search(query),
      );
  }
}

/// 插件能力 search 的契約（`app/plugins/host.d.ts`）：錄製的案例有結果，
/// 每首曲目屬於這個插件、有 id 與標題，時長不知道就不給，給了就是正的。
List<String> searchContractViolations(String pluginId, List<Track> tracks) => [
  if (tracks.isEmpty) 'search returned no tracks',
  for (final (i, t) in tracks.indexed) ...[
    if (t.source != pluginId) 'track $i: source is "${t.source}"',
    if (t.id.isEmpty) 'track $i: empty id',
    if (t.title.trim().isEmpty) 'track $i: empty title',
    if (t.duration case final d? when d <= Duration.zero)
      'track $i: duration $d is not positive',
  ],
];

/// 對 [bundle] 的插件跑 [capability] 的契約，網路經 [httpAdapter]。回傳
/// 插件丟的錯誤與違反契約的地方；空的就是通過。
Future<List<String>> runContract(
  PluginBundle bundle,
  PluginCapability capability,
  Map<String, Object?> input, {
  required Log log,
  required HttpClientAdapter httpAdapter,
}) async {
  final host = PluginHost(
    bundles: [bundle],
    log: log,
    httpAdapter: httpAdapter,
  );
  try {
    if (host.plugins.isEmpty) return ['the plugin did not load; see the log'];
    return await checkContract(host.plugins.single, capability, input);
  } catch (e) {
    return ['${capability.name} threw $e'];
  } finally {
    await host.close();
  }
}

/// 用 [fixture] 重播跑 [runContract]，再加上沒有 fixture 的請求與沒用到的
/// 錄製請求。有請求沒有 fixture 時，插件因此丟的錯不另外列。空的就是通過。
Future<List<String>> runContractCase(
  PluginBundle bundle,
  PluginCapability capability,
  PluginFixture fixture, {
  required Log log,
}) async {
  final replay = FixtureReplay(fixture);
  final problems = await runContract(
    bundle,
    capability,
    fixture.input,
    log: log,
    httpAdapter: replay,
  );
  return [
    for (final request in replay.unmatched) 'no fixture for $request',
    if (replay.unmatched.isEmpty) ...problems,
    for (final i in replay.unused) 'unused fixture request ${i.request}',
  ];
}

/// 錄製：把請求交給 [inner]（錄製時是真的網路），回應照原樣交回插件，
/// 同時把遮蔽過的請求與回應記在 [recorded]。原始的值不留在這裡，寫檔只寫
/// [recorded]。回應的 header 只留宿主讀的 [recordedHeaders]：其他的
/// （`set-cookie`、CDN 的追蹤 header）宿主用不到，也可能帶著 IP。
class RecordingHttp implements HttpClientAdapter {
  RecordingHttp(this.inner);

  static const recordedHeaders = {'content-type', 'location'};

  final HttpClientAdapter inner;
  final recorded = <Interaction>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await inner.fetch(options, requestStream, cancelFuture);
    final bytes = await response.stream.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (b, chunk) => b..add(chunk),
    );
    final body = bytes.takeBytes();
    recorded.add(
      Interaction(
        method: options.method,
        url: redact(options.uri.toString()),
        status: response.statusCode,
        headers: {
          for (final MapEntry(:key, :value) in response.headers.entries)
            if (recordedHeaders.contains(key.toLowerCase()))
              key.toLowerCase(): redact(value.join(', ')),
        },
        body: redact(utf8.decode(body, allowMalformed: true)),
      ),
    );
    return ResponseBody.fromBytes(
      body,
      response.statusCode,
      headers: response.headers,
      statusMessage: response.statusMessage,
      isRedirect: response.isRedirect,
    );
  }

  /// 錄了哪些請求，一行一個（已遮蔽），給手動執行的人看。
  String get summary =>
      recorded.map((i) => '  ${i.request} -> ${i.status}').join('\n');

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// 打真實網路的 [RecordingHttp]，只給 `live` tag 的測試用。
RecordingHttp liveRecording() =>
    RecordingHttp(IOHttpClientAdapter(createHttpClient: realHttpClient));

/// 只留 [paths] 列的欄位，key 的順序照原本的（照 MongoDB projection 的
/// 慣例）：路徑以 `.` 分隔，遇到陣列就套到每個元素；路徑指到物件時整個留下；
/// 不存在的路徑略過。
///
/// fixture 的回應內文只留插件會讀的欄位（擁有者 2026-11-12）：音源回應裡的
/// 使用者 id、頭像網址、追蹤用的 id 插件用不到，不進公開 repo。
Object? keepFields(Object? value, List<String> paths) =>
    _keep(value, [for (final p in paths) p.split('.')]);

Object? _keep(Object? value, List<List<String>> paths) {
  if (paths.any((p) => p.isEmpty)) return value;
  return switch (value) {
    List<dynamic> list => [for (final e in list) _keep(e, paths)],
    Map<String, dynamic> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (paths.any((p) => p.first == key))
          key: _keep(value, [
            for (final p in paths)
              if (p.first == key) p.sublist(1),
          ]),
    },
    _ => value,
  };
}

/// 提交的 fixture 是否裁過：回應內文要是 JSON，而且只有 [keep] 列的欄位。
List<String> untrimmedResponses(PluginFixture fixture, List<String> keep) {
  final problems = <String>[];
  for (final (i, interaction) in fixture.interactions.indexed) {
    final Object? json;
    try {
      json = jsonDecode(interaction.body);
    } on FormatException {
      problems.add(
        'interactions[$i] body is not JSON, so it cannot be trimmed',
      );
      continue;
    }
    if (jsonEncode(keepFields(json, keep)) != jsonEncode(json)) {
      problems.add('interactions[$i] keeps fields outside keep.json');
    }
  }
  return problems;
}

/// fixture 裡沒遮到的 cookie、token、簽名網址：回傳遮蔽函式（[redact]）還會
/// 改動的地方。遮過的 fixture 每個字串都是 [redact] 的不動點；整份文字也查
/// 一次，抓到值不是字串、或敏感名稱是 JSON 鍵的情況（例如
/// `"set-cookie": "…"`）。字串裡的 JSON（回應內文）要解開來查，跳脫的引號
/// 會讓整份文字的檢查看不到它。
List<String> unredactedValues(String source) {
  final found = <String>[];
  void walk(Object? value, String path) {
    switch (value) {
      case String s when redact(s) != s:
        found.add(path);
      case Map<String, dynamic> m:
        for (final MapEntry(:key, :value) in m.entries) {
          walk(value, path.isEmpty ? key : '$path.$key');
        }
      case List<dynamic> l:
        for (final (i, e) in l.indexed) {
          walk(e, '$path[$i]');
        }
    }
  }

  walk(jsonDecode(source), '');
  final redacted = redact(source);
  if (found.isEmpty && redacted != source) {
    // 遮蔽可能把多行的值換成一行，之後的行號就對不上，所以只報第一處。
    final before = source.split('\n');
    final after = redacted.split('\n');
    var line = 0;
    while (line < before.length &&
        line < after.length &&
        before[line] == after[line]) {
      line++;
    }
    found.add('line ${line + 1}');
  }
  return found;
}

/// `app/plugins/` 底下的一個插件：有 `manifest.json` 的子目錄（和
/// `build.mjs`、`bundled_plugins.dart` 的認法一樣）。
class PluginDirectory {
  PluginDirectory._(this.dir, this.bundle, this.manifest);

  final Directory dir;

  /// manifest 與提交的打包產物 `dist/plugin.js`。
  final PluginBundle bundle;
  final PluginManifest manifest;

  String get id => manifest.id;
}

/// [root]（通常是 `plugins`）底下的插件，依目錄名排序。
List<PluginDirectory> pluginDirectories(Directory root) {
  final dirs = [
    for (final dir in root.listSync().whereType<Directory>())
      if (File('${dir.path}/manifest.json').existsSync()) dir,
  ]..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final dir in dirs)
      () {
        final manifest = File('${dir.path}/manifest.json').readAsStringSync();
        final code = File('${dir.path}/dist/plugin.js').readAsStringSync();
        return PluginDirectory._(
          dir,
          PluginBundle(manifest: manifest, code: code),
          PluginManifest.parse(manifest),
        );
      }(),
  ];
}

/// 插件宣告的每個插件能力與它的案例（`fixtures/<插件能力>/*.json`，依檔名
/// 排序）。
Map<PluginCapability, List<File>> fixtureFiles(PluginDirectory plugin) => {
  for (final capability in PluginCapability.values)
    if (plugin.manifest.capabilities.contains(capability))
      capability: _jsonFiles(_fixtureDir(plugin, capability.name)),
};

/// 每個插件能力的 fixture 只留哪些回應欄位：`fixtures/keep.json`，例如
/// `{"search": ["code", "data.result.title"]}`（路徑寫法見 [keepFields]）。
/// 音源回應的形狀由插件決定，所以清單放在插件目錄裡，宿主與測試不寫音源
/// 專屬的欄位名（ADR 0038）。
Map<PluginCapability, List<String>> keptFields(PluginDirectory plugin) {
  final file = File('${plugin.dir.path}/fixtures/keep.json');
  if (!file.existsSync()) return {};
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final c in PluginCapability.values)
      if (json[c.name] case final List<dynamic> paths) c: paths.cast<String>(),
  };
}

/// 宣告了插件能力卻沒有案例或沒有 `keep.json` 的欄位清單，或 `fixtures/`
/// 底下有沒宣告的插件能力的目錄（多半是打錯字，那些案例永遠不會跑）。
List<String> fixtureProblems(PluginDirectory plugin) {
  final declared = {for (final c in plugin.manifest.capabilities) c.name};
  final root = Directory('${plugin.dir.path}/fixtures');
  final present = root.existsSync()
      ? [
          for (final dir in root.listSync().whereType<Directory>())
            dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ]
      : <String>[];
  final kept = keptFields(plugin);
  return [
    for (final MapEntry(:key, :value) in fixtureFiles(plugin).entries) ...[
      if (value.isEmpty)
        '${plugin.id} declares ${key.name} but has no '
            'fixtures/${key.name}/*.json',
      if (!kept.containsKey(key))
        '${plugin.id} declares ${key.name} but fixtures/keep.json does not '
            'list its fields',
    ],
    for (final name in present..sort())
      if (!declared.contains(name))
        '${plugin.id} has fixtures/$name but does not declare that capability',
  ];
}

Directory _fixtureDir(PluginDirectory plugin, String capability) =>
    Directory('${plugin.dir.path}/fixtures/$capability');

List<File> _jsonFiles(Directory dir) => dir.existsSync()
    ? ([
        for (final f in dir.listSync().whereType<File>())
          if (f.path.endsWith('.json')) f,
      ]..sort((a, b) => a.path.compareTo(b.path)))
    : [];
