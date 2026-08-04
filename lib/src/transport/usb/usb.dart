import 'dart:io';

import 'android.dart';
import 'ios.dart';
import 'linux.dart';
import 'macos.dart';
import 'platform.dart';
import 'unsupported.dart';
import 'windows.dart';

export 'platform.dart';

final UsbPlatform usbPlatform = createUsbPlatform();

UsbPlatform createUsbPlatform() {
  if (Platform.isAndroid) return const AndroidUsbPlatform();
  if (Platform.isIOS) return const IosUsbPlatform();
  if (Platform.isLinux) return const LinuxUsbPlatform();
  if (Platform.isMacOS) return const MacosUsbPlatform();
  if (Platform.isWindows) return const WindowsUsbPlatform();
  return const UnsupportedUsbPlatform();
}
