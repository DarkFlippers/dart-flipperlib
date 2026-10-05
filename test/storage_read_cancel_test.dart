import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stopping a read that is already streaming.
///
/// The firmware streams a storage read to the end once asked and the protocol
/// has no abort for it, so cancelling cannot stop the transfer - only free the
/// caller at the next frame instead of at the end of the file. Everything below
/// is about that distinction, because getting it wrong in either direction is a
/// bug: freeing nobody makes Stop useless, and tearing down the request would
/// leave the session's bookkeeping claiming an idle link while bytes are still
/// arriving.
///
/// `storageReadChunked` is an extension on `FlipperClient`, so a fake cannot
/// override it - the real body runs and `callRpcFrames` is the seam, which is
/// the same trick `reboot_refusal_test.dart` uses.
class _StreamingClient extends FlipperClient {
  _StreamingClient({required this.frames, this.failAfterCancel = false});

  /// How many response frames the "firmware" sends.
  final int frames;

  /// Whether the request then fails - a link drop part way through a drain
  /// nobody is waiting for any more.
  final bool failAfterCancel;

  int delivered = 0;
  bool completed = false;

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
  }) async {
    for (var i = 0; i < frames; i++) {
      // An await between frames, because that is how they really arrive: a
      // cancellation decided in one frame has to be seen before the next.
      await Future<void>.delayed(Duration.zero);
      delivered++;
      final frame = Main()
        ..storageReadResponse = (ReadResponse()
          ..file = (File()..data = List<int>.filled(16, 1)));
      onFrame?.call(frame);
    }
    completed = true;
    if (failAfterCancel) throw StateError('link dropped mid-drain');
    return const [];
  }
}

void main() {
  group('a cancelled read', () {
    test('throws, naming the path', () async {
      final client = _StreamingClient(frames: 10);

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
        final client = _StreamingClient(frames: 4);

        await expectLater(
          client.storageReadChunked('/ext/x', isCancelled: () => true),
          throwsA(isA<FlipperCancelledException>()),
        );
      },
    );

    // The point of the whole change: the caller is freed at the frame where it
    // asked, not after the file. Asserted by how much of the "file" had been
    // delivered when the throw arrived.
    test('frees the caller mid-stream, not at the end of the file', () async {
      final client = _StreamingClient(frames: 200);
      var seen = 0;

      await expectLater(
        client.storageReadChunked('/ext/x', isCancelled: () => ++seen > 3),
        throwsA(isA<FlipperReadCancelledException>()),
      );

      expect(
        client.delivered,
        lessThan(10),
        reason: 'it must not have waited out 200 frames',
      );
      expect(
        client.completed,
        isFalse,
        reason: 'and the request is still in flight, which is the contract',
      );
    });

    // The request is deliberately left running. Tearing it down is what would
    // make the session report an idle link while the firmware is still sending,
    // which is the thing the companion app's battery poll defers to.
    test('leaves the request in flight, and it finishes on its own', () async {
      final client = _StreamingClient(frames: 6);

      await expectLater(
        client.storageReadChunked('/ext/x', isCancelled: () => true),
        throwsA(isA<FlipperReadCancelledException>()),
      );
      expect(client.completed, isFalse);

      // Let the abandoned response drain.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.delivered, 6, reason: 'every frame still arrived');
      expect(client.completed, isTrue, reason: 'and it unwound normally');
    });

    // Future.any attaches an error handler to both futures, so the abandoned
    // read failing later is handled rather than reaching the zone as
    // [uncaught]. Without that this test fails the suite from the zone.
    test('an abandoned read that then fails does not go uncaught', () async {
      final client = _StreamingClient(frames: 5, failAfterCancel: true);

      await expectLater(
        client.storageReadChunked('/ext/x', isCancelled: () => true),
        throwsA(isA<FlipperReadCancelledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(client.completed, isTrue);
    });

    // The latch. Without it every frame of the drain asks again and tries to
    // complete a completed Completer.
    test('asks the predicate once, not once per remaining frame', () async {
      final client = _StreamingClient(frames: 20);
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

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(asked, 1, reason: 'the whole drain must not re-ask');
      expect(client.completed, isTrue, reason: 'and must not derail the read');
    });

    test('stops reporting progress once it has been abandoned', () async {
      final client = _StreamingClient(frames: 20);
      final reported = <double>[];

      await expectLater(
        client.storageReadChunked(
          '/ext/x',
          expectedSize: 320,
          onProgress: reported.add,
          isCancelled: () => client.delivered >= 2,
        ),
        throwsA(isA<FlipperReadCancelledException>()),
      );
      final atCancel = reported.length;

      // Never 1.0. The completion report belongs to a read that finished, and
      // a cancelled one showing 100% would tell the user their download
      // completed at the moment they stopped it.
      expect(reported, isNot(contains(1.0)));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        reported.length,
        atCancel,
        reason: 'progress after the caller has its error reads as a bug',
      );
      expect(reported, isNot(contains(1.0)));
    });
  });

  group('a read nobody cancels', () {
    test('returns the whole file', () async {
      final client = _StreamingClient(frames: 4);

      final bytes = await client.storageReadChunked('/ext/x');

      expect(bytes, hasLength(64));
      expect(client.completed, isTrue);
    });

    test('is unaffected by a predicate that always says no', () async {
      final client = _StreamingClient(frames: 4);

      final bytes = await client.storageReadChunked(
        '/ext/x',
        isCancelled: () => false,
      );

      expect(bytes, hasLength(64));
    });

    test('still reports progress against a known size', () async {
      final client = _StreamingClient(frames: 4);
      final reported = <double>[];

      await client.storageReadChunked(
        '/ext/x',
        expectedSize: 64,
        onProgress: reported.add,
      );

      expect(reported.last, 1.0);
      expect(reported.length, greaterThan(1));
    });
  });
}
