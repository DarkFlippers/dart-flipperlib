// What `configureConnected` throws when the service list it gets is not a
// Flipper's, and what it puts in the error.
//
// `FlipperServicesMissingError` is classified by type and carries `missing`,
// and until this file existed both of those facts were hand-transcribed into
// `connect_error_test.dart` and verified against nothing. The spellings in
// particular — `tx($flipperBleTxUuid)` through to
// `rpcStatus($rpcStatusCharUuid)` — are produced here and nowhere else, so a
// UUID constant or a label drifting would have left that file's literals
// passing while the real error said something different. QUNLEASHED-Y.
//
// The two shapes are the ones the field distinguishes and the error cannot:
// a service list with no Flipper service at all, which is Android handing over
// a stale cache, and a Flipper service missing one characteristic, which is
// old firmware. Both produce the same type; only the length of `missing`
// differs, and these cases are what make that observable.
import 'package:flutter_test/flutter_test.dart';

import 'package:flipperlib/src/model/connect_error.dart';
import 'package:flipperlib/src/transport/ble/gatt.dart';
import 'package:flipperlib/src/transport/ble/link.dart';
import 'package:flipperlib/src/transport/ble/ops.dart';

import 'ble_fixtures.dart';

/// Answers discovery with whatever it was handed, and nothing else.
class _FakeOps implements BleOps {
  _FakeOps(this.services);

  final List<BleService> services;

  @override
  Future<int> requestMtu(String deviceId, int mtu) async => 185;

  @override
  Future<List<BleService>> discoverServices(String deviceId) async => services;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    '${invocation.memberName} is not part of this path',
  );
}

UniversalBleTransportBase _transport(List<BleService> services) =>
    TestBleTransport(testFlipperDevice(), _FakeOps(services));

Future<FlipperServicesMissingError> _thrownBy(List<BleService> services) async {
  try {
    await _transport(services).configureConnected('dev');
  } on FlipperServicesMissingError catch (error) {
    return error;
  }
  fail('configureConnected accepted a service list it should have refused');
}

void main() {
  group('a service list with no Flipper service', () {
    test('is refused with the three required ones named', () async {
      // The stale-cache shape: Android answers discovery with a list that
      // does not contain the Flipper service at all, so the loop matches
      // nothing and every characteristic reads as absent.
      //
      // Three and not four: `rpcStatus` is absent here too, and is no longer
      // required - see the group at the bottom.
      final error = await _thrownBy([]);

      expect(error.missing, hasLength(3));
    });

    test('and names them as the classifier test spells them', () async {
      // The one place these strings are produced. `connect_error_test.dart`
      // writes them out by hand to pin a reword at this throw site; this is
      // what makes that hand copy true of the real error.
      final error = await _thrownBy([]);

      expect(error.missing, [
        'tx($flipperBleTxUuid)',
        'rx($flipperBleRxUuid)',
        'overflow(${UniversalBleTransportBase.overflowCharUuid})',
      ]);
    });

    test('and classifies by type, not by its sentence', () async {
      final error = await _thrownBy([]);

      expect(
        classifyConnectError(error),
        FlipperConnectErrorKind.servicesMissing,
      );
    });

    // A service that is not the Flipper's is the same as none: the loop skips
    // it on the UUID. Pinned because "no Flipper service" and "no services"
    // are different inputs and only one of them is the realistic one.
    test('and a list of somebody else-s services reads the same', () async {
      final error = await _thrownBy([
        BleService('0000180a-0000-1000-8000-00805f9b34fb', [
          flipperChar('00002a29-0000-1000-8000-00805f9b34fb'),
        ]),
      ]);

      expect(error.missing, hasLength(3));
    });
  });

  group('a Flipper service missing one characteristic', () {
    test('names only the one that is absent', () async {
      // Old firmware without the overflow channel, which is the other cause
      // the docs on this error distinguish - and the case that shows the two
      // are told apart by the length of `missing` and nothing else.
      final chars = allFlipperChars()
        ..removeWhere(
          (c) => c.uuid == UniversalBleTransportBase.overflowCharUuid,
        );
      final error = await _thrownBy([BleService(flipperBleServiceUuid, chars)]);

      expect(error.missing, [
        'overflow(${UniversalBleTransportBase.overflowCharUuid})',
      ]);
    });

    test('and still carries a message that classifies untyped', () async {
      final chars = allFlipperChars()
        ..removeWhere((c) => c.uuid == flipperBleRxUuid);
      final error = await _thrownBy([BleService(flipperBleServiceUuid, chars)]);

      // Through the string arm rather than the type, which is what an older
      // build of this library hands the app.
      expect(
        classifyConnectError(StateError(error.message)),
        FlipperConnectErrorKind.servicesMissing,
      );
    });
  });

  group('a Flipper service with no rpcStatus characteristic', () {
    // QUNLEASHED-14: a real Flipper answered discovery with tx, rx and
    // overflow and no rpcStatus - old firmware - and the link refused it. Six
    // events in under two minutes, because auto-reconnect kept trying.
    //
    // Refusing was the inconsistency: `_subscribeRpcStatus` already catches a
    // failed subscribe, clears `_rpcStatusAvailable` and falls back to ungated
    // TX, so the same condition was survivable when the subscribe failed and
    // fatal when the characteristic was absent.
    List<BleService> withoutRpcStatus() => [
      BleService(
        flipperBleServiceUuid,
        allFlipperChars()..removeWhere(
          (c) => c.uuid == UniversalBleTransportBase.rpcStatusCharUuid,
        ),
      ),
    ];

    test('is accepted', () async {
      // The whole of the fix. Before it, this threw.
      await expectLater(
        _transport(withoutRpcStatus()).configureConnected('dev'),
        completes,
      );
    });

    test('and is still refused when a required one is missing too', () async {
      // So the case above cannot pass by `configureConnected` having stopped
      // refusing anything at all.
      final chars = allFlipperChars()
        ..removeWhere(
          (c) =>
              c.uuid == UniversalBleTransportBase.rpcStatusCharUuid ||
              c.uuid == flipperBleRxUuid,
        );
      final error = await _thrownBy([BleService(flipperBleServiceUuid, chars)]);

      // Names the required one and not the optional one.
      expect(error.missing, ['rx($flipperBleRxUuid)']);
    });
  });

  test('a complete Flipper service is accepted', () async {
    // The precondition the six cases above rest on: this harness can produce
    // a list that does *not* throw. Without it they would all pass against a
    // `configureConnected` that refused everything.
    await _transport([BleService(flipperBleServiceUuid, allFlipperChars())])
        .configureConnected('dev');
  });
}
