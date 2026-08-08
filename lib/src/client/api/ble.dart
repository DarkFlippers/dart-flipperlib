import 'dart:async';

import '../../model/device.dart';
import '../client.dart';

extension FlipperBleApi on FlipperClient {
  Stream<FlipperDevice> get bleDevicesStream => devicesStream.asyncExpand(
    (devices) => Stream.fromIterable(devices.where((device) => device.isBle)),
  );
}
