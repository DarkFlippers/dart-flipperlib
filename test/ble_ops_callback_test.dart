// The two closures universal_ble 3.0.0's breaking callback change rewrote.
//
// It collapsed `onConnectionChange`'s three positional arguments into one
// `BleConnectionChange` and `onValueChange`'s four into a
// `BleCharacteristicValue`. `BleOps` keeps the positional shape, so
// `UniversalBleOps` destructures and nothing above it changed - and that
// isolation is exactly why these two lines were, until this file, the only
// lines in the library that the suite could not reach: `UniversalBleOps` is
// constructed only inside `createBlePlatform`'s per-platform branches, and
// every test above `BleOps` supplies its own fake.
//
// Both parameter lists are uniformly typed - (String, String, Uint8List, int?)
// and (String, bool, String?) - so a wrong field order type-checks and
// `flutter analyze` stays clean. A swapped `deviceId`/`characteristicId` was
// measured to pass the whole suite while making `_dispatchValueChange` look
// the transport up by a characteristic UUID: a link that connects, discovers,
// subscribes and then receives nothing. The same silence as #444.
//
// Reachable because `UniversalBle.setInstance` is public and
// `UniversalBle.onValueChange =` assigns straight to the platform object's
// field, so the fake holds the closure and this file can call it. No binding
// and no channel mock.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

import 'package:flipperlib/src/transport/ble/ops.dart';

/// Holds whatever the adapter installs, and nothing else.
class _SlotPlugin extends uble.UniversalBlePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not on this path: ${invocation.memberName}');
}

void main() {
  late _SlotPlugin plugin;

  setUp(() {
    plugin = _SlotPlugin();
    uble.UniversalBle.setInstance(plugin);
  });

  test('the value callback hands over the device, then the characteristic', () {
    String? deviceId;
    String? charId;
    Uint8List? value;
    int? timestamp;
    UniversalBleOps().onValueChange = (d, c, v, t) {
      deviceId = d;
      charId = c;
      value = v;
      timestamp = t;
    };

    // Deliberately unlike each other: two UUID-shaped strings would make a
    // swap read as correct, and the first argument is what
    // `_dispatchValueChange` keys the live-transport lookup by.
    plugin.onValueChange!(
      uble.BleCharacteristicValue(
        deviceId: '80:e1:27:aa:bb:cc',
        characteristicId: '19ed82ae-ed21-4c9d-4145-228e62fe0000',
        value: Uint8List.fromList(const [0x51, 0x55]),
        timestamp: 1700,
      ),
    );

    expect(deviceId, '80:e1:27:aa:bb:cc');
    expect(charId, '19ed82ae-ed21-4c9d-4145-228e62fe0000');
    expect(value, const [0x51, 0x55]);
    // Carried, not read - `BleOps` says why it is in the signature at all.
    expect(timestamp, 1700);
  });

  test('the MTU capability is the plugin\'s answer, not ours', () {
    // It was three hard-coded `=> true` overrides on the Apple and Linux
    // transports - the same set the plugin reports, and a copy that goes
    // stale with no compile error and no failing test. The cost of this one
    // going stale was measured at two service discoveries per connect.
    //
    // The limit of the case: `defaultTargetPlatform` is android here, where
    // the plugin answers false, so a body hard-coded to `false` would pass
    // it too. What it does catch is the inversion and a hard-coded `true`.
    expect(
      UniversalBleOps().mtuNeedsDiscovery,
      uble.BleCapabilities.mtuRequiresServiceDiscovery,
    );
    expect(
      uble.BleCapabilities.mtuRequiresServiceDiscovery,
      isFalse,
      reason: 'this host is not one of the platforms that needs discovery',
    );
  });

  test('the connection callback keeps the flag and the platform sentence', () {
    String? deviceId;
    bool? connected;
    String? error;
    UniversalBleOps().onConnectionChange = (d, c, e) {
      deviceId = d;
      connected = c;
      error = e;
    };

    plugin.onConnectionChange!(
      const uble.BleConnectionChange(
        deviceId: '80:e1:27:aa:bb:cc',
        isConnected: false,
        error: 'GATT_CONN_TIMEOUT',
      ),
    );

    expect(deviceId, '80:e1:27:aa:bb:cc');
    // Inverting this is a disconnect reported as a connect, with nothing in
    // the library able to tell: `_onConnectionChange` returns early on
    // `isConnected`, so the link would simply never notice it had gone.
    expect(connected, isFalse);
    // The sentence is what `link.dart` classifies and what
    // `classifyConnectError` matches on. Dropped, every BLE failure reads as
    // UNCLASSIFIED.
    expect(error, 'GATT_CONN_TIMEOUT');
  });
}
