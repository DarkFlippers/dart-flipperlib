import 'package:protobuf/protobuf.dart' as $pb;

import '../proto/generated/flipper.pb.dart';
import 'discovered.dart';
import 'enums.dart';

class FlipperDevice {
  final String id;
  final String name;
  final FlipperLink link;
  final DiscoveredDevice source;
  final int? vendorId;
  final int? productId;
  final String? serialNumber;
  final int? rssi;

  const FlipperDevice({
    required this.id,
    required this.name,
    required this.link,
    required this.source,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.rssi,
  });

  bool get isUsb => link == FlipperLink.usb;

  bool get isBle => link == FlipperLink.ble;
}

class FlipperRpcBatch<T extends $pb.GeneratedMessage> {
  final int commandId;
  final Main request;
  final List<Main> frames;
  final List<T> items;

  const FlipperRpcBatch({
    required this.commandId,
    required this.request,
    required this.frames,
    required this.items,
  });

  T get single => items.single;

  T? get firstOrNull => items.isEmpty ? null : items.first;
}

/// Snapshot of one held link: the device, its lifecycle state and whether it
/// is the session all API calls and public streams currently route to.
class FlipperSessionInfo {
  final FlipperDevice device;
  final bool connected;
  final bool connecting;
  final bool active;

  const FlipperSessionInfo({
    required this.device,
    required this.connected,
    required this.connecting,
    required this.active,
  });
}

class FlipperConnectionState {
  final FlipperMode mode;
  final FlipperDevice? device;
  final bool connected;

  /// Why the session ended (only meaningful when [connected] is false after a
  /// previously established connection). Carries the transport fault — e.g.
  /// "Flipper closed the RPC session" — so UIs can report the problem calmly
  /// instead of guessing from a bare disconnect.
  final Object? closeReason;

  /// True on the disconnected event that precedes an automatic reconnect
  /// attempt: the link dropped unexpectedly and the client is already
  /// re-establishing it. UIs can show a soft "reconnecting" indicator instead
  /// of the full disconnect flow.
  final bool reconnecting;

  /// True while a connection attempt is in flight (the radio is busy
  /// establishing the link) and no session is committed yet. [device] is the
  /// target being connected to. UIs can surface this as a "connecting…" row
  /// with a cancel action — a stuck attempt is the only state that holds the
  /// radio and blocks scanning, so being able to abort it from here matters.
  final bool connecting;

  const FlipperConnectionState({
    required this.mode,
    required this.device,
    required this.connected,
    this.closeReason,
    this.reconnecting = false,
    this.connecting = false,
  });
}
