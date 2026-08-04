import '../../model/device.dart';
import '../../model/discovered.dart';
import '../transport.dart';
import 'platform.dart';

class IosUsbPlatform extends UsbPlatform {
  const IosUsbPlatform();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    return const <FlipperDevice>[];
  }

  @override
  Future<Transport> openTransport(UsbDiscoveredDevice device) {
    throw UnsupportedError('USB transport is not available on iOS');
  }
}
