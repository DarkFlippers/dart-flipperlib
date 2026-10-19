import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart';
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Restarting an upload the link died under.
///
/// `storageWriteChunked` is the only caller of `isLinkDropError` inside this
/// library that acts on the answer: a drop waits for the automatic reconnect
/// and sends the file again from offset 0, anything else is rethrown. (The app
/// has a second one, in the archive sync.) So the predicate's reading of a
/// sentence is visible here as a second attempt, which is what makes this the
/// file the case-sensitivity bug belongs in: the two sentences that embed a
/// transport constant's words in a longer one, at six sites between them, were
/// not drops to it while the dialog for the same event called them a device
/// out of range. qUnleashed#366.
///
/// Those two sentences do not reach this catch today - every failure that does
/// is either a `FlipperTransportError`, which matches by type, or carries a
/// constant whole, because the request queue wraps a failed write and a
/// teardown prefixes `Disconnected:`. What is pinned here is therefore the
/// predicate's contract through the one path that acts on it, not a crash
/// anybody saw: if a sentence that names a dropped link arrives, the upload
/// restarts.
///
/// The seam is `callRpcFramesMulti`: `storageWriteChunked` is an extension on
/// `FlipperClient`, so a fake cannot override it - the real body runs, the
/// same way `storage_read_cancel_test.dart` works one layer down.
class _Flipper extends FlipperClient {
  _Flipper({this.failAttemptOneWith, this.failLaterWith, this.onDrop});

  /// What the link throws two frames into the first upload.
  final Object? failAttemptOneWith;

  /// What it throws two frames into every attempt after the first. Null means
  /// the restart succeeds.
  final Object? failLaterWith;

  /// Run as the link dies, for a test that wants to cancel at that moment.
  final void Function()? onDrop;

  final _transport = _LiveTransport();

  /// The bytes each attempt managed to send, in order.
  final attempts = <List<int>>[];

  /// How many times the restart asked for the session back.
  int waits = 0;

  /// Whether the session is taken to come back. False is a reconnect that
  /// never finished.
  bool rpcComesBack = true;

  /// A reconnect that has already happened by the time it is asked about: the
  /// client is in RPC mode over a live transport, so the real
  /// `waitForRpcSession` answers from `healthy()` without waiting on the
  /// connection stream. [waits] is what holds the wait in the path - a restart
  /// that stopped asking would pass every case below without it.
  @override
  FlipperMode get mode => FlipperMode.rpc;

  @override
  Transport? get transport => _transport;

  @override
  Future<bool> waitForRpcSession(Duration timeout) {
    waits++;
    if (!rpcComesBack) return Future.value(false);
    return super.waitForRpcSession(timeout);
  }

  /// The pacing ping, which `storageWriteChunked` interleaves every 16 frames
  /// on a transport that is not BLE. None of the files below is big enough to
  /// reach one - a case over 8192 bytes would, and without this it would reach
  /// the real `callRpcFrames`, be refused for want of a session with the exact
  /// `No active transport` sentence, and restart for the harness's own reason
  /// rather than the injected one.
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
  }) async => const [];

  @override
  Future<List<Main>> callRpcFramesMulti(
    Future<void> Function(Future<void> Function(Main frame) sendFrame) body, {
    Duration timeout = const Duration(seconds: 60),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) async {
    final sent = <int>[];
    final attempt = attempts.length + 1;
    attempts.add(sent);
    var frames = 0;
    await body((frame) async {
      // An await per frame, because that is how they really go out - and the
      // restart has to survive the gap.
      await Future<void>.delayed(Duration.zero);
      frames++;
      final dies = attempt == 1 ? failAttemptOneWith : failLaterWith;
      if (dies != null && frames == 2) {
        onDrop?.call();
        throw dies;
      }
      sent.addAll(frame.storageWriteRequest.file.data);
    });
    return const [];
  }
}

/// A transport that is up and does nothing: `isActive` is what the restart
/// waits on, and 512-byte frames are what the file is cut into.
class _LiveTransport extends Transport {
  @override
  bool get supportsCli => false;

  @override
  FlipperMode get initialMode => FlipperMode.rpc;

  @override
  Future<void> open() async {}

  @override
  Future<void> rawWrite(Uint8List bytes) async {}

  @override
  Future<void> nudgeCli() async {}

  @override
  Future<void> doClose() async {}
}

List<int> _bytes(int length) => List<int>.generate(length, (i) => i & 0xff);

