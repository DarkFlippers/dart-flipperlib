import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'port_info.dart';

const int _kCFStringEncodingUTF8 = 0x08000100;
const String _kUSBVendorString = 'USB Vendor Name';
const String _kUSBSerialNumberString = 'USB Serial Number';
const int _ioNameSize = 128;
const int _kernSuccess = 0;
const int _kCFNumberSInt16Type = 2;
const int _kCFNumberSInt32Type = 3;

final DynamicLibrary _iokit = DynamicLibrary.open(
  '/System/Library/Frameworks/IOKit.framework/IOKit',
);
final DynamicLibrary _cf = DynamicLibrary.open(
  '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
);

final Pointer<Void> _kCFAllocatorDefault = _cf
    .lookup<Pointer<Void>>('kCFAllocatorDefault')
    .value;

final _ioServiceMatching = _iokit
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)
    >('IOServiceMatching');

final _ioServiceGetMatchingServices = _iokit
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Void>, Pointer<Uint32>),
      int Function(int, Pointer<Void>, Pointer<Uint32>)
    >('IOServiceGetMatchingServices');

final _ioIteratorIsValid = _iokit
    .lookupFunction<Int32 Function(Uint32), int Function(int)>(
      'IOIteratorIsValid',
    );

final _ioIteratorNext = _iokit
    .lookupFunction<Uint32 Function(Uint32), int Function(int)>(
      'IOIteratorNext',
    );

final _ioObjectRelease = _iokit
    .lookupFunction<Int32 Function(Uint32), int Function(int)>(
      'IOObjectRelease',
    );

final _ioRegistryEntryGetParentEntry = _iokit
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Utf8>, Pointer<Uint32>),
      int Function(int, Pointer<Utf8>, Pointer<Uint32>)
    >('IORegistryEntryGetParentEntry');

final _ioRegistryEntryCreateCFProperty = _iokit
    .lookupFunction<
      Pointer<Void> Function(Uint32, Pointer<Void>, Pointer<Void>, Uint32),
      Pointer<Void> Function(int, Pointer<Void>, Pointer<Void>, int)
    >('IORegistryEntryCreateCFProperty');

final _ioRegistryEntryGetName = _iokit
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)
    >('IORegistryEntryGetName');

final _ioObjectGetClass = _iokit
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)
    >('IOObjectGetClass');

final _cfStringCreateWithCString = _cf
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Int32),
      Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int)
    >('CFStringCreateWithCString');

final _cfStringGetCStringPtr = _cf
    .lookupFunction<
      Pointer<Utf8> Function(Pointer<Void>, Uint32),
      Pointer<Utf8> Function(Pointer<Void>, int)
    >('CFStringGetCStringPtr');

final _cfStringGetCString = _cf
    .lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Utf8>, Int64, Uint32),
      int Function(Pointer<Void>, Pointer<Utf8>, int, int)
    >('CFStringGetCString');

final _cfNumberGetValue = _cf
    .lookupFunction<
      Uint8 Function(Pointer<Void>, Int64, Pointer<Void>),
      int Function(Pointer<Void>, int, Pointer<Void>)
    >('CFNumberGetValue');

final _cfRelease = _cf
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'CFRelease',
    );

String? _getStringProperty(int deviceType, String property) {
  return using((arena) {
    final key = _cfStringCreateWithCString(
      _kCFAllocatorDefault,
      property.toNativeUtf8(allocator: arena),
      _kCFStringEncodingUTF8,
    );

    final cfContainer = _ioRegistryEntryCreateCFProperty(
      deviceType,
      key,
      _kCFAllocatorDefault,
      0,
    );
    String? output;

    if (cfContainer != nullptr) {
      final ptr = _cfStringGetCStringPtr(cfContainer, 0);
      if (ptr != nullptr) {
        output = ptr.toDartString();
      } else {
        final buffer = arena.allocate<Utf8>(_ioNameSize);
        final success = _cfStringGetCString(
          cfContainer,
          buffer,
          _ioNameSize,
          _kCFStringEncodingUTF8,
        );
        if (success != 0) {
          output = buffer.toDartString();
        }
      }
      _cfRelease(cfContainer);
    }
    return output;
  });
}

int? _getIntProperty(int deviceType, String property, int cfNumberType) {
  return using((arena) {
    final key = _cfStringCreateWithCString(
      _kCFAllocatorDefault,
      property.toNativeUtf8(allocator: arena),
      _kCFStringEncodingUTF8,
    );

    final cfContainer = _ioRegistryEntryCreateCFProperty(
      deviceType,
      key,
      _kCFAllocatorDefault,
      0,
    );

    if (cfContainer != nullptr) {
      int value;
      if (cfNumberType == _kCFNumberSInt32Type) {
        final number = arena<Uint32>();
        _cfNumberGetValue(cfContainer, cfNumberType, number.cast());
        value = number.value;
      } else {
        final number = arena<Uint16>();
        _cfNumberGetValue(cfContainer, cfNumberType, number.cast());
        value = number.value;
      }
      _cfRelease(cfContainer);
      return value;
    }
    return null;
  });
}

