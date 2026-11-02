// Connecting to an address the caller stored, which is the one BLE id in this
// library that does not come from the plugin (#444).
//
// universal_ble 3.0.0 emits lower-case ids on every native platform; 2.x let
// each platform report its own case, and Android upper-cased MACs while Apple
// reported its peer UUID as the upper-case `uuidString`. The plugin still
// accepts either as input, so the connect succeeds and everything that
// compares afterwards fails: the device cache, and then the transport's
// callback dispatch, which is keyed by the id the transport was built with.
// A link that reports connected and carries nothing.
//
// These drive the real `connectBleAddress` with the plugin replaced through
// `UniversalBle.setInstance` - which is public, and is what makes this
// behavioural rather than a source assertion. No binding and no channel mock:
// the only plugin call on this path is the availability read, and the fake
// answers it.
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

/// The plugin, with the one read this path makes answered and everything else
/// a failure rather than a default - a call that should not happen here should
/// say so by name.
class _PoweredOnPlugin extends uble.UniversalBlePlatform {
  @override
  Future<uble.AvailabilityState> getBluetoothAvailabilityState() async =>
      uble.AvailabilityState.poweredOn;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not on this path: ${invocation.memberName}');
}

/// The real client with the link stood in for: `connect` is public and
/// overridable, and `reboot_refusal_test.dart` and
/// `storage_write_restart_test.dart` already take it this way.
class _Client extends FlipperClient {
  final List<FlipperDevice> handed = [];

  @override
  Future<FlipperDevice> connect(FlipperDevice device) async {
    handed.add(device);
    return device;
  }
}

void main() {
  setUp(() => uble.UniversalBle.setInstance(_PoweredOnPlugin()));

  // The spelling a 2.x build of the host wrote into its store, and the one
  // the plugin reports for the same Flipper today.
  const stored = '80:E1:27:AA:BB:CC';
  const reported = '80:e1:27:aa:bb:cc';

  test('a stored upper-case MAC becomes the id everything else uses', () async {
    final client = _Client();
    addTearDown(client.dispose);

    final device = await client.connectBleAddress(stored, name: 'Flipper Zoe');

    // One object, so one assertion: `connect` is handed the device this method
    // built, returns it, and `_rememberDevice` stores that same instance. The
    // id reaching `connect` is the one that matters - it is what the transport
    // registers its callback dispatch under - and the cache key is the second
    // case's subject.
    expect(client.handed.single.id, reported);
    expect(device.id, same(client.handed.single.id));
  });

  test('and the same stored spelling finds the live session again', () async {
    // What a remembered device actually does: the store hands out the same
    // string every time, so the second call must swap to the session the
    // first one opened instead of dialling again. That is what the device
    // cache is for, and an uncanonical key misses it silently - every
    // reconnect becomes a cold connect.
    final client = _Client();
    addTearDown(client.dispose);

    await client.connectBleAddress(stored);
    await client.connectBleAddress(stored);
    await client.connectBleAddress(reported);

    expect(
      identical(client.handed[0], client.handed[1]),
      isTrue,
      reason: 'the stored spelling did not find the device it just opened',
    );
    expect(
      identical(client.handed[0], client.handed[2]),
      isTrue,
      reason: 'the spelling the plugin reports found a different device',
    );
    expect(client.devices, hasLength(1));
  });
}
