import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/src/model/connect_error.dart';
import 'package:flipperlib/src/model/enums.dart';
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// What bounds a USB open, and what happens to a port that answers too late.
///
/// `openWithin` exists as a function because there is no seam to fake
/// `usbPlatform` behind - it is a top-level `final` built by
/// `createUsbPlatform()` - so the alternative to this file is no coverage of
/// the deadline at all. The call site in `FlipperSession.establishLocked`
/// passes `FlipperClient.usbOpenTimeout` and applies it to USB only; that
/// wiring is not covered here, which is the gap this shape accepts.
///
/// Why it is bounded: `usb_serial`'s `openDevice` completes its platform
/// result only from the `ACTION_USB_PERMISSION` broadcast, and nothing on the
/// path used to put a deadline on an answer that never arrives - so the
/// session, the client's lifecycle chain and the consumer's reconcile loop
/// were held for the life of the process, with `abortConnectInFlight` unable
/// to cancel a USB connect.
class _FakeTransport extends Transport {
  var closes = 0;

  @override
  bool get supportsCli => true;

  @override
  FlipperMode get initialMode => FlipperMode.cli;

  @override
  Future<void> open() async {}

  @override
  Future<void> rawWrite(Uint8List bytes) async {}

  @override
  Future<void> nudgeCli() async {}

  // The hook `close()` runs, so counting here counts a real close rather
  // than an override that skipped the base contract.
  @override
  Future<void> doClose() async => closes++;
}

void main() {
  const limit = Duration(milliseconds: 50);

  test('an open that answers in time is handed straight back', () async {
    final transport = _FakeTransport();

    final opened = await openWithin(Future.value(transport), limit, () => 'A');

    expect(opened, same(transport));
    expect(transport.closes, 0, reason: 'nothing timed out');
  });

  test('an open that never answers throws rather than waiting', () async {
    // Never completed, which is the condition: a permission broadcast that
    // does not arrive.
    final stuck = Completer<Transport>();

    await expectLater(
      openWithin(stuck.future, limit, () => 'A (usb:1)'),
      throwsA(
        isA<FlipperUsbOpenUnansweredError>()
            .having((e) => e.device, 'device', 'A (usb:1)')
            .having((e) => e.limit, 'limit', limit),
      ),
    );
  });

  // The half that is not about giving up: a port handed over after the
  // deadline is live and nobody holds it. On desktop libserialport opens
  // exclusively, so leaving it would strand the port for the life of the
  // process and make the next attempt fail with "access is denied" - a
  // different fault, and the wrong one to show somebody.
  test(
    'a port that answers after the deadline is closed, not stranded',
    () async {
      final late = Completer<Transport>();
      final transport = _FakeTransport();

      await expectLater(
        openWithin(late.future, limit, () => 'A'),
        throwsA(isA<FlipperUsbOpenUnansweredError>()),
      );
      expect(transport.closes, 0, reason: 'has not been handed over yet');

      late.complete(transport);
      await pumpEventQueue();

      expect(transport.closes, 1);
    },
  );

  test(
    'an open that fails after the deadline is not an unhandled error',
    () async {
      final late = Completer<Transport>();

      await expectLater(
        openWithin(late.future, limit, () => 'A'),
        throwsA(isA<FlipperUsbOpenUnansweredError>()),
      );

      // The ordinary shape of a late answer: a denial that arrives once nobody
      // is listening. With no handler this reaches the zone and fails the test,
      // which is what the `onError` in `openWithin` is there to stop.
      late.completeError(StateError('USB permission denied'));
      await pumpEventQueue();
    },
  );

  // The reason the error is typed rather than a `TimeoutException`:
  // `classifyConnectError` matches a bare `timeout` and `timed out`, which
  // would make a cable that never answered read as a Flipper out of range and
  // tell the user to move closer to it.
  test('it classifies as a USB failure, not a range problem', () {
    const error = FlipperUsbOpenUnansweredError('A', limit);

    expect(classifyConnectError(error), FlipperConnectErrorKind.unknown);
    expect(
      classifyConnectError(TimeoutException('timed out', limit)),
      FlipperConnectErrorKind.deviceUnreachable,
      reason: 'which is what the typed error exists to avoid',
    );
  });
}
