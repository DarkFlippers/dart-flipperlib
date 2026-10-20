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
import 'package:universal_ble/universal_ble.dart' as uble;

import 'package:flipperlib/src/model/connect_error.dart';
import 'package:flipperlib/src/model/discovered.dart';
import 'package:flipperlib/src/transport/ble/gatt.dart';
import 'package:flipperlib/src/transport/ble/link.dart';
import 'package:flipperlib/src/transport/ble/ops.dart';

BleChar _char(String uuid) => BleChar(
  uuid,
  canWrite: true,
  canWriteNoRsp: true,
  canNotify: true,
  canIndicate: false,
);

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
    _TestTransport(
      BleDiscoveredDevice(uble.BleDevice(deviceId: 'dev', name: 'Flipper')),
      _FakeOps(services),
    );

class _TestTransport extends UniversalBleTransportBase {
  _TestTransport(super.device, super.ops);
}

/// Every characteristic a Flipper carries, so a case can drop exactly one.
List<BleChar> _allChars() => [
  _char(flipperBleTxUuid),
  _char(flipperBleRxUuid),
  _char(UniversalBleTransportBase.overflowCharUuid),
  _char(UniversalBleTransportBase.rpcStatusCharUuid),
];

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
    test('is refused with all four named', () async {
      // The stale-cache shape: Android answers discovery with a list that
      // does not contain the Flipper service at all, so the loop matches
      // nothing and every characteristic reads as absent.
      final error = await _thrownBy([]);

      expect(error.missing, hasLength(4));
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
        'rpcStatus(${UniversalBleTransportBase.rpcStatusCharUuid})',
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
          _char('00002a29-0000-1000-8000-00805f9b34fb'),
        ]),
      ]);

      expect(error.missing, hasLength(4));
    });
  });

  group('a Flipper service missing one characteristic', () {
    test('names only the one that is absent', () async {
      // Old firmware without the overflow channel, which is the other cause
      // the docs on this error distinguish - and the case that shows the two
      // are told apart by the length of `missing` and nothing else.
      final chars = _allChars()
        ..removeWhere(
          (c) => c.uuid == UniversalBleTransportBase.overflowCharUuid,
        );
      final error = await _thrownBy([BleService(flipperBleServiceUuid, chars)]);

      expect(error.missing, [
        'overflow(${UniversalBleTransportBase.overflowCharUuid})',
      ]);
    });

    test('and still carries a message that classifies untyped', () async {
      final chars = _allChars()..removeWhere((c) => c.uuid == flipperBleRxUuid);
      final error = await _thrownBy([BleService(flipperBleServiceUuid, chars)]);

      // Through the string arm rather than the type, which is what an older
      // build of this library hands the app.
      expect(
        classifyConnectError(StateError(error.message)),
        FlipperConnectErrorKind.servicesMissing,
      );
    });
  });

  test('a complete Flipper service is accepted', () async {
    // The precondition the six cases above rest on: this harness can produce
    // a list that does *not* throw. Without it they would all pass against a
    // `configureConnected` that refused everything.
    await _transport([BleService(flipperBleServiceUuid, _allChars())])
        .configureConnected('dev');
  });
}
