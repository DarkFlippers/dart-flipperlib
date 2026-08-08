import 'dart:async';

import '../../model/device.dart';
import '../client.dart';

extension FlipperUsbApi on FlipperClient {
  Stream<FlipperDevice> get usbDevicesStream => devicesStream.asyncExpand(
    (devices) => Stream.fromIterable(devices.where((device) => device.isUsb)),
  );
}
