import '../../model/discovered.dart';
import '../transport.dart';
import 'platform.dart';

class UnsupportedBlePlatform extends UniversalBlePlatformBase {
  const UnsupportedBlePlatform();

  @override
  Future<void> requestPermissions() async {}

  @override
  bool includeDevice(BleDiscoveredDevice device) => false;

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    throw UnsupportedError('BLE transport is not available on this platform');
  }
}
