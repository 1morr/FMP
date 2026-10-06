import 'package:flutter/foundation.dart';

/// 一個音訊輸出裝置（只有 Windows 能選，`PlaybackSupport.outputDeviceSelection`；
/// design §7.6）。
///
/// 放在 `domain/`：設定層要存它（「播放」組的 `output_device_id`、
/// `output_device_name`），播放層與介面要用它。
@immutable
final class OutputDevice {
  const OutputDevice({required this.id, required this.name});

  /// 引擎的裝置名（mpv 的 `audio-device`，例如 `wasapi/{…}`），以它認裝置。
  final String id;

  /// 給人看的描述（mpv 的 `description`，例如「喇叭 (Realtek(R) Audio)」）。
  final String name;

  @override
  bool operator ==(Object other) =>
      other is OutputDevice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'OutputDevice($id, $name)';
}
