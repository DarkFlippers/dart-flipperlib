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

  /// Every value the transport asked for, so the request itself can be pinned
  /// rather than only its answer.
  final List<int> requested = [];

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    requested.add(mtu);
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

/// Stands in for a CoreBluetooth platform: the one that negotiates the MTU on
/// the link's behalf and so wants reading again after discovery.
class _TestTransport extends UniversalBleTransportBase {
  _TestTransport(super.device, super.ops);

  @override
  bool get mtuSettlesAfterDiscovery => true;
}

/// Stands in for the platforms that get their figure from the first ask.
class _NoResettleTransport extends UniversalBleTransportBase {
  _NoResettleTransport(super.device, super.ops);
}

UniversalBleTransportBase _transport(_FakeOps ops) => _TestTransport(
  BleDiscoveredDevice(uble.BleDevice(deviceId: 'dev', name: 'Flipper')),
  ops,
);

const _cap = UniversalBleTransportBase.maxBleMtuSize;
// The clamp floor: what an unnegotiated 23-byte ATT_MTU leaves.
const _minPayload = 20;

void main() {
  final logged = <String>[];

  setUp(() {
    UniversalBleTransportBase.resetSlowLinkLatch();
    logged.clear();
    Log.sink = (level, message) => logged.add('${level.name}: $message');
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

    expect(transport.bleMtuSize, _cap);
    expect(ops.calls, 1, reason: 'a saturated reading must not be re-read');
  });

  test('a read that throws leaves the last good reading standing', () async {
    final ops = _FakeOps(mtus: [185], throwFromCall: 2);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, 182);
    expect(logged, contains(contains('MTU read failed')));
  });

  test('a link that stays small says so where a report will carry it', () async {
    // The host keeps warnings and errors for a bug report and drops the rest,
    // so this is the only level at which "the link is slow" survives to be read
    // back. Both reads answer small: the link really is at 23.
    final ops = _FakeOps(mtus: [23, 23]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, _minPayload);
    // At warning, not info. A consumer keeps warnings for a bug report and
    // drops what is below them, so a demotion would delete the line from the
    // one place it exists to appear - while leaving every other assertion here
    // green.
    expect(
      logged,
      contains(
        contains('warning: [BLE] link carries only payload=$_minPayload'),
      ),
    );
  });

  // The rule the pairing reconnect rests on: that path measures a *different*
  // link, and keeping a larger earlier figure would put every write above the
  // new link's ATT MTU, where it is silently promoted to a long write. Every
  // other case here feeds non-decreasing readings, so "takes the newer" and
  // "takes the larger" are indistinguishable across all of them - and the
  // larger-wins version passed the whole file.
  test('a later, smaller reading replaces a larger one', () async {
    final ops = _FakeOps(mtus: [185, 23]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(
      transport.bleMtuSize,
      _minPayload,
      reason: 'the reading taken after discovery is the one that counts',
    );
  });

  // Android and the rest take what the first ask granted. Reading again there
  // is not free: its stack ignores a repeat request while universal_ble parks
  // the callback, so the ask can hold the package's global queue.
  test('a platform that settles on the first ask is not asked twice', () async {
    final ops = _FakeOps(mtus: [185, 414]);
    final transport = _NoResettleTransport(
      BleDiscoveredDevice(uble.BleDevice(deviceId: 'dev', name: 'Flipper')),
      ops,
    );

    await transport.configureConnected('dev');

    expect(ops.calls, 1);
    expect(transport.bleMtuSize, 182, reason: 'the first reading stands');
  });

  test('asks for the largest MTU the platform will take', () async {
    final ops = _FakeOps(mtus: [23, 185]);

    await _transport(ops).configureConnected('dev');

    // Android grants what it is asked for, up to the firmware ceiling, so this
    // number is the one that decides the payload on the platform the
    // saturation guard assumes will saturate.
    expect(ops.requested, everyElement(517));
  });

  test('the threshold is where it says it is', () async {
    // Without a pair either side of it, any value from 21 to 181 keeps the two
    // cases above green and the constant means nothing.
    Future<bool> warnsAtPayload(int payload) async {
      logged.clear();
      await _transport(_FakeOps(mtus: [23, payload + 3]))
          .configureConnected('dev');
      return logged.any((line) => line.contains('link carries only'));
    }

    expect(await warnsAtPayload(99), isTrue);
    expect(await warnsAtPayload(100), isFalse);
  });

  test('a healthy link says nothing about being slow', () async {
    final ops = _FakeOps(mtus: [23, 185]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(logged, isNot(contains(contains('link carries only'))));
  });

  test('the payload never exceeds the firmware ATT ceiling', () async {
    // A platform reporting more than the firmware can take must still be cut
    // to the cap: a larger write becomes a long write, which it handles worse.
    final ops = _FakeOps(mtus: [23, 4096]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, _cap);
  });
}
