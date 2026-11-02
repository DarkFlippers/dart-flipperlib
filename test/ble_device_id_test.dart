// The canonical device id: what universal_ble 3.0.0 changed about identity,
// and what this library had to do about it (#444).
//
// The failure is not a connect that fails. The plugin accepts an id in any
// case and converts to the one its native side wants at its own boundary, so
// a stored upper-case MAC still connects on Android. What breaks is every
// comparison afterwards: `link.dart` drops a connection or value event whose
// deviceId is not equal to the one its transport was built with, and
// `FlipperClient._devices` is keyed by that same string. A device remembered
// by a 2.x build therefore connects and then reports nothing.
//
// This file initialises no binding, and that is load-bearing rather than an
// omission - see the last case.
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show ServicesBinding;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the canonical device id', () {
    test('lower-cases the upper-case MAC Android used to report', () {
      // The exact shape out of `known_devices_v1`, down to the Flipper OUI.
      expect(canonicalBleDeviceId('80:E1:27:AA:BB:CC'), '80:e1:27:aa:bb:cc');
    });

    test('leaves an id the plugin emitted today alone', () {
      // With the case above, this also settles idempotency, which the id
      // reaching `connectBleAddress` relies on - it is already canonical
      // whenever it came from a scan rather than from a store, and nothing
      // tells the two apart at that point. A case of its own could not fail
      // without one of these two failing first.
      expect(canonicalBleDeviceId('80:e1:27:aa:bb:cc'), '80:e1:27:aa:bb:cc');
    });

    test('canonicalises an Apple peer UUID too, not just a MAC', () {
      // iOS and macOS report an opaque per-app peer UUID instead of a MAC,
      // and the plugin treats it as an address as well. Not belt and braces:
      // 2.x emitted those ids from CoreBluetooth's `uuidString`, which is
      // upper-case, so a remembered iOS device breaks exactly as an Android
      // one does - #444's own "iOS/macOS are unaffected (opaque peer UUIDs)"
      // is wrong about that. It is also the only case here that a fix
      // handling just colon-separated hex would fail.
      expect(
        canonicalBleDeviceId('E7A4B2C1-0F3D-4A5B-8C9D-1E2F3A4B5C6D'),
        'e7a4b2c1-0f3d-4a5b-8c9d-1e2f3a4b5c6d',
      );
    });

    test('answers with no binding initialised', () {
      // The case that keeps this off the plugin, and it is not hypothetical:
      // the first draft of `canonicalBleDeviceId` delegated to
      // `UniversalBle.canonicalDeviceId`, and every case in this file failed
      // with "Binding has not yet been initialized". Reading
      // `UniversalBle._platform` constructs the host's backend: the Pigeon
      // channel, whose constructor needs a binding, or on Linux a
      // `BlueZClient`, whose constructor calls `DBusClient.system()` and can
      // throw over a malformed bus address. The second one would land at the
      // top of `connectBleAddress`, above the gate #443 put there, on the
      // kind of machine #443 was about.
      //
      // The precondition is the subject, so it is asserted rather than left
      // to the file's layout. Without this line the case is a copy of the
      // first one, and one `TestWidgetsFlutterBinding.ensureInitialized()`
      // added here for an unrelated reason would take the guard out with
      // nothing going red.
      expect(
        () => ServicesBinding.instance,
        throwsA(isA<FlutterError>()),
        reason:
            'something in this file initialised a binding, so a body that '
            'went back to asking the plugin would pass every case here',
      );
      expect(canonicalBleDeviceId('80:E1:27:AA:BB:CC'), '80:e1:27:aa:bb:cc');
    });
  });
}
