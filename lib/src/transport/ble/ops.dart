import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import 'gatt.dart';

abstract class BleOps {
  /// Whether [requestMtu] can only answer once the services are known.
  ///
  /// A capability rather than an operation, and here rather than on the
  /// transport because it is a fact about the plugin, and this is the one file
  /// that is allowed to know those. [UniversalBleOps] reads the plugin's own
  /// predicate; a fake answers for the platform it stands in for.
  bool get mtuNeedsDiscovery;

  set onConnectionChange(
    void Function(String deviceId, bool isConnected, String? error)? cb,
  );

  /// The fourth argument is universal_ble's `timestamp`, not an MTU: its
  /// Darwin plugin fills it with `Date().timeIntervalSince1970 * 1000`. It is
  /// carried through unused - named here only so the next person looking for a
  /// settled-MTU signal does not think they have found one.
  set onValueChange(
    void Function(
      String deviceId,
      String charId,
      Uint8List value,
      int? timestamp,
    )?
    cb,
  );

  Future<void> connect(String deviceId);
  Future<int> requestMtu(String deviceId, int mtu);
  Future<List<BleService>> discoverServices(String deviceId);
  Future<void> subscribeNotifications(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  });
  Future<void> subscribeIndications(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  });
  Future<Uint8List> read(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  });
  Future<void> write(
    String deviceId,
    String svcId,
    String charId,
    Uint8List data, {
    bool withoutResponse = false,
  });
  Future<void> disconnect(String deviceId);
  Future<BleConnState?> getConnectionState(String deviceId);
}

/// [BleOps] over universal_ble itself: the only file that touches the
/// plugin's *per-link* callbacks. (`onScanResult` is the exception, set and
/// cleared inside `_scanBleLocked` in `client.dart`; 3.0.0 left its signature
/// alone.)
///
/// That is what made universal_ble 3.0.0's two breaking callback changes a
/// two-line edit. It collapsed `onConnectionChange`'s three positional
/// arguments into one `BleConnectionChange` and `onValueChange`'s four into a
/// `BleCharacteristicValue`; [BleOps] keeps the positional shape, so the
/// destructuring stops here and `link.dart`, the fakes in `ble_fixtures.dart`
/// and every test above them were untouched by the bump.
class UniversalBleOps implements BleOps {
  /// The plugin's own answer, not ours.
  ///
  /// `BleCapabilities.mtuRequiresServiceDiscovery` is iOS, macOS and Linux in
  /// universal_ble 3.2.0, which is exactly what the three platform transports
  /// used to declare for themselves - and a copied fact goes stale without a
  /// compile error or a failing test. The cost of this one going stale was
  /// measured: it is two service discoveries per connect, which is what #444
  /// fixed. Reading it is free, unlike `canonicalDeviceId` - it looks at
  /// `kIsWeb` and `defaultTargetPlatform` and touches no backend.
  @override
  bool get mtuNeedsDiscovery =>
      uble.BleCapabilities.mtuRequiresServiceDiscovery;

  @override
  set onConnectionChange(void Function(String, bool, String?)? cb) {
    uble.UniversalBle.onConnectionChange = cb == null
        ? null
        // `error` is the platform's own sentence, and it already was in
        // 2.x: `OnConnectionChange` declared `String? error` as far back as
        // 1.2.0, so the `err?.toString()` this replaces was a no-op. What
        // 3.0.0 changed is only that it arrives on an object. The two fields
        // that came with it, `errorCode` and `nativeErrorCode`, are dropped
        // here - `classifyConnectError` still reads the sentence - which is
        // #436's business and not a bump's.
        : (change) => cb(change.deviceId, change.isConnected, change.error);
  }

  @override
  set onValueChange(void Function(String, String, Uint8List, int?)? cb) {
    uble.UniversalBle.onValueChange = cb == null
        ? null
        : (value) => cb(
            value.deviceId,
            value.characteristicId,
            value.value,
            value.timestamp,
          );
  }

  @override
  Future<void> connect(String deviceId) => uble.UniversalBle.connect(deviceId);

  @override
  Future<int> requestMtu(String deviceId, int mtu) =>
      uble.UniversalBle.requestMtu(deviceId, mtu);

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    final svcs = await uble.UniversalBle.discoverServices(deviceId);
    return svcs.map((s) {
      final chars = s.characteristics.map((c) {
        return BleChar(
          c.uuid,
          canWrite: c.properties.contains(uble.CharacteristicProperty.write),
          canWriteNoRsp: c.properties.contains(
            uble.CharacteristicProperty.writeWithoutResponse,
          ),
          canNotify: c.properties.contains(uble.CharacteristicProperty.notify),
          canIndicate: c.properties.contains(
            uble.CharacteristicProperty.indicate,
          ),
        );
      }).toList();
      return BleService(s.uuid, chars);
    }).toList();
  }

  @override
  Future<void> subscribeNotifications(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  }) => uble.UniversalBle.subscribeNotifications(
    deviceId,
    svcId,
    charId,
    timeout: timeout,
  );

  @override
  Future<void> subscribeIndications(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  }) => uble.UniversalBle.subscribeIndications(
    deviceId,
    svcId,
    charId,
    timeout: timeout,
  );

  @override
  Future<Uint8List> read(
    String deviceId,
    String svcId,
    String charId, {
    Duration? timeout,
  }) => uble.UniversalBle.read(deviceId, svcId, charId, timeout: timeout);

  @override
  Future<void> write(
    String deviceId,
    String svcId,
    String charId,
    Uint8List data, {
    bool withoutResponse = false,
  }) async {
    // Per-chunk hot path: skip the stopwatch and message building in release.
    if (!Log.debugOn) {
      return uble.UniversalBle.write(
        deviceId,
        svcId,
        charId,
        data,
        withoutResponse: withoutResponse,
      );
    }
    final stopwatch = Stopwatch()..start();
    final mode = withoutResponse ? 'withoutResponse' : 'withResponse';
    try {
      await uble.UniversalBle.write(
        deviceId,
        svcId,
        charId,
        data,
        withoutResponse: withoutResponse,
      );
      Log.debug(
        '[UniversalBle] write done len=${data.length} mode=$mode '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error) {
      Log.debug(
        '[UniversalBle] write failed len=${data.length} mode=$mode '
        'elapsedMs=${stopwatch.elapsedMilliseconds} error=$error',
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect(String deviceId) =>
      uble.UniversalBle.disconnect(deviceId);

  @override
  Future<BleConnState?> getConnectionState(String deviceId) async {
    try {
      final s = await uble.UniversalBle.getConnectionState(deviceId);
      return switch (s) {
        uble.BleConnectionState.connected => BleConnState.connected,
        uble.BleConnectionState.connecting => BleConnState.connecting,
        _ => BleConnState.disconnected,
      };
    } catch (_) {
      return null;
    }
  }
}
