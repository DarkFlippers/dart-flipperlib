import 'dart:async';

import '../../model/discovered.dart';
import '../transport.dart';
import 'gatt.dart';

abstract class BlePlatform {
  Future<void> requestPermissions();

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
