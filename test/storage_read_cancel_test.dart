import 'dart:math';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a file in windows, and stopping part way.
///
/// `storageReadChunked` is an extension on `FlipperClient`, so a fake cannot
/// override it - the real body runs and `callRpcFrames` is the seam, which is
/// the same trick `reboot_refusal_test.dart` uses. The fake below answers a
/// read request the way the firmware does: the requested range in 512-byte
/// frames with `ranged` set, or - as stock firmware, which knows no offsets -
/// the whole file and no flag.
class _Flipper extends FlipperClient {
  _Flipper(
    this.file, {
    this.honoursRanges = true,
    this.failWindowAt,
    this.failAfterFrame,
  });

  final List<int> file;
  final bool honoursRanges;

  /// A window offset whose request fails instead of answering.
  final int? failWindowAt;

  /// A frame count after which the link drops mid-window.
  final int? failAfterFrame;

  final requests = <int>[];
  int delivered = 0;
  int completed = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  int _nextCommandId = 1;
  Future<void> _tail = Future<void>.value();

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) {
    inFlight++;
    maxInFlight = max(maxInFlight, inFlight);
    final answer = _tail.then((_) => _answer(request, onFrame));
    _tail = answer.then((_) {}, onError: (Object _) {});
    return answer.whenComplete(() => inFlight--);
  }

  Future<List<Main>> _answer(
    Main request,
    void Function(Main frame)? onFrame,
  ) async {
    final req = request.storageReadRequest;
    requests.add(req.offset);
    final commandId = _nextCommandId++;
    try {
      // An await between frames, because that is how they really arrive: a
      // cancellation decided in one frame has to be seen before the next.
      await Future<void>.delayed(Duration.zero);
      if (failWindowAt == req.offset) {
        throw FlipperRpcStorageNotExistException(
          Main()
            ..commandId = commandId
            ..commandStatus = CommandStatus.ERROR_STORAGE_NOT_EXIST,
        );
      }
      final start = honoursRanges ? min(req.offset, file.length) : 0;
      final end = honoursRanges && req.size > 0
          ? min(start + req.size, file.length)
          : file.length;
      var pos = start;
      do {
        final chunkEnd = min(pos + 512, end);
        final frame = Main()
          ..commandId = commandId
          ..hasNext = chunkEnd < end
          ..storageReadResponse = (ReadResponse()
            ..ranged = honoursRanges
            ..file = (File()..data = file.sublist(pos, chunkEnd)));
        delivered++;
        onFrame?.call(frame);
        pos = chunkEnd;
        await Future<void>.delayed(Duration.zero);
        if (failAfterFrame != null && delivered >= failAfterFrame!) {
          throw StateError('link dropped mid-window');
        }
      } while (pos < end);
      return const [];
    } finally {
      completed++;
    }
  }
}

