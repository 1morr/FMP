import Cocoa
import FlutterMacOS
import MediaPlayer
import os

class MainFlutterWindow: NSWindow {
  private var nowPlaying: NowPlayingChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    nowPlaying = NowPlayingChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// 實驗用（可丟棄）：候選二，自己接 MPNowPlayingInfoCenter 與 MPRemoteCommandCenter。
///
/// Dart → 原生：init、setTrack、setPlayback。原生 → Dart：play、pause、togglePlayPause、
/// next、previous、seek（`seconds`）。每次收到系統指令也寫一筆系統 log
/// （subsystem `com.personal.fmp.exp`、category `now-playing`），供 `log show` 對照。
final class NowPlayingChannel {
  private let channel: FlutterMethodChannel
  private let log = Logger(subsystem: "com.personal.fmp.exp", category: "now-playing")
  private var info: [String: Any] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "fmp.exp/now_playing", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "init":
      registerCommands()
      result(nil)
    case "setTrack":
      var next: [String: Any] = [
        MPMediaItemPropertyTitle: args["title"] as? String ?? "",
        MPMediaItemPropertyArtist: args["artist"] as? String ?? "",
        MPMediaItemPropertyAlbumTitle: args["album"] as? String ?? "",
        MPMediaItemPropertyPlaybackDuration: args["duration"] as? Double ?? 0,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
        MPNowPlayingInfoPropertyPlaybackRate: 0.0,
      ]
      if let path = args["artPath"] as? String, let image = NSImage(contentsOfFile: path) {
        next[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      }
      info = next
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      log.info("setTrack \(args["title"] as? String ?? "", privacy: .public)")
      result(nil)
    case "setPlayback":
      let playing = args["playing"] as? Bool ?? false
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = args["position"] as? Double ?? 0
      info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
      let center = MPNowPlayingInfoCenter.default()
      center.nowPlayingInfo = info
      // macOS 才有的屬性：不設的話系統不知道 App 在播還是暫停。
      center.playbackState = playing ? .playing : .paused
      log.info("setPlayback playing=\(playing, privacy: .public)")
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func registerCommands() {
    let cc = MPRemoteCommandCenter.shared()
    func on(_ command: MPRemoteCommand, _ name: String) {
      command.isEnabled = true
      command.addTarget { [weak self] _ in
        self?.send(name, nil)
        return .success
      }
    }
    on(cc.playCommand, "play")
    on(cc.pauseCommand, "pause")
    on(cc.togglePlayPauseCommand, "togglePlayPause")
    on(cc.nextTrackCommand, "next")
    on(cc.previousTrackCommand, "previous")
    cc.changePlaybackPositionCommand.isEnabled = true
    cc.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self?.send("seek", ["seconds": e.positionTime])
      return .success
    }
  }

  private func send(_ name: String, _ args: [String: Any]?) {
    log.info("received \(name, privacy: .public)")
    DispatchQueue.main.async { self.channel.invokeMethod(name, arguments: args) }
  }
}
