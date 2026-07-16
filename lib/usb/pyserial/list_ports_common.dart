import 'dart:io';

class ListPortInfo {
  final String device;
  late final String name;
  String description = 'n/a';
  String hwid = 'n/a';
  int? vid;
  int? pid;
  String? serialNumber;
  String? location;
  String? manufacturer;
  String? product;
  String? interface;

  ListPortInfo(this.device, {bool skipLinkDetection = false}) {
    name = device.split(RegExp(r'[/\\]')).last;
    if (!skipLinkDetection && FileSystemEntity.isLinkSync(device)) {
      hwid = 'LINK=${File(device).resolveSymbolicLinksSync()}';
    }
  }

  String usbDescription() {
    if (interface != null) {
      return '$product - $interface';
    } else if (product != null) {
      return product!;
    } else {
      return name;
    }
  }

  String usbInfo() {
    final v = (vid ?? 0).toRadixString(16).toUpperCase().padLeft(4, '0');
    final p = (pid ?? 0).toRadixString(16).toUpperCase().padLeft(4, '0');
    final ser = serialNumber != null ? ' SER=$serialNumber' : '';
    final loc = location != null ? ' LOCATION=$location' : '';
    return 'USB VID:PID=$v:$p$ser$loc';
  }

  void applyUsbInfo() {
    description = usbDescription();
    hwid = usbInfo();
  }
}
