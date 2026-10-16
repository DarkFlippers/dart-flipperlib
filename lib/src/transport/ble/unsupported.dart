import '../../model/discovered.dart';
import '../transport.dart';
import 'platform.dart';

class UnsupportedBlePlatform extends UniversalBlePlatformBase {
  const UnsupportedBlePlatform();

  // Answered here rather than inherited: the base reads the plugin's
  // availability state, and there is no plugin on a platform that reached
  // this class. `unsupported` is also the one answer that must not raise a
  // notice — there is nothing for the user to grant.
  @override
  String get platformLabel => 'unsupported';

  @override
  Future<BleAccess> requestPermissions() async => BleAccess.unsupported;

  @override
  Future<BleAccess> readAccess() async => BleAccess.unsupported;

  @override
  bool includeDevice(BleDiscoveredDevice device) => false;

  @override
  Future<Transport> openTransport(BleDiscoveredDevice device) {
    throw UnsupportedError('BLE transport is not available on this platform');
  }
}
