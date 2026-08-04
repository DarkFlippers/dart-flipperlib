import 'dart:io';

import 'android.dart';
import 'ios.dart';
import 'linux.dart';
import 'macos.dart';
import 'platform.dart';
import 'unsupported.dart';
import 'windows.dart';

export 'gatt.dart';
export 'link.dart';
export 'platform.dart';

final BlePlatform blePlatform = createBlePlatform();

BlePlatform createBlePlatform() {
  if (Platform.isAndroid) return const AndroidBlePlatform();
  if (Platform.isIOS) return const IosBlePlatform();
  if (Platform.isLinux) return const LinuxBlePlatform();
  if (Platform.isMacOS) return MacosBlePlatform();
  if (Platform.isWindows) return const WindowsBlePlatform();
  return const UnsupportedBlePlatform();
}