List<int> _bytes(int length) => List<int>.generate(length, (i) => i & 0xff);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('a read nobody cancels', () {
    test('assembles a file spanning several windows, in order', () async {
      final file = _bytes(20000);
      final client = _Flipper(file);

      final bytes = await client.storageReadChunked('/ext/x');

      expect(bytes, file);
      expect(client.requests, [0, 8192, 16384]);
    });

    test('handles a file that is an exact number of windows', () async {
      final file = _bytes(16384);
      final client = _Flipper(file);

      final bytes = await client.storageReadChunked('/ext/x');

      expect(bytes, file);
      expect(client.requests, [0, 8192, 16384]);
    });

    test('keeps one window in flight', () async {
      final client = _Flipper(_bytes(30000));

      await client.storageReadChunked('/ext/x');

      expect(client.maxInFlight, 1);
    });

    test('a file smaller than a window takes one request', () async {
      final file = _bytes(100);
      final client = _Flipper(file);

      final bytes = await client.storageReadChunked('/ext/x');

      expect(bytes, file);
      expect(client.requests, [0]);
    });

    test('an empty file takes one request and returns nothing', () async {
      final client = _Flipper(const []);

      final bytes = await client.storageReadChunked('/ext/x');

      expect(bytes, isEmpty);
      expect(client.requests, [0]);
    });

    test('asks for windows of the documented size', () async {
      final client = _Flipper(_bytes(100));

      await client.storageReadChunked('/ext/x');

      expect(storageReadWindow, 8192);
    });

    // Stock firmware ignores the offset and the size and streams the whole
    // file on the first request. Asking for more would fetch it again.
    test('takes the whole file from firmware without ranges', () async {
      final file = _bytes(20000);
      final client = _Flipper(file, honoursRanges: false);

      final bytes = await client.storageReadChunked('/ext/x');

      expect(bytes, file);
      expect(client.requests, [0]);
    });

    test('reports progress against a known size, ending at 1.0', () async {
      final client = _Flipper(_bytes(20000));
      final reported = <double>[];

      await client.storageReadChunked(
        '/ext/x',
        expectedSize: 20000,
        onProgress: reported.add,
      );

      expect(reported.last, 1.0);
      expect(reported.length, greaterThan(1));
    });

    test('is unaffected by a predicate that always says no', () async {
      final file = _bytes(20000);
      final client = _Flipper(file);

      final bytes = await client.storageReadChunked(
        '/ext/x',
        isCancelled: () => false,
      );

      expect(bytes, file);
    });
  });

  group('a read that fails part way', () {
    test('throws the window\'s error and leaves nothing uncaught', () async {
      final client = _Flipper(_bytes(30000), failWindowAt: 8192);

      await expectLater(
        client.storageReadChunked('/ext/x'),
        throwsA(isA<FlipperRpcStorageNotExistException>()),
      );

      await _settle();
      expect(client.completed, client.requests.length);
    });
  });

  group('a cancelled read', () {
    test('throws, naming the path', () async {
      final client = _Flipper(_bytes(20000));

      await expectLater(
        client.storageReadChunked(
          '/ext/nfc/.nested.log',
          isCancelled: () => true,
        ),
        throwsA(
          isA<FlipperReadCancelledException>().having(
            (e) => e.path,
            'path',
            '/ext/nfc/.nested.log',
          ),
        ),
      );
    });

    test(
      'is caught by the shared base, as a caller driving both will',
      () async {
        final client = _Flipper(_bytes(20000));

        await expectLater(
          client.storageReadChunked('/ext/x', isCancelled: () => true),
          throwsA(isA<FlipperCancelledException>()),
        );
      },
    );

    // The point of the whole change: the caller is freed at the frame where it
    // asked, and no further windows are requested.
    test('frees the caller mid-stream and requests no more windows', () async {
      final client = _Flipper(_bytes(200000));
      var seen = 0;

      await expectLater(
        client.storageReadChunked('/ext/x', isCancelled: () => ++seen > 3),
        throwsA(isA<FlipperReadCancelledException>()),
      );

      expect(client.delivered, lessThan(10));
      expect(client.requests, [0]);

      await _settle();
      expect(client.requests, [0], reason: 'no window after the cancel');
      expect(client.delivered, 16, reason: 'the one in flight drained');
      expect(client.completed, 1);
    });

    test(
      'on firmware without ranges, the one request drains on its own',
      () async {
        final client = _Flipper(_bytes(4096), honoursRanges: false);

        await expectLater(
          client.storageReadChunked('/ext/x', isCancelled: () => true),
          throwsA(isA<FlipperReadCancelledException>()),
        );
        expect(client.completed, 0);

        await _settle();
        expect(client.requests, [0]);
        expect(client.delivered, 8, reason: 'every frame still arrived');
        expect(client.completed, 1, reason: 'and it unwound normally');
      },
    );

    // The window in flight failing after the caller left must be handled
    // rather than reaching the zone as [uncaught]. Without that this test
    // fails the suite from the zone.
    test('the window failing after the cancel does not go uncaught', () async {
      final client = _Flipper(_bytes(30000), failAfterFrame: 20);

      await expectLater(
        client.storageReadChunked(
          '/ext/x',
          isCancelled: () => client.delivered >= 18,
        ),
        throwsA(isA<FlipperReadCancelledException>()),
      );

      await _settle();
      expect(client.completed, client.requests.length);
    });

    // The latch. Without it every frame of the drain asks again and tries to
    // complete a completed Completer.
    test('asks the predicate once, not once per remaining frame', () async {
      final client = _Flipper(_bytes(4096), honoursRanges: false);
      var asked = 0;

      await expectLater(
        client.storageReadChunked(
          '/ext/x',
          isCancelled: () {
            asked++;
            return true;
          },
        ),
        throwsA(isA<FlipperReadCancelledException>()),
      );

      await _settle();
      expect(asked, 1, reason: 'the whole drain must not re-ask');
      expect(client.completed, 1, reason: 'and must not derail the read');
    });

    test('goes on reporting progress while the window drains', () async {
      final client = _Flipper(_bytes(20000));
      final reported = <double>[];

      await expectLater(
        client.storageReadChunked(
          '/ext/x',
          expectedSize: 20000,
          onProgress: reported.add,
          isCancelled: () => client.delivered >= 2,
        ),
        throwsA(isA<FlipperReadCancelledException>()),
      );
      final atCancel = reported.length;

      await _settle();
      // The frames of the window in flight are still crossing the link, and a
      // bar that stopped at the cancel would look like an app that hung.
      expect(
        reported.length,
        greaterThan(atCancel),
        reason: 'every frame of the drain is still a frame received',
      );
      expect(reported.last, closeTo(8192 / 20000, 0.001));
      // Never the completion report: that belongs to a read that finished.
      expect(reported, isNot(contains(1.0)));
    });

    test('drained completes when the window in flight has', () async {
      final client = _Flipper(_bytes(200000));
      late FlipperReadCancelledException cancel;

      try {
        await client.storageReadChunked('/ext/x', isCancelled: () => true);
      } on FlipperReadCancelledException catch (e) {
        cancel = e;
      }
      expect(client.completed, 0);

      await cancel.drained;
      expect(client.completed, 1);
      expect(client.delivered, 16);
    });
  });
}
