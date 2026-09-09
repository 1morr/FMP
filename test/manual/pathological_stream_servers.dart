// ignore_for_file: avoid_print
//
// Two deliberately broken HTTP audio servers. They are the only reliable way to
// reproduce the "loads forever" and "stutters and re-loads" playback symptoms,
// because both depend on how the audio engine reacts to a sick connection —
// something no unit test can stand in for, and something a real CDN will not do
// on request.
//
// Manual probe, not a test. It must never be named `*_test.dart`: it binds
// sockets and runs until killed, so `flutter test` would hang on it forever.
//
//   dart run test/manual/pathological_stream_servers.dart
//
// Then point playback at one of the URLs it prints. Windows reaches the host as
// 127.0.0.1; the Android emulator reaches it as 10.0.2.2.
//
// Measured engine behaviour these reproduce, which is what a fix has to change.
// Taken with the engines driven directly, no AudioController attached, so these
// are the engines' own numbers and not FMP's:
//
//   hold  | Windows/mpv       `open()` returns in ~0.6s, playUrl "succeeds" in
//         |                   6.1s with duration: null, then completes at 12.4s
//         | Android/ExoPlayer `setAudioSource` blocks 37.7s, then Source error
//   stall | Windows/mpv       reconnects 6 times, emits completed after 3.8s
//         |                   with no error at all
//         | Android/ExoPlayer reconnects 3 times, Source error after 16.4s

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const int _sampleRate = 44100;
const int _channels = 2;
const int _bytesPerSample = 2;
const int _trackSeconds = 120;

/// Bytes of PCM data a [_trackSeconds] track claims to have.
///
/// The engines only believe a stall is abnormal if the response promised more
/// than it delivered, so `Content-Length` has to describe a plausible track.
const int _dataBytes =
    _sampleRate * _channels * _bytesPerSample * _trackSeconds;

/// How much audio the stall server delivers before cutting the connection.
const int _stallAfterBytes = _sampleRate * _channels * _bytesPerSample * 4;

Future<void> main(List<String> args) async {
  final host = _option(args, '--host') ?? '0.0.0.0';
  final holdPort = int.parse(_option(args, '--hold-port') ?? '8742');
  final stallPort = int.parse(_option(args, '--stall-port') ?? '8741');

  await _serve(host, holdPort, 'hold', _handleHold);
  await _serve(host, stallPort, 'stall', _handleStall);

  print('');
  print('  hold  (connects, never sends a byte, never closes)');
  print('    Windows  http://127.0.0.1:$holdPort/hold.wav');
  print('    Android  http://10.0.2.2:$holdPort/hold.wav');
  print('  stall (sends 4s of audio, then cuts the connection)');
  print('    Windows  http://127.0.0.1:$stallPort/stall.wav');
  print('    Android  http://10.0.2.2:$stallPort/stall.wav');
  print('');
  print('Ctrl+C to stop.');
}

Future<void> _serve(
  String host,
  int port,
  String name,
  Future<void> Function(String tag, Socket socket, _Request request) handle,
) async {
  final server = await ServerSocket.bind(host, port);
  var connections = 0;
  server.listen((socket) async {
    final tag = '[$name ${++connections}]';
    try {
      final request = await _readRequest(socket);
      if (request == null) {
        print('$tag no request line; closing');
        socket.destroy();
        return;
      }
      print(
        '$tag ${request.method} ${request.path}'
        '${request.range == null ? '' : ' Range: bytes=${request.range}-'}',
      );
      await handle(tag, socket, request);
    } catch (error) {
      print('$tag failed: $error');
      socket.destroy();
    }
  });
  print('$name server listening on $host:$port');
}

/// Answers, then goes silent forever. The socket is deliberately leaked: the
/// whole point is that the peer is never told anything is wrong.
Future<void> _handleHold(String tag, Socket socket, _Request request) async {
  socket.add(_responseHead(request.range ?? 0));
  socket.add(_wavHeader());
  await socket.flush();
  print('$tag headers sent; holding the connection open with no data');
}

Future<void> _handleStall(String tag, Socket socket, _Request request) async {
  // Only the first attempt gets audio. Every reconnect is refused, so the
  // engine's own retry logic runs to exhaustion instead of quietly recovering —
  // that exhaustion is the behaviour under test.
  if (request.range != null && request.range! > 0) {
    print('$tag refusing reconnect');
    socket.destroy();
    return;
  }

  socket.add(_responseHead(0));
  socket.add(_wavHeader());
  socket.add(Uint8List(_stallAfterBytes));
  await socket.flush();
  print('$tag sent ${_stallAfterBytes}B of $_dataBytes B; cutting the socket');
  socket.destroy();
}

List<int> _responseHead(int from) {
  final remaining = _dataBytes + _wavHeaderBytes - from;
  final lines = <String>[
    if (from == 0) 'HTTP/1.1 200 OK' else 'HTTP/1.1 206 Partial Content',
    'Content-Type: audio/wav',
    'Accept-Ranges: bytes',
    'Content-Length: $remaining',
    if (from > 0)
      'Content-Range: bytes $from-${_dataBytes + _wavHeaderBytes - 1}'
          '/${_dataBytes + _wavHeaderBytes}',
    'Connection: close',
    '',
    '',
  ];
  return lines.join('\r\n').codeUnits;
}

const int _wavHeaderBytes = 44;

Uint8List _wavHeader() {
  final header = BytesBuilder();
  void ascii(String value) => header.add(value.codeUnits);
  void u16(int value) => header.add([value & 0xff, (value >> 8) & 0xff]);
  void u32(int value) => header.add([
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);

  ascii('RIFF');
  u32(36 + _dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(_channels);
  u32(_sampleRate);
  u32(_sampleRate * _channels * _bytesPerSample); // byte rate
  u16(_channels * _bytesPerSample); // block align
  u16(_bytesPerSample * 8);
  ascii('data');
  u32(_dataBytes);
  return header.takeBytes();
}

class _Request {
  const _Request({required this.method, required this.path, this.range});

  final String method;
  final String path;
  final int? range;
}

Future<_Request?> _readRequest(Socket socket) async {
  final buffer = BytesBuilder();
  await for (final chunk in socket) {
    buffer.add(chunk);
    final text = String.fromCharCodes(buffer.toBytes());
    if (!text.contains('\r\n\r\n')) continue;

    final lines = text.split('\r\n');
    final start = lines.first.split(' ');
    if (start.length < 2) return null;

    int? range;
    for (final line in lines.skip(1)) {
      if (!line.toLowerCase().startsWith('range:')) continue;
      final match = RegExp(r'bytes=(\d+)-').firstMatch(line);
      if (match != null) range = int.parse(match.group(1)!);
    }
    return _Request(method: start[0], path: start[1], range: range);
  }
  return null;
}

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
