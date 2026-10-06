import 'dart:io';
import 'dart:typed_data';

import 'package:flipperlib/src/model/enums.dart';
import 'package:flipperlib/src/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who releases the platform resource, and when.
///
/// The base class makes this easy to get wrong, and it was: `onTransportFault`
/// sets the lifecycle straight to `closed`, and `close()` returns early unless
/// it is `active` - so after a fault `doClose()` is unreachable. A subclass that
/// only frees things in `doClose()` therefore leaks them on every fault. For the
/// USB transport that meant the OS handle on the COM port stayed open for the
/// life of the process and auto-reconnect then opened a second port on the same
/// COM, against one its own orphan still held.
///
/// These pin the base class's half of the contract, so the asymmetry is written
/// down rather than rediscovered. The BLE subclass has always compensated in
/// `onFaultExtra`; the USB one now does too.
class _FakeTransport extends Transport {
  _FakeTransport({this.releaseOnFault = true});

  /// Whether this subclass does what USB now does. False reproduces the bug.
  final bool releaseOnFault;

  int released = 0;
  int faults = 0;
  bool _done = false;

  void _release() {
    if (_done) return;
    _done = true;
    released++;
  }

  @override
  void onFaultExtra(Object error) {
    faults++;
    if (releaseOnFault) _release();
  }

  @override
  Future<void> doClose() async => _release();

  @override
  Future<void> open() async {}

  @override
  bool get supportsCli => false;

  @override
  FlipperMode get initialMode => FlipperMode.rpc;

  @override
  Future<void> rawWrite(Uint8List bytes) async {}

  @override
  Future<void> nudgeCli() async {}
}

/// The real USB subclass cannot be instantiated here - its constructor spawns
/// an isolate and opens a serial port - so the tests above pin the base class's
/// contract with a fake and this one pins that USB actually honours it.
///
/// A source assertion rather than a behavioural one, deliberately, and in the
/// same spirit as this repo's other ratchets: removing the release call from the
/// real `onFaultExtra` passes every behavioural test in this file, because they
/// exercise the fake. Crude, and better than the alternative, which is nothing.
void _usbHonoursTheContract() {
  group('the USB transport', () {
    test('releases the port from its fault path, not only from doClose', () {
      final source = File('lib/src/transport/usb/link.dart').readAsStringSync();

      final faultBody = source.substring(
        source.indexOf('void onFaultExtra('),
        source.indexOf('Future<void> doClose()'),
      );

      expect(
        faultBody,
        contains('_release()'),
        reason:
            'after a fault doClose() is unreachable, so this is the only '
            'place the COM handle goes back',
      );
      expect(
        source,
        contains('if (_released) return;'),
        reason:
            'and it has to be idempotent: a fault and a close can both '
            'reach it',
      );
    });
  });
}

void main() {
  _usbHonoursTheContract();
  group('a transport that faults', () {
    test('never reaches doClose, so close() cannot free anything', () async {
      // The bug, reproduced: a subclass that frees only in doClose().
      final transport = _FakeTransport(releaseOnFault: false);

      transport.onTransportFault(StateError('link dropped'));
      await transport.close();

      expect(transport.faults, 1);
      expect(
        transport.released,
        0,
        reason:
            'this is the leak - close() bails because the fault already '
            'moved the lifecycle to closed',
      );
    });

    test('releases from onFaultExtra instead', () async {
      final transport = _FakeTransport();

      transport.onTransportFault(StateError('link dropped'));

      expect(transport.released, 1, reason: 'the handle goes back at once');
    });

    test('releases once, however many times it is asked', () async {
      final transport = _FakeTransport();

      transport.onTransportFault(StateError('first'));
      // A fault can arrive from several places - a write ack, an isolate fault
      // message, the isolate exiting - and the client calls close() on its way
      // through reconnect regardless.
      transport.onTransportFault(StateError('second'));
      await transport.close();
      await transport.close();

      expect(transport.released, 1);
      expect(
        transport.faults,
        1,
        reason: 'the base class already swallows a repeat fault',
      );
    });

    test('is closed, and says why', () {
      final transport = _FakeTransport();
      final reason = StateError('link dropped');

      transport.onTransportFault(reason);

      expect(transport.isClosed, isTrue);
      expect(transport.isActive, isFalse);
      expect(transport.closeReason, same(reason));
    });
  });

  group('a transport closed in order', () {
    test('releases through doClose', () async {
      final transport = _FakeTransport(releaseOnFault: false);

      await transport.close();

      expect(transport.released, 1);
      expect(transport.faults, 0, reason: 'an orderly close is not a fault');
      expect(transport.isClosed, isTrue);
    });

    test('stops accepting bytes once closed', () async {
      final transport = _FakeTransport();
      final seen = <List<int>>[];
      transport.bytesStream.listen(seen.add);

      transport.addBytes(const [1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      await transport.close();
      transport.addBytes(const [4, 5, 6]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [
        const [1, 2, 3],
      ]);
    });
  });
}
