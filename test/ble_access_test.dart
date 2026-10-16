// What a Bluetooth ask answers, and what the answer must never say.
//
// `requestPermissions` returned `Future<void>` until #351, so a user who
// refused the Android scan permission was shown "No devices found." — the
// device list reads identically for a denial and an empty room, and the
// denial was the only thing that could have told them apart.
//
// The fake below stubs `availabilityState()` and nothing else, so the body
// under test is the real `requestPermissions` and the real `accessFor`. A
// fake that carried its own copy of the mapping would have passed on its own
// copy being right, which CLAUDE.md names as this repository's most
// productive way of writing a test that proves nothing.
//
// Three of the five answers are deliberately *not* denials, and that is most of
// what is checked here: reporting an adapter that is merely switched off, a
// machine with no radio, or a read that failed as "you refused this" sends the
// user to a settings screen with nothing in it to change.
import 'package:flipperlib/src/model/discovered.dart';
import 'package:flipperlib/src/transport/ble/platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart' as uble;

/// Drives the real base class with the plugin replaced.
///
/// [availabilityState] is the only override, which is exactly the platform
/// boundary: everything the change is about — the ask, the catch that falls
/// through to the read, and the mapping — is the base's own code running.
class _FakePlatform extends UniversalBlePlatformBase {
  _FakePlatform(this._state, {this.askThrows = false, this.readThrows = false});

  final uble.AvailabilityState _state;
  final bool askThrows;
  final bool readThrows;

  int asks = 0;
  int reads = 0;

  @override
  String get platformLabel => 'Fake';

  @override
  Future<void> askPlatform() async {
    asks++;
    if (askThrows) throw StateError('another request is already running');
  }

  @override
  Future<uble.AvailabilityState> availabilityState() async {
    reads++;
    if (readThrows) throw StateError('no adapter');
    return _state;
  }

  @override
  Future<Never> openTransport(BleDiscoveredDevice device) {
    throw UnsupportedError('not reached by these tests');
  }
}

void main() {
  group('a denial reaches the caller', () {
    test('an unauthorized adapter answers denied', () async {
      final platform = _FakePlatform(uble.AvailabilityState.unauthorized);
      expect(await platform.requestPermissions(), BleAccess.denied);
    });

    test('a powered-on adapter answers granted', () async {
      final platform = _FakePlatform(uble.AvailabilityState.poweredOn);
      expect(await platform.requestPermissions(), BleAccess.granted);
    });
  });

  test('the base read is only for platforms that report unauthorized', () {
    // Pinned as a fact about the mapping rather than left to prose: the base
    // class's whole claim to correctness is that its platform answers
    // `unauthorized` for a refusal. Android does not, which is why it
    // overrides `readAccess`.
    expect(
      UniversalBlePlatformBase.accessFor(uble.AvailabilityState.unauthorized),
      BleAccess.denied,
    );
  });

  group('what must not read as a denial', () {
    // The user cannot grant their way out of any of these, and sending them
    // to system settings to try is the wrong-cause failure #351 is about.
    // `FlipperConnectErrorKind.bluetoothUnavailable` already owns the
    // switched-off case and has a sentence for it.
    test('a switched-off adapter is off, not denied', () async {
      final platform = _FakePlatform(uble.AvailabilityState.poweredOff);
      expect(await platform.requestPermissions(), BleAccess.off);
    });

    test('a machine with no radio is unsupported, not denied', () async {
      final platform = _FakePlatform(uble.AvailabilityState.unsupported);
      expect(await platform.requestPermissions(), BleAccess.unsupported);
    });

    test('an adapter mid-reset is unknown, not denied', () async {
      final platform = _FakePlatform(uble.AvailabilityState.resetting);
      expect(await platform.requestPermissions(), BleAccess.unknown);
    });

    test('a failed availability read is unknown, not denied', () async {
      final platform = _FakePlatform(
        uble.AvailabilityState.poweredOn,
        readThrows: true,
      );
      expect(await platform.requestPermissions(), BleAccess.unknown);
    });
  });

  test('an ask that throws defers to the read, it does not answer', () async {
    // The plugin refuses a request while another one is running, and on Apple
    // platforms the ask is a no-op whose result only ever arrives through the
    // authorisation state. Returning early on the throw would have reported a
    // granted install as unknown for the rest of the process.
    //
    // This says nothing about what the read *should* answer - that is the
    // platform's business, and on Android the base class's read is wrong for
    // it. See `ble_access_android_test.dart`. An earlier version of this test
    // asserted `granted` here and called it "still reports the standing
    // grant", which pinned the Android bug as correct behaviour.
    final platform = _FakePlatform(
      uble.AvailabilityState.poweredOn,
      askThrows: true,
    );
    expect(await platform.requestPermissions(), BleAccess.granted);
    expect(platform.asks, 1, reason: 'the ask still happened');
    expect(platform.reads, 1, reason: 'and the read still followed it');
  });

  test('readAccess asks for nothing', () async {
    // The re-read on resume must not raise a second prompt: on Android
    // MANAGE-style screens and on iOS alike, a user who already answered
    // being asked again every time they return to the app is its own bug.
    final platform = _FakePlatform(uble.AvailabilityState.unauthorized);
    expect(await platform.readAccess(), BleAccess.denied);
    expect(platform.asks, 0);
  });

  group('accessFor covers every state the plugin can report', () {
    // Named one per row rather than looped, so a failure names the state.
    // The mapping is a `switch` expression, so a new plugin state breaks the
    // build rather than landing in a silent default — this group is the
    // record of what the six mean today.
    const expected = <uble.AvailabilityState, BleAccess>{
      uble.AvailabilityState.poweredOn: BleAccess.granted,
      uble.AvailabilityState.unauthorized: BleAccess.denied,
      uble.AvailabilityState.poweredOff: BleAccess.off,
      uble.AvailabilityState.unsupported: BleAccess.unsupported,
      uble.AvailabilityState.resetting: BleAccess.unknown,
      uble.AvailabilityState.unknown: BleAccess.unknown,
    };

    test('the table covers the enum', () {
      expect(expected.keys, containsAll(uble.AvailabilityState.values));
    });

    for (final entry in expected.entries) {
      test('${entry.key.name} maps to ${entry.value.name}', () {
        expect(UniversalBlePlatformBase.accessFor(entry.key), entry.value);
      });
    }
  });
}
