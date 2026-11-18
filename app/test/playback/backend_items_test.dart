import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/backends/backend_items.dart';

/// 兩個音訊後端共用的原生清單帳本（[BackendItems]）：目前這條、預載的
/// 那條，以及原生播放器的位置變了時對回哪一條。
void main() {
  AudioStream stream(String name) =>
      AudioStream(url: Uri.parse('https://cdn.example.com/$name.m4a'));

  late BackendItems playlist;
  final a = stream('a');
  final b = stream('b');
  final c = stream('c');

  setUp(() => playlist = BackendItems());

  /// 預載 [stream]，原生加好了。
  void preload(AudioStream stream) {
    playlist.preload(stream);
    playlist.appended(stream, onTopOf: playlist.current!);
  }

  test('nothing is current or preloaded before the first load', () {
    expect(playlist.current, isNull);
    expect(playlist.preloaded, isNull);
    expect(playlist.preload(b), isNull);
  });

  test('a load makes its stream the only one in the native list', () {
    playlist.opened(a);

    expect(playlist.current, same(a));
    expect(playlist.preloaded, isNull);
  });

  test('preloading appends after the current stream once the native list '
      'has it', () {
    playlist.opened(a);

    final edit = playlist.preload(b)!;
    expect(edit.remove, isEmpty);
    expect(edit.append, same(b));
    // 原生還沒加好：自己接過去也對不到它。
    expect(playlist.preloaded, isNull);

    expect(playlist.appended(b, onTopOf: a), isTrue);
    expect(playlist.preloaded, same(b));
  });

  test('a native append that finishes after the list was replaced is not '
      'recorded', () {
    playlist.opened(a);
    playlist.preload(b);
    playlist.opened(c);

    expect(playlist.appended(b, onTopOf: a), isFalse);
    expect(playlist.preloaded, isNull);
  });

  test('preloading another stream removes the old one first', () {
    playlist.opened(a);
    preload(b);

    final edit = playlist.preload(c)!;

    expect(edit.remove, [1]);
    expect(edit.append, same(c));
    expect(playlist.preloaded, isNull);
  });

  test('preloading null clears the preloaded stream', () {
    playlist.opened(a);
    preload(b);

    final edit = playlist.preload(null)!;

    expect(edit.remove, [1]);
    expect(edit.append, isNull);
    expect(playlist.preloaded, isNull);
  });

  test('preloading the stream already preloaded changes nothing', () {
    playlist.opened(a);
    preload(b);

    final edit = playlist.preload(b)!;

    expect(edit.remove, isEmpty);
    expect(edit.append, isNull);
  });

  test('a stream that is only equal, not the same object, counts as '
      'another stream', () {
    playlist.opened(a);
    preload(b);

    final edit = playlist.preload(stream('b'))!;

    expect(edit.remove, [1]);
    expect(edit.append, isNotNull);
  });

  group('loading', () {
    test('the preloaded stream switches to its index', () {
      playlist.opened(a);
      preload(b);

      expect(playlist.planLoad(b), const SwitchTo(1));
    });

    test('the current stream changes nothing', () {
      playlist.opened(a);

      expect(playlist.planLoad(a), const AlreadyCurrent());
    });

    test('any other stream reopens', () {
      playlist.opened(a);
      preload(b);

      expect(playlist.planLoad(c), const Reopen());
      expect(playlist.planLoad(stream('b')), const Reopen());
    });
  });

  group('the native position moves', () {
    test('to the preloaded stream: it becomes current, nothing is '
        'preloaded, and the finished one is dropped', () {
      playlist.opened(a);
      preload(b);

      expect(playlist.moveTo(1), same(b));
      expect(playlist.current, same(b));
      expect(playlist.preloaded, isNull);

      expect(playlist.dropPlayed(), [0]);
      // 移掉之後原生的位置是 0，還是同一條。
      expect(playlist.moveTo(0), isNull);
      expect(playlist.current, same(b));
    });

    test('to where it already is: nothing changes', () {
      playlist.opened(a);
      preload(b);

      expect(playlist.moveTo(0), isNull);
      expect(playlist.current, same(a));
      expect(playlist.preloaded, same(b));
    });

    test('outside the list (the native list is being replaced): ignored', () {
      playlist.opened(a);

      expect(playlist.moveTo(3), isNull);
      expect(playlist.current, same(a));
    });

    test('after the switch, the next preload goes after the new current', () {
      playlist.opened(a);
      preload(b);
      playlist
        ..moveTo(1)
        ..dropPlayed();

      final edit = playlist.preload(c)!;
      expect(edit.remove, isEmpty);
      expect(edit.append, same(c));
      playlist.appended(c, onTopOf: b);
      expect(playlist.planLoad(c), const SwitchTo(1));
    });
  });

  test('clearing forgets everything', () {
    playlist.opened(a);
    preload(b);
    playlist.clear();

    expect(playlist.current, isNull);
    expect(playlist.preloaded, isNull);
    expect(playlist.planLoad(b), const Reopen());
  });
}
