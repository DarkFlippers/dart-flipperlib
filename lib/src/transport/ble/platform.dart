import 'dart:async';

import 'package:flutter/foundation.dart' show protected;
import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'gatt.dart';

/// Whether this process may use Bluetooth, after the platform has been asked.
///
/// One enum for every platform rather than a per-platform answer, because the
/// caller's question is the same everywhere and only one value of it is
/// actionable: [denied] is the one a user can undo, and it is the one
/// `requestPermissions` used to throw away.
///
/// [off] and [unsupported] are not denials and must not be reported as one.
/// The adapter being switched off is already the subject of
/// `FlipperConnectErrorKind.bluetoothUnavailable`, and a machine with no radio
/// has nothing for the user to grant.
enum BleAccess {
  /// Usable now. Nothing to tell the user.
  granted,

  /// The user refused. Reversible only in system settings.
  ///
  /// How this is established differs by platform, and the difference is not
  /// cosmetic: Apple reports it as an authorisation state, while Android has a
  /// runtime permission the adapter state cannot see — so the Android
  /// implementation reads the permission model directly. Getting that wrong
  /// reported a refusal as a grant, which is the one answer worse than
  /// silence.
  denied,

  /// Permitted, but the adapter is switched off.
  off,

  /// No Bluetooth on this machine.
  unsupported,

  /// The platform would not say. Treated as usable: scanning is what finds
  /// out, and a notice raised on a guess is the failure mode #351 is about.
  unknown,
}

abstract class BlePlatform {
  /// Asks for whatever this platform needs in order to scan, and answers what
  /// it got.
  ///
  /// Returns a value rather than `void`: a denial reaching nobody is why a
  /// first-run Android user was shown "No devices found." and told to blame
  /// their hardware (#351).
  ///
  /// The answer must come from the platform's own permission model, not from
  /// whatever is cheapest to read. See `AndroidBlePlatform.readAccess`.
  Future<BleAccess> requestPermissions();

  /// Re-reads [requestPermissions]'s answer without asking again.
  ///
  /// Every one of these is reversible only in system settings, so the app has
  /// to notice the user came back having granted it. Asking again to find out
  /// would re-raise a prompt the user already answered.
  Future<BleAccess> readAccess();

  /// The plugin's own answer about the radio, unmapped.
  ///
  /// On the interface rather than private to the base class because it is the
  /// only place this process calls `getBluetoothAvailabilityState`. Two
  /// callers in `FlipperClient` used to call it directly, and on Linux that
  /// call is how the app died: the plugin's bluez backend initialises on first
  /// use, and when that fails it completes its own initialisation completer
  /// with an error nothing is listening to yet. An orphaned rejection is not
  /// catchable at a call site — it goes to the root zone, which is
  /// `PlatformDispatcher.onError`, which is a fatal crash report
  /// (QUNLEASHED-Q, QUNLEASHED-C). So the fix has to be to not make the call,
  /// and that is only possible if there is one place making it.
  ///
  /// The narrow claim is the one that matters and the one to keep true: this
  /// is not the only `UniversalBle` call in the process — there are two dozen
  /// — and it is not even the only adapter read. `FlipperClient` also listens
  /// to `UniversalBle.availabilityStream`, and that subscription **does**
  /// reach `_ensureInitialized`: the backend's controller is a
  /// `UniversalBleStreamController` whose `onListen` awaits
  /// `getBluetoothAvailabilityState`, and its `catch (_) {}` swallows the
  /// rethrow but not the orphaned completer. So it is safe only by position —
  /// `_awaitBleAvailable` returns on `poweredOn` and on `unsupported` before
  /// it ever subscribes. That ordering is the load-bearing fact, and
  /// `plugin_reach_guard_test.dart` is where it is held, because a
  /// prohibition documented on the thing you *are* allowed to call is the
  /// weakest possible placement.
  ///
  /// Callers want [readAccess]. This is for the two of them that need the
  /// platform's word before deciding whether to scan at all.
  Future<uble.AvailabilityState> availabilityState();

  // Already-bonded / system-known devices: an instant lookup (not a scan),
  // queried once at the start of every scan to surface devices that are
  // connected but not currently advertising.
  Future<List<BleDiscoveredDevice>> loadKnownDevices();

  bool includeDevice(BleDiscoveredDevice device);

  Future<Transport> openTransport(BleDiscoveredDevice device);
}

abstract class UniversalBlePlatformBase implements BlePlatform {
  const UniversalBlePlatformBase();

  // Flipper Zero's BLE MAC OUI. Present on platforms that expose the MAC
  // (Android / Linux / Windows); iOS / macOS expose an opaque UUID instead and
  // fall back to the advertised name.
  static const List<String> _flipperMacPrefixes = ['80E127', '80E126'];

  /// Names this platform in the one log line an ask can produce.
  String get platformLabel;

  /// The ask itself, which is the only part that differs per platform —
  /// Android passes `withAndroidFineLocation`, nobody else passes anything.
  ///
  /// Overriding this rather than [requestPermissions] is what keeps the
  /// availability read below in one place. Five copies of it was how the
  /// grant came to be discarded five times over.
  Future<void> askPlatform() => uble.UniversalBle.requestPermissions();

