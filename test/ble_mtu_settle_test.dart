// Covers the MTU read in `configureConnected`, whose reason for existing is on
// `applyMtu` in link.dart and not repeated here.
//
// These drive the real `configureConnected` through a fake `BleOps`.
//
// The rule changed with universal_ble 3.0.0 (#444). It used to be "ask before
// discovery, and on CoreBluetooth ask again after"; from 3.0.0 the ask is what
// makes Apple and Linux discover the services, so asking before a discovery we
// are about to make ourselves bought the same unnegotiated 23 and paid a whole
// extra discovery for it. The rule is now one ask per link, placed by whether
// the platform can answer before discovery - which the plugin itself reports,
// and which the fake here answers for the platform it stands in for. The first
// two cases pin the placement, and only the call order can see it: the reading
// is the same either way.
//
// What they cannot see: whether a real CoreBluetooth link reports a larger
// value by the time discovery completes - that is the premise, and only a
// device can confirm it.
import 'package:flutter_test/flutter_test.dart';

import 'package:flipperlib/src/common/log.dart';
import 'package:flipperlib/src/transport/ble/gatt.dart';
import 'package:flipperlib/src/transport/ble/link.dart';
import 'package:flipperlib/src/transport/ble/ops.dart';

import 'ble_fixtures.dart';

/// `configureConnected` reads only these three flags, so the rest are noise.
/// Kept here rather than taken from `ble_fixtures.dart`'s all-true shape
/// because the per-flag precision is the subject under test in this file -
/// which is what that file's own header says about this one.
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
  _FakeOps({required this.answers, this.mtuNeedsDiscovery = true});

  /// One answer per `requestMtu` call, in order: an `int` to report, or
  /// anything else to throw. Indexed without a bound, so an unexpected extra
  /// call is a range error rather than a silently repeated reading.
  final List<Object> answers;

  /// What the platform this fake stands in for can do, which is what places
  /// the read. True is Apple and Linux, false is Android and Windows.
  @override
  final bool mtuNeedsDiscovery;

  int calls = 0;

  /// Every value the transport asked for, so the request itself can be pinned
  /// rather than only its answer.
  final List<int> requested = [];

  /// The two calls in the order they were made, which is the one thing about
  /// this method that an answer cannot show.
  final List<String> order = [];

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    order.add('mtu');
    requested.add(mtu);
    final answer = answers[calls++];
    if (answer is int) return answer;
    throw answer;
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

UniversalBleTransportBase _transport(_FakeOps ops) =>
    TestBleTransport(testFlipperDevice(), ops);

const _cap = UniversalBleTransportBase.maxBleMtuSize;
// The clamp floor: what an unnegotiated 23-byte ATT_MTU leaves.
const _minPayload = 20;
final _refused = StateError('platform refused');

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
    // these platforms: from universal_ble 3.0.0 the ask discovers the services
    // to answer, so the link paid for two discoveries per connect - on every
    // auto-reconnect cycle too - and the second got whatever was left of the
    // budget.
    final ops = _FakeOps(answers: [185]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(ops.order, ['discover', 'mtu'], reason: 'one ask, and after it');
    expect(transport.bleMtuSize, 182);
    expect(logged, contains(contains('negotiatedMtu=185 mtu=182')));
    // A healthy link says nothing about being slow.
    expect(logged, isNot(contains(contains('link carries only'))));
    // Android grants what it is asked for, up to the firmware ceiling, so this
    // number is the one that decides the payload there. A list rather than
    // `everyElement`, which passes on an empty one - and an empty one is what a
    // mutant that skips the read entirely leaves behind.
    expect(ops.requested, [517]);
  });

  test('a platform that answers from the connection is asked first', () async {
    // Android's half of the same rule: it grants the MTU when asked and wants
    // asking before the traffic that benefits, discovery included.
    final ops = _FakeOps(answers: [185], mtuNeedsDiscovery: false);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(ops.order, ['mtu', 'discover']);
    expect(transport.bleMtuSize, 182, reason: 'the first reading stands');
  });

  test('a read that throws leaves the link at the ATT floor', () async {
    // Not at a figure from an earlier link: a payload sized for a larger
    // previous link is silently promoted to a long write on a smaller new one,
    // which this firmware handles far worse. `applyMtu` drops what it holds
    // before it reads, which is what makes the floor the fallback.
    final ops = _FakeOps(answers: [_refused]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, _minPayload);
    expect(logged, contains(contains('MTU read failed')));
  });

  test('a read that throws does not keep an earlier figure', () async {
    // The reset in `applyMtu`, which is the half a successful read cannot
    // show: the first read succeeds at 185, the second throws, and without the
    // reset the link would keep writing 182-byte payloads sized for a link it
    // is no longer on.
    final ops = _FakeOps(answers: [185, _refused]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');
    expect(transport.bleMtuSize, 182);

    await transport.applyMtu('dev');

    expect(transport.bleMtuSize, _minPayload);
    expect(logged, contains(contains('MTU read failed')));
  });

  // The rule the pairing reconnect rests on. That path measures a *different*
  // link, and keeping the larger of the two figures would put every write above
  // the new link's ATT MTU. It is driven directly because it is the one caller
  // that reads an MTU onto a transport that already holds one -
  // `configureConnected` cannot be run twice (its characteristic ids are
  // `late final`), and a larger-wins version of `applyMtu` passed this whole
  // file before the case existed.
  test('a later, smaller reading replaces a larger one', () async {
    final ops = _FakeOps(answers: [185, 23]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');
    expect(transport.bleMtuSize, 182);

    await transport.applyMtu('dev');

    expect(
      transport.bleMtuSize,
      _minPayload,
      reason: 'the reading taken on the link in front of it is what counts',
    );
  });

  test('a link that stays small says so where a report will carry it', () async {
    // The host keeps warnings and errors for a bug report and drops the rest,
    // so this is the only level at which "the link is slow" survives to be read
    // back. The link really is at 23.
    final ops = _FakeOps(answers: [23]);
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

  test('the threshold is where it says it is', () async {
    // Without a pair either side of it, any value from 21 to 181 keeps the
    // cases above green and the constant means nothing.
    Future<bool> warnsAtPayload(int payload) async {
      logged.clear();
      await _transport(_FakeOps(answers: [payload + 3]))
          .configureConnected('dev');
      return logged.any((line) => line.contains('link carries only'));
    }

    expect(await warnsAtPayload(99), isTrue);
    expect(await warnsAtPayload(100), isFalse);
  });

  test('the payload never exceeds the firmware ATT ceiling', () async {
    // A platform reporting more than the firmware can take must still be cut to
    // the cap: a larger write becomes a long write, which it handles worse.
    final ops = _FakeOps(answers: [4096]);
    final transport = _transport(ops);

    await transport.configureConnected('dev');

    expect(transport.bleMtuSize, _cap);
  });
}
