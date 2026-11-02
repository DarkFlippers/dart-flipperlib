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
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the canonical device id', () {
    test('lower-cases the upper-case MAC Android used to report', () {
      // The exact shape out of `known_devices_v1`, down to the Flipper OUI.
      expect(canonicalBleDeviceId('80:E1:27:AA:BB:CC'), '80:e1:27:aa:bb:cc');
    });

    test('leaves an id the plugin emitted today alone', () {
      expect(canonicalBleDeviceId('80:e1:27:aa:bb:cc'), '80:e1:27:aa:bb:cc');
    });

    test('is idempotent, so a second application is not a bug', () {
      // Relied on: the id reaching `connectBleAddress` is canonical already
      // whenever it came from a scan rather than from the store, and nothing
      // tells the two apart at that point.
      final once = canonicalBleDeviceId('80:E1:27:AA:BB:CC');
      expect(canonicalBleDeviceId(once), once);
    });

    test('canonicalises an Apple peer UUID too, not just a MAC', () {
      // iOS and macOS report an opaque per-app peer UUID instead of a MAC,
      // and the plugin treats it as an address as well. Worth its own case
      // because every report behind #444 was Android: a fix that only handled
      // colon-separated hex would pass every other case here.
      expect(
        canonicalBleDeviceId('E7A4B2C1-0F3D-4A5B-8C9D-1E2F3A4B5C6D'),
        'e7a4b2c1-0f3d-4a5b-8c9d-1e2f3a4b5c6d',
      );
    });

    test('answers with no binding initialised', () {
      // The case that keeps this off the plugin, and it is not hypothetical:
      // the first draft of `canonicalBleDeviceId` delegated to
      // `UniversalBle.canonicalDeviceId`, and every case in this file failed
      // here with "Binding has not yet been initialized". Reading
      // `UniversalBle._platform` constructs the host's backend, which sets up
      // a Pigeon callback channel - and on a Linux host also builds a
      // `BlueZClient`, whose constructor calls `DBusClient.system()` and can
      // throw over a malformed bus address. That throw would land at the top
      // of `connectBleAddress`, above the gate #443 put there, on the kind of
      // machine #443 was about.
      //
      // So: no `TestWidgetsFlutterBinding.ensureInitialized()` above, on
      // purpose. It is what makes this assertion mean something.
      expect(canonicalBleDeviceId('80:E1:27:AA:BB:CC'), '80:e1:27:aa:bb:cc');
    });
  });
}