  @override
  Future<BleAccess> requestPermissions() async {
    try {
      await askPlatform();
    } catch (e) {
      Log.error(
        '[FlipperClient] $platformLabel BLE permission request failed: $e',
      );
      // Falls through to [readAccess] rather than returning, and that is only
      // sound because every platform's read is authoritative about its own
      // permission model — see `AndroidBlePlatform.readAccess`, which had to
      // be written for exactly this reason.
      //
      // The ask throwing is not itself an answer. The plugin refuses a request
      // while another is running, and on Apple platforms the ask is a no-op
      // whose result only ever arrives through the authorisation state. On
      // Android a refusal *is* delivered as a throw, but the read sees the
      // same refusal, so the fall-through reports it correctly without this
      // method having to know which case it was.
    }
    return readAccess();
  }

  /// Policy, not the plugin call: this body makes none, and
  /// [askPluginForAvailability] below is the line that does.
  ///
  /// Two methods of one signature is a trap, so the rule is — override **this**
  /// to change the *answer* (`LinuxBlePlatform` does), and stand in for
  /// [askPluginForAvailability] to change *where the answer comes from* (its
  /// test does). `ble_access_test.dart` and `ble_access_android_test.dart`
  /// stub the plugin method for the same reason.
  @override
  Future<uble.AvailabilityState> availabilityState() {
    return askPluginForAvailability();
  }

  /// The line that touches universal_ble, split out from [availabilityState]
  /// because a platform that overrides the latter has to be able to delegate
  /// to the plugin *and* be tested without one. `super.availabilityState()` is
  /// statically bound, so there is no dispatch point for a test subclass to
  /// intercept; this has one. `LinuxBlePlatform` is the override that still
  /// delegates, and `ble_access_linux_test.dart` is the test.
  @protected
  Future<uble.AvailabilityState> askPluginForAvailability() {
    return uble.UniversalBle.getBluetoothAvailabilityState();
  }

  /// Reads the standing grant from the authorisation state.
  ///
  /// Correct on Apple platforms and Windows, where the plugin answers this
  /// from `CBManager.authorization` (or the OS radio state) and so reports
  /// `unauthorized` for a refusal. **Not** correct on Android, which has a
  /// runtime permission model the adapter state knows nothing about;
  /// `AndroidBlePlatform` overrides this.
  ///
  /// On iOS this answers without instantiating a `CBCentralManager` only
  /// because the app declares the `bluetooth-central` background mode. Drop
  /// that from `Info.plist` and this both starts prompting at launch and stops
  /// being a read.
  @override
  Future<BleAccess> readAccess() async {
    try {
      return accessFor(await availabilityState());
    } catch (e) {
      // `unknown`, not `denied`: see BleAccess.unknown. A read that failed is
      // not a user who said no, and telling them it was costs them the one
      // sentence that would have helped.
      Log.error(
        '[FlipperClient] $platformLabel BLE availability read failed: $e',
      );
      return BleAccess.unknown;
    }
  }

  /// Maps the plugin's availability state onto the answer the app acts on.
  ///
  /// Exhaustive by construction: a `switch` expression over the plugin's enum
  /// fails to compile if universal_ble adds a state, which is the point. The
  /// alternative — a default arm — would quietly file a new state under
  /// whichever answer happened to be the fallback.
  static BleAccess accessFor(uble.AvailabilityState state) {
    return switch (state) {
      uble.AvailabilityState.poweredOn => BleAccess.granted,
      uble.AvailabilityState.unauthorized => BleAccess.denied,
      uble.AvailabilityState.poweredOff => BleAccess.off,
      uble.AvailabilityState.unsupported => BleAccess.unsupported,
      // `resetting` is the adapter cycling, which resolves on its own.
      uble.AvailabilityState.resetting => BleAccess.unknown,
      uble.AvailabilityState.unknown => BleAccess.unknown,
    };
  }

  @override
  Future<List<BleDiscoveredDevice>> loadKnownDevices() async {
    return const <BleDiscoveredDevice>[];
  }

  @override
  bool includeDevice(BleDiscoveredDevice device) {
    if (_advertisesFlipperService(device)) return true;

    final id = device.id.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    if (_flipperMacPrefixes.any(id.startsWith)) return true;

    final name = device.name.toLowerCase();
    return name.contains('flipper') || name.contains('flip_');
  }

  bool _advertisesFlipperService(BleDiscoveredDevice device) {
    bool hasFlipper(Iterable<String> uuids) =>
        uuids.map((uuid) => uuid.toLowerCase()).contains(flipperBleServiceUuid);
    return hasFlipper(device.device.services) ||
        hasFlipper(device.device.serviceData.keys);
  }
}

// Firmware contract (serial_service.c, bt.c, rpc.c in unleashed-firmware):
// - Flow control: the firmware grants RPC_BUFFER_SIZE (1024) bytes of credit,
//   counts every byte written to RX against it, and notifies a fresh full
//   credit only after the counter hit zero AND its RPC thread drained the
//   buffer. Sending past the credit drops bytes (1 s feed timeout) and breaks
//   the protobuf varint framing permanently.
// - rpcStatus is 1 only while the firmware RPC session is open. The session
//   opens on the GAP connected event (after pairing), which is later than our
//   GATT subscriptions; bytes written earlier are silently discarded. After a
//   decode error the firmware sends ERROR_DECODE and restarts its whole BLE
//   stack.
// - Writing 0 to rpcStatus restarts the firmware BLE stack. Never write it.
