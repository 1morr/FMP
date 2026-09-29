import 'dart:convert';
import 'dart:typed_data';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';

/// 安裝檔標頭的開頭與結尾（ADR 0014 2026-09-30 補充；使用者腳本 metadata
/// block 的慣例）。
const pluginHeaderStart = '/* ==FMP Plugin==';
const pluginHeaderEnd = '==/FMP Plugin== */';

/// 一個安裝檔：單一 `.js` 檔，開頭以 [pluginHeaderStart]、[pluginHeaderEnd]
/// 包一段 JSON manifest，之後是 ES module 腳本。
///
/// 讀 manifest 不執行腳本：安裝前先檢查網域與能力（ADR 0014 §決定 6）。
final class PluginFile {
  const PluginFile._({
    required this.source,
    required this.manifestJson,
    required this.manifest,
  });

  /// 解析安裝檔的位元組（UTF-8，可帶 BOM）。不是合法 UTF-8 是 [ParseError]；
  /// 其他錯誤見 [PluginFile.parse]。
  factory PluginFile.decode(Uint8List bytes) {
    final String text;
    try {
      text = const Utf8Decoder().convert(bytes);
    } on FormatException catch (error, stackTrace) {
      throw ParseError(cause: error, stackTrace: stackTrace);
    }
    return PluginFile.parse(text);
  }

  /// 解析安裝檔的文字。
  ///
  /// 標頭必須是檔案的第一段內容（前面只准有 BOM 與空白），JSON 裡不能出現
  /// `*/`（會提早結束註解）。標頭有問題是 [ParseError]；manifest 本身的錯誤
  /// 見 [PluginManifest.parse]。
  factory PluginFile.parse(String source) {
    final text = source.startsWith('﻿') ? source.substring(1) : source;
    final start = text.length - text.trimLeft().length;
    if (!text.startsWith(pluginHeaderStart, start)) {
      throw _headerError('the file must start with "$pluginHeaderStart"');
    }
    final jsonStart = start + pluginHeaderStart.length;
    final end = text.indexOf(pluginHeaderEnd, jsonStart);
    if (end < 0) {
      throw _headerError('missing "$pluginHeaderEnd"');
    }
    final json = text.substring(jsonStart, end);
    if (json.contains('*/')) {
      throw _headerError('the manifest must not contain "*/"');
    }
    return PluginFile._(
      source: text,
      manifestJson: json.trim(),
      manifest: PluginManifest.parse(json),
    );
  }

  /// 整個檔案（去掉 BOM）；安裝時原樣存進 `installed_plugins.script`，index 的
  /// SHA-256 針對的也是這個檔案。
  final String source;

  /// 標頭內的 JSON 原文。
  final String manifestJson;
  final PluginManifest manifest;

  static ParseError _headerError(String message) => ParseError(
    cause: FormatException('Plugin header: $message'),
    stackTrace: StackTrace.current,
  );
}