void main() {
  // The regression. Both sentences are raised verbatim by the library -
  // `client.dart` and `session/session.dart` for the first,
  // `transport/ble/link.dart` for the second - and neither matched the
  // case-sensitive `contains` that `isLinkDropError` used to do, while the
  // dialog for the same event said "out of range".
  //
  // Written out rather than built from the constants on purpose: these are the
  // strings the sites actually hold, so rewording a constant fails here
  // instead of quietly taking the restart away again.
  group('an upload the link dies under', () {
    for (final sentence in const [
      'Cannot fetch device info: no active transport',
      'BLE transport closed',
      noActiveTransportMessage,
      transportClosedMessage,
      'Disconnected: link lost',
      'Request dropped: session torn down',
    ]) {
      test('restarts after "$sentence"', () async {
        final file = _bytes(2000);
        final client = _Flipper(failAttemptOneWith: StateError(sentence));

        await client.storageWriteChunked('/ext/nfc/x.nfc', file);

        expect(client.attempts, hasLength(2), reason: 'it restarted once');
        expect(
          client.attempts.last,
          file,
          reason: 'and sent the whole file again, from offset 0',
        );
        expect(client.waits, 1, reason: 'after waiting for the session back');
      });
    }

    test('restarts after a transport error', () async {
      final file = _bytes(2000);
      final client = _Flipper(
        failAttemptOneWith: FlipperTransportError('BLE write failed'),
      );

      await client.storageWriteChunked('/ext/nfc/x.nfc', file);

      expect(client.attempts, hasLength(2));
      expect(client.attempts.last, file);
    });

    // Once, not until it works: a link that keeps dying would otherwise upload
    // the same file forever. The second sentence differs from the first so the
    // failure the caller gets is identifiably the restart's own.
    test(
      'restarts once, then gives the second failure to the caller',
      () async {
        final client = _Flipper(
          failAttemptOneWith: StateError('BLE transport closed'),
          failLaterWith: StateError('BLE transport closed again'),
        );

        await expectLater(
          client.storageWriteChunked('/ext/nfc/x.nfc', _bytes(2000)),
          throwsA(
            isStateError.having(
              (e) => e.message,
              'message',
              'BLE transport closed again',
            ),
          ),
        );

        expect(client.attempts, hasLength(2));
        expect(client.waits, 1);
      },
    );

    // The other half of the wait: a reconnect that does not finish must hand
    // the original failure over rather than send the file into a dead session.
    test('is not restarted when the session does not come back', () async {
      final client = _Flipper(
        failAttemptOneWith: StateError('BLE transport closed'),
      )..rpcComesBack = false;

      await expectLater(
        client.storageWriteChunked('/ext/nfc/x.nfc', _bytes(2000)),
        throwsA(
          isStateError.having(
            (e) => e.message,
            'message',
            'BLE transport closed',
          ),
        ),
      );

      expect(client.waits, 1, reason: 'it asked');
      expect(
        client.attempts,
        hasLength(1),
        reason: 'and took no for an answer',
      );
    });
  });

  group('an upload that fails for a reason a reconnect cannot fix', () {
    test('is not restarted and reaches the caller', () async {
      final client = _Flipper(
        failAttemptOneWith: FlipperRpcStorageNotExistException(
          Main()
            ..commandId = 1
            ..commandStatus = CommandStatus.ERROR_STORAGE_NOT_EXIST,
        ),
      );

      await expectLater(
        client.storageWriteChunked('/ext/nope/x.nfc', _bytes(2000)),
        throwsA(isA<FlipperRpcStorageNotExistException>()),
      );

      expect(client.attempts, hasLength(1));
      expect(client.waits, 0);
    });

    // The near miss the shared reading has to keep out: a firmware error whose
    // text happens to be about storage, not about the link.
    test('a storage error naming no transport is not a drop', () async {
      final client = _Flipper(
        failAttemptOneWith: StateError('Storage error: ERROR_STORAGE_DENIED'),
      );

      await expectLater(
        client.storageWriteChunked('/ext/nfc/x.nfc', _bytes(2000)),
        throwsA(isStateError),
      );

      expect(client.attempts, hasLength(1));
      expect(client.waits, 0);
    });
  });

  // A cancel decided while the link was dying is a cancel, not a restart: the
  // check for it comes first in the catch, and swapping the two would re-send
  // a whole file the user had just stopped.
  group('an upload cancelled as the link died', () {
    test('is not restarted and says it was cancelled', () async {
      var dropped = false;
      final client = _Flipper(
        failAttemptOneWith: StateError('BLE transport closed'),
        onDrop: () => dropped = true,
      );

      await expectLater(
        client.storageWriteChunked(
          '/ext/nfc/x.nfc',
          _bytes(2000),
          isCancelled: () => dropped,
        ),
        throwsA(
          isA<FlipperWriteCancelledException>().having(
            (e) => e.path,
            'path',
            '/ext/nfc/x.nfc',
          ),
        ),
      );

      expect(client.attempts, hasLength(1));
      expect(client.waits, 0, reason: 'a cancel never reaches the wait');
    });
  });
}