String? _ioRegistryEntryGetNameString(int device) {
  return using((arena) {
    final deviceName = arena.allocate<Utf8>(_ioNameSize);
    final res = _ioRegistryEntryGetName(device, deviceName);
    if (res != _kernSuccess) {
      return null;
    }
    return deviceName.toDartString();
  });
}

String _ioObjectGetClassString(int device) {
  return using((arena) {
    final className = arena.allocate<Utf8>(_ioNameSize);
    _ioObjectGetClass(device, className);
    return className.toDartString();
  });
}

int? _getParentDeviceByType(int device, String parentType) {
  var current = device;
  while (_ioObjectGetClassString(current) != parentType) {
    final response = using((arena) {
      final parent = arena<Uint32>();
      final res = _ioRegistryEntryGetParentEntry(
        current,
        'IOService'.toNativeUtf8(allocator: arena),
        parent,
      );
      return (res, parent.value);
    });
    if (response.$1 != _kernSuccess) {
      return null;
    }
    current = response.$2;
  }
  return current;
}

List<int> _getIOServicesByType(String serviceType) {
  return using((arena) {
    final serialPortIterator = arena<Uint32>();

    _ioServiceGetMatchingServices(
      0,
      _ioServiceMatching(serviceType.toNativeUtf8(allocator: arena)),
      serialPortIterator,
    );

    final services = <int>[];
    while (_ioIteratorIsValid(serialPortIterator.value) != 0) {
      final service = _ioIteratorNext(serialPortIterator.value);
      if (service == 0) {
        break;
      }
      services.add(service);
    }
    _ioObjectRelease(serialPortIterator.value);
    return services;
  });
}

String locationToString(int locationId) {
  var id = locationId;
  final loc = <String>['${id >> 24}-'];
  while (id & 0xf00000 != 0) {
    if (loc.length > 1) {
      loc.add('.');
    }
    loc.add('${(id >> 20) & 0xf}');
    id <<= 4;
  }
  return loc.join();
}

class _SuitableSerialInterface {
  Object? id;
  String? name;
}

List<_SuitableSerialInterface> _scanInterfaces() {
  final interfaces = <_SuitableSerialInterface>[];
  for (final service in _getIOServicesByType('IOSerialBSDClient')) {
    final device = _getStringProperty(service, 'IOCalloutDevice');
    if (device != null && device.isNotEmpty) {
      final usbDevice = _getParentDeviceByType(service, 'IOUSBInterface');
      if (usbDevice != null) {
        final name = _getStringProperty(usbDevice, 'USB Interface Name');
        final locationId = _getIntProperty(
          usbDevice,
          'locationID',
          _kCFNumberSInt32Type,
        );
        final i = _SuitableSerialInterface();
        i.id = (locationId == null || locationId == 0) ? '' : locationId;
        i.name = name;
        interfaces.add(i);
      }
    }
  }
  return interfaces;
}

String? _searchForLocationIdInInterfaces(
  List<_SuitableSerialInterface> serialInterfaces,
  Object? locationId,
) {
  for (final interface in serialInterfaces) {
    if (interface.id == locationId) {
      return interface.name;
    }
  }
  return null;
}

List<ListPortInfo> macosComports() {
  final services = _getIOServicesByType('IOSerialBSDClient');
  final ports = <ListPortInfo>[];
  final serialInterfaces = _scanInterfaces();
  for (final service in services) {
    final device = _getStringProperty(service, 'IOCalloutDevice');
    if (device != null && device.isNotEmpty) {
      final info = ListPortInfo(device);
      var usbDevice = _getParentDeviceByType(service, 'IOUSBHostDevice');
      usbDevice ??= _getParentDeviceByType(service, 'IOUSBDevice');
      if (usbDevice != null) {
        info.vid = _getIntProperty(usbDevice, 'idVendor', _kCFNumberSInt16Type);
        info.pid = _getIntProperty(
          usbDevice,
          'idProduct',
          _kCFNumberSInt16Type,
        );
        info.serialNumber = _getStringProperty(
          usbDevice,
          _kUSBSerialNumberString,
        );
        info.product = _ioRegistryEntryGetNameString(usbDevice) ?? 'n/a';
        info.manufacturer = _getStringProperty(usbDevice, _kUSBVendorString);
        final locationId = _getIntProperty(
          usbDevice,
          'locationID',
          _kCFNumberSInt32Type,
        );
        info.location = locationToString(locationId!);
        info.interface = _searchForLocationIdInInterfaces(
          serialInterfaces,
          locationId,
        );
        info.applyUsbInfo();
      }
      ports.add(info);
    }
  }
  return ports;
}
