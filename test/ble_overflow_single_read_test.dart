// That the overflow characteristic is read exactly once per session, on both
// paths through the encrypted setup.
//
// This is the invariant `_openEncryptedSetup`'s own header states, and the
// reason it is stated: reading overflow returns the stored credit rather than a
// fresh grant, so a second read desyncs the firmware's flow-control counter,
// trips ERROR_DECODE and makes the firmware reset its BLE stack - seen as a
// PEER-INITIATED drop minutes into a session, which points at nothing.
//
// It needs a test now because making `rpcStatus` optional made a dead branch
// live. Step 1 pairs with a side-effect-free encrypted read, which has to come
// first - on Apple a CCCD write on an unencrypted link silently fails to
// activate and TX then stalls at budget=0 - and on a device with no rpcStatus
// the only readable characteristic left is overflow. So that read *is* the
// session's one read, and step 4 reuses its value.
//
// Nothing else in the suite reaches `_openEncryptedSetup`:
// `ble_services_missing_test.dart` and `ble_mtu_settle_test.dart` both stop at
// `configureConnected`, whose fake answers two calls and throws on the rest.
// A review found the two-read path by reading, not by running, which is why
// the count is asserted here rather than left to the comment.
import 'dart:typed_data';

import 'package:flipperlib/src/transport/ble/gatt.dart';
import 'package:flipperlib/src/transport/ble/link.dart';
import 'package:flipperlib/src/transport/ble/ops.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ble_fixtures.dart';

/// Answers the whole encrypted setup and counts every read by characteristic.
class _CountingOps implements BleOps {
  _CountingOps(this.services);

  final List<BleService> services;

  /// Reads per characteristic uuid, which is the whole point of this fake.
  final reads = <String, int>{};

  final subscribed = <String>[];

  @override
  set onConnectionChange(void Function(String, bool, String?)? cb) {}

  @override
  set onValueChange(void Function(String, String, Uint8List, int?)? cb) {}

  @override
  Future<int> requestMtu(String deviceId, int mtu) async => 185;

  @override
  Future<List<BleService>> discoverServices(String deviceId) async => services;

  @override
  Future<Uint8List> read(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  }) async {
    reads.update(charId, (n) => n + 1, ifAbsent: () => 1);
    // A non-zero credit, so the `_budget <= 0` seeding at the end of the setup
    // is not what the cases below are measuring.
    return Uint8List.fromList([0x00, 0x04]);
  }

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  }) async => subscribed.add(charId);

  @override
  Future<void> subscribeIndications(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  }) async => subscribed.add(charId);

  /// Only so `close()` in the teardown has something to call - without it
  /// `doClose` reaches [noSuchMethod] and the transport logs an error per
  /// test.
  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    '${invocation.memberName} is not part of this path',
  );
}

Future<_CountingOps> _runSetup(List<BleChar> chars) async {
  final ops = _CountingOps([BleService(flipperBleServiceUuid, chars)]);
  final transport = TestBleTransport(testFlipperDevice(), ops);
  // `open()` starts a sender that parks on a signal nothing completes, and
  // sets the static `_connectionOwner`. Neither is reset by anything in this
  // package - there is no `flutter_test_config.dart` here - so without this a
  // later BLE test takes the `!identical(_connectionOwner, this)` arm and
  // passes or fails on a stale transport rather than on what it names.
  addTearDown(transport.close);
  await transport.configureConnected('dev');
  await transport.open();
  return ops;
}

const _overflow = UniversalBleTransportBase.overflowCharUuid;
const _rpcStatus = UniversalBleTransportBase.rpcStatusCharUuid;

void main() {
  group('a device with rpcStatus', () {
    test('reads overflow exactly once', () async {
      final ops = await _runSetup(allFlipperChars());

      expect(ops.reads[_overflow], 1);
    });

    test('and pairs with the rpcStatus read, not the overflow one', () async {
      // The order the header insists on: the pairing read is the one with no
      // side effect, and it happens before any subscribe.
      final ops = await _runSetup(allFlipperChars());

      // Not a count. rpcStatus is read twice on this path - once to pair in
      // step 1 and once by `_subscribeRpcStatus` for the initial session
      // state - and that is exactly the asymmetry this file is about: reading
      // rpcStatus again is free, reading overflow again resets the firmware's
      // BLE stack. Pinning a number here would be pinning the wrong property.
      expect(ops.reads[_rpcStatus], greaterThanOrEqualTo(1));
      expect(ops.reads[_overflow], 1);
      expect(ops.subscribed, contains(_overflow));
    });
  });

  group('a device without rpcStatus', () {
    List<BleChar> chars() =>
        allFlipperChars()..removeWhere((c) => c.uuid == _rpcStatus);

    test('reads overflow once and rpcStatus never', () async {
      // The case the fix exists for: two overflow reads here is a firmware
      // stack reset minutes into the session. The `isNull` half is what stops
      // it passing by the setup having skipped the pairing read altogether -
      // which would be the Apple stall instead of the desync.
      final ops = await _runSetup(chars());

      expect(ops.reads[_overflow], 1);
      expect(ops.reads[_rpcStatus], isNull);
    });

    test('and still subscribes to overflow and rx', () async {
      // The subscribes are what the pairing read exists to make work, so a
      // setup that paired and then stopped would pass the counts above.
      final ops = await _runSetup(chars());

      expect(ops.subscribed, contains(_overflow));
      expect(ops.subscribed, contains(flipperBleRxUuid));
    });
  });
}
