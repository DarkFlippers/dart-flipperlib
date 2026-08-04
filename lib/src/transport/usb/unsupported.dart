import '../../model/device.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'platform.dart';

class UnsupportedUsbPlatform extends UsbPlatform {
  const UnsupportedUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return const <FlipperDevice>[];
  }

  @override
  Future<Transport> openTransport(UsbDiscoveredDevice device) {
    throw UnsupportedError('USB transport is not available on this platform');
  }
}
