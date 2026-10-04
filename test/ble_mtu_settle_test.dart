// Covers the MTU read in `configureConnected`, whose reason for existing is on
// `_applyMtu` in link.dart and not repeated here.
//
// These drive the real `configureConnected` through a fake `BleOps`. Against
// the pre-fix code the first case fails with mtu=20, which is what shipped.
//
// What they cannot see: whether a real CoreBluetooth link reports a larger
// value by the time discovery completes - that is the premise, and only a
// device can confirm it - and the pairing-reconnect path, which calls the same
// method but is reached only through a live pairing failure.
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

import 'package:flipperlib/src/common/log.dart';
import 'package:flipperlib/src/model/discovered.dart';
import 'package:flipperlib/src/transport/ble/gatt.dart';
import 'package:flipperlib/src/transport/ble/link.dart';
import 'package:flipperlib/src/transport/ble/ops.dart';

/// `configureConnected` reads only these three flags, so the rest are noise.
BleChar _char(String uuid, {bool write = false, bool notify = false}) =>
    BleChar(
      uuid,
      canWrite: write,
      canWriteNoRsp: write,
      canNotify: notify,
      canIndicate: false,
    );

/// Answers the two calls `configureConnected` makes, and nothing else.
class _FakeOps implements BleOps {
  _FakeOps({required this.mtus, this.throwFromCall});

  /// One reading per `requestMtu` call, in order. Indexed without a bound so an
  /// unexpected extra call is a range error rather than a silently repeated
  /// reading.
  final List<int> mtus;

  /// 1-based call number from which `requestMtu` throws instead of answering.
  final int? throwFromCall;
  int calls = 0;

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    calls++;
    if (throwFromCall != null && calls >= throwFromCall!) {
      throw StateError('platform refused');
    }
    return mtus[calls - 1];
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async => [
    BleService(flipperBleServiceUuid, [
      _char(flipperBleTxUuid, write: true),
      _char(flipperBleRxUuid, notify: true),
      _char(UniversalBleTransportBase.overflowCharUuid, notify: true),
      _char(UniversalBleTransportBase.rpcStatusCharUuid, notify: true),
    ]),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    '${invocation.memberName} is not part of this path',
  );
}

class _TestTransport extends UniversalBleTransportBase {
  _TestTransport(super.device, super.ops);
}

UniversalBleTransportBase _transport(_FakeOps ops) => _TestTransport(
  BleDiscoveredDevice(uble.BleDevice(deviceId: 'dev', name: 'Flipper')),
  ops,
);

void main() {
  final logged = <String>[];

  setUp(() {
    logged.clear();
    Log.sink = (level, message) => logged.add(message);
    Log.level = FlipperLogLevel.trace;
  });

  tearDown(() {
    Log.sink = null;
    Log.level = FlipperLogLevel.info;
  });

  test('a reading taken before the exchange settled is replaced', () async {
    // 23 is the default Apple leaves before negotiating; 185 is a plausible
    // settled iOS value. Pre-fix this ended at (23 - 3) = 20.
    final ops = _FakeOps(mtus: [23, 185]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, 182);
    expect(ops.calls, 2, reason: 'the MTU must be read again after discovery');
    expect(logged, contains(contains('negotiatedMtu=185 mtu=182')));
  });

  test('a saturated first reading is not asked about again', () async {
    // What Android does: it grants the firmware's 414 ceiling when asked, which
    // already fills the clamp. Asking again could only cost - its stack ignores
    // repeat requests and the plugin waits on a reply that may never come,
    // blocking the queue the subscribes are behind.
    final ops = _FakeOps(mtus: [414]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, UniversalBleTransportBase.maxBleMtuSize);
    expect(ops.calls, 1, reason: 'a saturated reading must not be re-read');
  });

  test('a read that throws leaves the last good reading standing', () async {
    final ops = _FakeOps(mtus: [185], throwFromCall: 2);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, 182);
    expect(logged, contains(contains('MTU read failed')));
  });

  test('the payload never exceeds the firmware ATT ceiling', () async {
    // A platform reporting more than the firmware can take must still be cut
    // to the cap: a larger write becomes a long write, which it handles worse.
    final ops = _FakeOps(mtus: [23, 4096]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, UniversalBleTransportBase.maxBleMtuSize);
  });
}
