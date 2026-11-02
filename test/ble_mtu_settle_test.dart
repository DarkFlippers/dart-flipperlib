// Covers the MTU read in `configureConnected`, whose reason for existing is on
// `applyMtu` in link.dart and not repeated here.
//
// These drive the real `configureConnected` through a fake `BleOps`.
//
// The rule changed with universal_ble 3.0.0 (#444). It used to be "ask before
// discovery, and on CoreBluetooth ask again after"; from 3.0.0 the ask is what
// makes Apple and Linux discover the services, so asking before a discovery we
// are about to make ourselves bought the same unnegotiated 23 and paid a whole
// extra discovery for it. The rule is now one ask per link, placed by
// `mtuSettlesAfterDiscovery`: before discovery where the platform answers from
// the connection (Android, Windows), after it where it does not (Apple, Linux).
// The case that pins the placement is the first one here.
//
// What they cannot see: whether a real CoreBluetooth link reports a larger
// value by the time discovery completes - that is the premise, and only a
// device can confirm it.
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

  /// The two calls in the order they were made. The placement of the MTU read
  /// relative to discovery is the subject of the first case, and it is the one
  /// thing about this method that an answer cannot show.
  final List<String> order = [];

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    order.add('mtu');
    requested.add(mtu);
    calls++;
    if (throwFromCall != null && calls >= throwFromCall!) {
      throw StateError('platform refused');
    }
    return mtus[calls - 1];
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    order.add('discover');
    return [
      BleService(flipperBleServiceUuid, [
        _char(flipperBleTxUuid, write: true),
        _char(flipperBleRxUuid, notify: true),
        _char(UniversalBleTransportBase.overflowCharUuid, notify: true),
        _char(UniversalBleTransportBase.rpcStatusCharUuid, notify: true),
      ]),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    '${invocation.memberName} is not part of this path',
  );
}

/// Stands in for CoreBluetooth and BlueZ: the platforms with no MTU to give
/// until the services are known.
class _TestTransport extends UniversalBleTransportBase {
  _TestTransport(super.device, super.ops);

  @override
  bool get mtuSettlesAfterDiscovery => true;
}

/// Stands in for Android and Windows, which answer from the connection itself.
class _NoResettleTransport extends UniversalBleTransportBase {
  _NoResettleTransport(super.device, super.ops);
}

UniversalBleTransportBase _transport(_FakeOps ops) => _TestTransport(
  BleDiscoveredDevice(uble.BleDevice(deviceId: 'dev', name: 'Flipper')),
  ops,
);

UniversalBleTransportBase _earlyAskTransport(_FakeOps ops) =>
    _NoResettleTransport(
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

  test('a platform with nothing to say yet is asked after discovery', () async {
    // The whole of #444's MTU half. Asking first is not merely useless on
    // these platforms: from universal_ble 3.0.0 the ask discovers the
    // services to answer, so the link paid for two discoveries per connect -
    // on every auto-reconnect cycle too - and the second one had whatever was
    // left of its budget. Only the order can show it; the reading is the same
    // either way.
    final ops = _FakeOps(mtus: [185]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(ops.order, ['discover', 'mtu']);
    expect(ops.calls, 1, reason: 'one ask per link, not two');
    expect(transport.bleMtuSize, 182);
    expect(logged, contains(contains('negotiatedMtu=185 mtu=182')));
  });

  test('a platform that answers from the connection is asked first', () async {
    // Android's half of the same rule, and the reason the flag is declared
    // rather than inferred: Android grants the MTU when asked and wants asking
    // before the traffic that benefits, discovery included.
    final ops = _FakeOps(mtus: [185]);
    final transport = _earlyAskTransport(ops);

    await transport.configureConnected('dev');

    expect(ops.order, ['mtu', 'discover']);
    expect(ops.calls, 1);
    expect(transport.bleMtuSize, 182, reason: 'the first reading stands');
  });

  test('a read that throws leaves the link at the ATT floor', () async {
    // Not at a figure from an earlier link: a payload sized for a larger
    // previous link is silently promoted to a long write on a smaller new one,
    // which this firmware handles far worse. `applyMtu` drops what it holds
    // before it reads, which is what makes the floor the fallback.
    final ops = _FakeOps(mtus: const [], throwFromCall: 1);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, _minPayload);
    expect(logged, contains(contains('MTU read failed')));
  });

  // The rule the pairing reconnect rests on. That path measures a *different*
  // link, and keeping the larger of the two figures would put every write
  // above the new link's ATT MTU. It is driven directly because it is the one
  // caller that reads an MTU onto a transport that already holds one -
  // `configureConnected` cannot be run twice (its characteristic ids are
  // `late final`), and a larger-wins version of `applyMtu` passed this whole
  // file before the case existed.
  test('a later, smaller reading replaces a larger one', () async {
    final ops = _FakeOps(mtus: [185, 23]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');
    expect(transport.bleMtuSize, 182);

    await transport.applyMtu('dev');

    expect(
      transport.bleMtuSize,
      _minPayload,
      reason:
          'the reading taken on the link in front of it is the one that counts',
    );
  });

  test('a read that throws does not keep the figure from an earlier link', () async {
    // The reset in `applyMtu`, which is the half of it a successful read
    // cannot show: the first read here succeeds at 185, the second throws, and
    // without the reset the link would keep writing 182-byte payloads sized
    // for a link it is no longer on - promoted to long writes on the new one.
    final ops = _FakeOps(mtus: [185], throwFromCall: 2);
    final transport = _transport(ops);

    await transport.configureConnected('dev');
    expect(transport.bleMtuSize, 182);

    await transport.applyMtu('dev');

    expect(transport.bleMtuSize, _minPayload);
    expect(logged, contains(contains('MTU read failed')));
  });

  test('a link that stays small says so where a report will carry it', () async {
    // The host keeps warnings and errors for a bug report and drops the rest,
    // so this is the only level at which "the link is slow" survives to be read
    // back. The link really is at 23.
    final ops = _FakeOps(mtus: [23]);
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

  test('asks for the largest MTU the platform will take', () async {
    final ops = _FakeOps(mtus: [185]);

    await _transport(ops).configureConnected('dev');

    // Android grants what it is asked for, up to the firmware ceiling, so this
    // number is the one that decides the payload there.
    expect(ops.requested, everyElement(517));
  });

  test('the threshold is where it says it is', () async {
    // Without a pair either side of it, any value from 21 to 181 keeps the two
    // cases above green and the constant means nothing.
    Future<bool> warnsAtPayload(int payload) async {
      logged.clear();
      await _transport(_FakeOps(mtus: [payload + 3])).configureConnected('dev');
      return logged.any((line) => line.contains('link carries only'));
    }

    expect(await warnsAtPayload(99), isTrue);
    expect(await warnsAtPayload(100), isFalse);
  });

  test('a healthy link says nothing about being slow', () async {
    final ops = _FakeOps(mtus: [185]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(logged, isNot(contains(contains('link carries only'))));
  });

  test('the payload never exceeds the firmware ATT ceiling', () async {
    // A platform reporting more than the firmware can take must still be cut
    // to the cap: a larger write becomes a long write, which it handles worse.
    final ops = _FakeOps(mtus: [4096]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, _cap);
  });
}
