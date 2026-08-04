import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart' as uble;

import '../../common/log.dart';
import 'gatt.dart';

abstract class BleOps {
  set onConnectionChange(
    void Function(String deviceId, bool isConnected, String? error)? cb,
  );

  set onValueChange(
    void Function(String deviceId, String charId, Uint8List value, int? mtu)?
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

class UniversalBleOps implements BleOps {
  @override
  set onConnectionChange(void Function(String, bool, String?)? cb) {
    uble.UniversalBle.onConnectionChange = cb == null
        ? null
        : (did, conn, err) => cb(did, conn, err?.toString());
  }

  @override
  set onValueChange(void Function(String, String, Uint8List, int?)? cb) {
    uble.UniversalBle.onValueChange = cb;
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
