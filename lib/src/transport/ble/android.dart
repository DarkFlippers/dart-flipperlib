import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'link.dart';
import 'ops.dart';
import 'platform.dart';

class AndroidBlePlatform extends UniversalBlePlatformBase {
  const AndroidBlePlatform();

  @override
  String get platformLabel => 'Android';

  // The one platform that passes anything. Fine location is not asked for:
  // BLUETOOTH_SCAN with neverForLocation covers the scan, and asking for a
  // second permission the app does not need is a second thing to be denied.
  @override
  Future<void> askPlatform() {
    return uble.UniversalBle.requestPermissions(withAndroidFineLocation: false);
  }

  /// The one plugin call [readAccess] adds, as its own method so a test can
  /// stand in for the platform without reimplementing the ordering in it —
  /// which is the thing that has to be right.
  @visibleForTesting
  Future<bool> hasScanPermission() {
    return uble.UniversalBle.hasPermissions(withAndroidFineLocation: false);
  }

  /// Reads the runtime permission, which on Android is the only thing that
  /// knows whether this app may scan.
  ///
  /// The base class reads `getBluetoothAvailabilityState()`, and on Android
  /// that is the wrong question: the plugin implements it as
  /// `bluetoothManager.adapter.state`, which maps only OFF / ON / TURNING_*
  /// and **can never return `unauthorized`**. A phone whose owner tapped Deny
  /// still has a powered-on adapter, so the base read answered `granted` for a
  /// refusal — reporting the denial as a grant, which is worse than the
  /// silence it replaced because a grant also clears the user's dismissal.
  ///
  /// `hasPermissions` is the permission-model read: the plugin returns whether
  /// the set of still-needed permissions is empty. Android signals a refusal
  /// the other way too — `requestPermissions` fails with
  /// "Permissions denied: android.permission.BLUETOOTH_SCAN" — but a throw is
  /// only available at the moment of asking, and the resume re-read has to
  /// work without asking.
  ///
  /// A granted permission still defers to the adapter state, so a user with
  /// Bluetooth switched off gets `off` and the sentence that belongs to it
  /// rather than a permission notice.
  @override
  Future<BleAccess> readAccess() async {
    final bool permitted;
    try {
      permitted = await hasScanPermission();
    } catch (e) {
      // `hasPermissions` throws when a required permission is missing from the
      // manifest - a packaging mistake, not a user decision - and when there
      // is no activity to answer from. `unknown` either way: see
      // BleAccess.unknown.
      Log.error('[FlipperClient] Android BLE permission read failed: $e');
      return BleAccess.unknown;
    }
    if (!permitted) return BleAccess.denied;
    return super.readAccess();
  }

  // No withServices filter: unlike iOS, Android resolves it from a service
  // cache that is empty in a fresh process — exactly when this lookup matters.
  // includeDevice filters by the Flipper MAC OUI / name instead.
  @override
  Future<List<BleDiscoveredDevice>> loadKnownDevices() async {
    try {
      final devices = await uble.UniversalBle.getSystemDevices();
      return devices
          .map(BleDiscoveredDevice.new)
          .where(includeDevice)
          .toList(growable: false);
    } catch (e) {
      Log.error('[FlipperClient] known BLE devices lookup failed: $e');
      return const <BleDiscoveredDevice>[];
    }
  }

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    return AndroidBleTransport.create(device);
  }
}

class AndroidBleTransport extends UniversalBleTransportBase {
  AndroidBleTransport._(BleDiscoveredDevice device)
    : super(device, UniversalBleOps());

  static Future<AndroidBleTransport> create(BleDiscoveredDevice device) async {
    final transport = AndroidBleTransport._(device);
    await transport.configure();
    return transport;
  }
}
