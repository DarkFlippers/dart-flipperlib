import 'dart:io';

import 'port_info.dart';

class SysFS extends ListPortInfo {
  String? usbDevicePath;
  String? devicePath;
  String? subsystem;
  String? usbInterfacePath;

  SysFS(super.device) {
    String dev = device;
    bool isLink = false;
    if (FileSystemEntity.isLinkSync(device)) {
      dev = File(device).resolveSymbolicLinksSync();
      isLink = true;
    }
    usbDevicePath = null;
    if (FileSystemEntity.typeSync('/sys/class/tty/$name/device') !=
        FileSystemEntityType.notFound) {
      devicePath = _realpath('/sys/class/tty/$name/device');
      subsystem = _basename(_realpath('$devicePath/subsystem'));
    } else {
      devicePath = null;
      subsystem = null;
    }
    if (subsystem == 'usb-serial') {
      usbInterfacePath = _dirname(devicePath!);
    } else if (subsystem == 'usb') {
      usbInterfacePath = devicePath;
    } else {
      usbInterfacePath = null;
    }
    if (usbInterfacePath != null) {
      usbDevicePath = _dirname(usbInterfacePath!);

      int numIf;
      try {
        numIf = int.parse(readLine(usbDevicePath!, 'bNumInterfaces')!);
      } on FormatException {
        numIf = 1;
      }

      vid = int.parse(readLine(usbDevicePath!, 'idVendor')!, radix: 16);
      this.pid = int.parse(readLine(usbDevicePath!, 'idProduct')!, radix: 16);
      serialNumber = readLine(usbDevicePath!, 'serial');
      if (numIf > 1) {
        location = _basename(usbInterfacePath!);
      } else {
        location = _basename(usbDevicePath!);
      }

      manufacturer = readLine(usbDevicePath!, 'manufacturer');
      product = readLine(usbDevicePath!, 'product');
      interface = readLine(usbInterfacePath!, 'interface');
    }

    if (subsystem == 'usb' || subsystem == 'usb-serial') {
      applyUsbInfo();
    } else if (subsystem == 'pnp') {
      description = name;
      hwid = readLine(devicePath!, 'id') ?? 'n/a';
    } else if (subsystem == 'amba') {
      description = name;
      hwid = _basename(devicePath!);
    }

    if (isLink) {
      hwid += ' LINK=$dev';
    }
  }

  String? readLine(String base, String leaf) {
    try {
      final lines = File('$base/$leaf').readAsLinesSync();
      return (lines.isEmpty ? '' : lines.first).trim();
    } on IOException {
      return null;
    }
  }

  static String _realpath(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } on IOException {
      return File(path).resolveSymbolicLinksSync();
    }
  }

  static String _basename(String path) => path.split('/').last;

  static String _dirname(String path) =>
      (path.split('/')..removeLast()).join('/');
}

List<SysFS> linuxComports() {
  final devices = <String>[
    ..._glob('ttyS'),
    ..._glob('ttyUSB'),
    ..._glob('ttyXRUSB'),
    ..._glob('ttyACM'),
    ..._glob('ttyAMA'),
    ..._glob('rfcomm'),
    ..._glob('ttyAP'),
  ];
  return [
    for (final d in devices.map(SysFS.new))
      if (d.subsystem != 'platform') d,
  ];
}

List<String> _glob(String prefix) {
  try {
    return [
      for (final entry in Directory('/dev').listSync(followLinks: false))
        if (_basenameOf(entry.path).startsWith(prefix)) entry.path,
    ];
  } on IOException {
    return const [];
  }
}

String _basenameOf(String path) => path.split('/').last;
