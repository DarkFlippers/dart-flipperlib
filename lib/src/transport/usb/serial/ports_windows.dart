import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'port_info.dart';

const int _digcfPresent = 2;
const int _errorInsufficientBuffer = 122;
const int _errorNotFound = 1168;
const int _spdrpHardwareId = 1;
const int _spdrpFriendlyName = 12;
const int _spdrpLocationPaths = 35;
const int _spdrpMfg = 11;
const int _dicsFlagGlobal = 1;
const int _diregDev = 0x00000001;
const int _keyRead = 0x20019;

const int _maxUsbDeviceTreeTraversalDepth = 5;

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

final class _SpDevinfoData extends Struct {
  @Uint32()
  external int cbSize;
  external _Guid classGuid;
  @Uint32()
  external int devInst;
  @IntPtr()
  external int reserved;
}

final DynamicLibrary _setupapi = DynamicLibrary.open('setupapi.dll');
final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');
final DynamicLibrary _cfgmgr32 = DynamicLibrary.open('cfgmgr32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _setupDiDestroyDeviceInfoList = _setupapi
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetupDiDestroyDeviceInfoList',
    );

final _setupDiClassGuidsFromName = _setupapi
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<_Guid>, Uint32, Pointer<Uint32>),
      int Function(Pointer<Utf16>, Pointer<_Guid>, int, Pointer<Uint32>)
    >('SetupDiClassGuidsFromNameW');

final _setupDiEnumDeviceInfo = _setupapi
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<_SpDevinfoData>),
      int Function(int, int, Pointer<_SpDevinfoData>)
    >('SetupDiEnumDeviceInfo');

final _setupDiGetClassDevs = _setupapi
    .lookupFunction<
      IntPtr Function(Pointer<_Guid>, Pointer<Utf16>, IntPtr, Uint32),
      int Function(Pointer<_Guid>, Pointer<Utf16>, int, int)
    >('SetupDiGetClassDevsW');

final _setupDiGetDeviceRegistryProperty = _setupapi
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<_SpDevinfoData>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
        Uint32,
        Pointer<Uint32>,
      ),
      int Function(
        int,
        Pointer<_SpDevinfoData>,
        int,
        Pointer<Uint32>,
        Pointer<Void>,
        int,
        Pointer<Uint32>,
      )
    >('SetupDiGetDeviceRegistryPropertyW');

final _setupDiGetDeviceInstanceId = _setupapi
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<_SpDevinfoData>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Uint32>,
      ),
      int Function(
        int,
        Pointer<_SpDevinfoData>,
        Pointer<Utf16>,
        int,
        Pointer<Uint32>,
      )
    >('SetupDiGetDeviceInstanceIdW');

final _setupDiOpenDevRegKey = _setupapi
    .lookupFunction<
      IntPtr Function(
        IntPtr,
        Pointer<_SpDevinfoData>,
        Uint32,
        Uint32,
        Uint32,
        Uint32,
      ),
      int Function(int, Pointer<_SpDevinfoData>, int, int, int, int)
    >('SetupDiOpenDevRegKey');

final _regCloseKey = _advapi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

final _regQueryValueEx = _advapi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      ),
      int Function(
        int,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      )
    >('RegQueryValueExW');

final _cmGetParent = _cfgmgr32
    .lookupFunction<
      Int32 Function(Pointer<Uint32>, Uint32, Uint32),
      int Function(Pointer<Uint32>, int, int)
    >('CM_Get_Parent');

final _cmGetDeviceId = _cfgmgr32
    .lookupFunction<
      Int32 Function(Uint32, Pointer<Utf16>, Uint32, Uint32),
      int Function(int, Pointer<Utf16>, int, int)
    >('CM_Get_Device_IDW');

final _cmMapCrToWin32Err = _cfgmgr32
    .lookupFunction<Uint32 Function(Uint32, Uint32), int Function(int, int)>(
      'CM_MapCrToWin32Err',
    );

final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

final RegExp _usbInstanceIdRe = RegExp(
  r'VID_([0-9a-f]{4})(&PID_([0-9a-f]{4}))?(&MI_(\d{2}))?(\\(.*))?',
  caseSensitive: false,
);

final RegExp _ftdibusRe = RegExp(
  r'VID_([0-9a-f]{4})\+PID_([0-9a-f]{4})(\+(\w+))?',
  caseSensitive: false,
);

final RegExp _wordRe = RegExp(r'^\w+$');

final RegExp _locationRe = RegExp(r'USBROOT\((\w+)\)|#USB\((\w+)\)');

String getParentSerialNumber(
  int childDevinst,
  int? childVid,
  int? childPid, [
  int depth = 0,
  String? lastSerialNumber,
]) {
  String fallback() => (lastSerialNumber == null || lastSerialNumber.isEmpty)
      ? ''
      : lastSerialNumber;

  if (depth > _maxUsbDeviceTreeTraversalDepth) {
    return fallback();
  }

  return using((arena) {
    final devinst = arena<Uint32>();
    final ret = _cmGetParent(devinst, childDevinst, 0);

    if (ret != 0) {
      final winError = _cmMapCrToWin32Err(ret, 0);
      if (winError == _errorNotFound) {
        return fallback();
      }
      throw StateError('CM_Get_Parent failed, WinError $winError');
    }

    final parentHardwareId = arena<Uint16>(500).cast<Utf16>();
    final idRet = _cmGetDeviceId(devinst.value, parentHardwareId, 499, 0);
    if (idRet != 0) {
      throw StateError(
        'CM_Get_Device_IDW failed, WinError ${_cmMapCrToWin32Err(idRet, 0)}',
      );
    }

    final parentHardwareIdStr = parentHardwareId.toDartString();
    final m = _usbInstanceIdRe.firstMatch(parentHardwareIdStr);

    if (m == null) {
      return fallback();
    }

    int? vid;
    int? pid;
    String? serialNumber;
    final g1 = m.group(1);
    if (g1 != null && g1.isNotEmpty) {
      vid = int.parse(g1, radix: 16);
    }
    final g3 = m.group(3);
    if (g3 != null && g3.isNotEmpty) {
      pid = int.parse(g3, radix: 16);
    }
    final g7 = m.group(7);
    if (g7 != null && g7.isNotEmpty) {
      serialNumber = g7;
    }

    final foundSerialNumber = serialNumber;

    if (serialNumber != null &&
        serialNumber.isNotEmpty &&
        !_wordRe.hasMatch(serialNumber)) {
      serialNumber = null;
    }

    if (vid == null || vid == 0 || pid == null || pid == 0) {
      return getParentSerialNumber(
        devinst.value,
        childVid,
        childPid,
        depth + 1,
        foundSerialNumber,
      );
    }

    if (pid != childPid || vid != childVid) {
      return fallback();
    }

    if (serialNumber == null || serialNumber.isEmpty) {
      return getParentSerialNumber(
        devinst.value,
        childVid,
        childPid,
        depth + 1,
        foundSerialNumber,
      );
    }

    return serialNumber;
  });
}

List<ListPortInfo> windowsComports() {
  return using((arena) {
    final portsGuids = arena<_Guid>(8);
    final portsGuidsSize = arena<Uint32>();
    if (_setupDiClassGuidsFromName(
          'Ports'.toNativeUtf16(allocator: arena),
          portsGuids,
          8,
          portsGuidsSize,
        ) ==
        0) {
      throw StateError(
        'SetupDiClassGuidsFromName(Ports) failed, WinError ${_getLastError()}',
      );
    }

    final modemsGuids = arena<_Guid>(8);
    final modemsGuidsSize = arena<Uint32>();
    if (_setupDiClassGuidsFromName(
          'Modem'.toNativeUtf16(allocator: arena),
          modemsGuids,
          8,
          modemsGuidsSize,
        ) ==
        0) {
      throw StateError(
        'SetupDiClassGuidsFromName(Modem) failed, WinError ${_getLastError()}',
      );
    }

    final guids = <Pointer<_Guid>>[
      for (var i = 0; i < portsGuidsSize.value; i++) portsGuids + i,
      for (var i = 0; i < modemsGuidsSize.value; i++) modemsGuids + i,
    ];

    final result = <ListPortInfo>[];

    for (final guid in guids) {
      int? bInterfaceNumber;
      final gHdi = _setupDiGetClassDevs(guid, nullptr, 0, _digcfPresent);
      if (gHdi == 0) {
        throw StateError(
          'SetupDiGetClassDevs failed, WinError ${_getLastError()}',
        );
      }

      final devinfo = arena<_SpDevinfoData>();
      devinfo.ref.cbSize = sizeOf<_SpDevinfoData>();
      var index = 0;
      while (_setupDiEnumDeviceInfo(gHdi, index, devinfo) != 0) {
        index += 1;

        final hkey = _setupDiOpenDevRegKey(
          gHdi,
          devinfo,
          _dicsFlagGlobal,
          0,
          _diregDev,
          _keyRead,
        );
        final portNameBuffer = arena<Uint16>(250).cast<Utf16>();
        final portNameLength = arena<Uint32>()..value = 500;
        _regQueryValueEx(
          hkey,
          'PortName'.toNativeUtf16(allocator: arena),
          nullptr,
          nullptr,
          portNameBuffer.cast(),
          portNameLength,
        );
        _regCloseKey(hkey);

        final portName = portNameBuffer.toDartString();
        if (portName.startsWith('LPT')) {
          continue;
        }

        final szHardwareId = arena<Uint16>(500).cast<Utf16>();
        if (_setupDiGetDeviceInstanceId(
              gHdi,
              devinfo,
              szHardwareId,
              499,
              nullptr,
            ) ==
            0) {
          if (_setupDiGetDeviceRegistryProperty(
                gHdi,
                devinfo,
                _spdrpHardwareId,
                nullptr,
                szHardwareId.cast(),
                499,
                nullptr,
              ) ==
              0) {
            if (_getLastError() != _errorInsufficientBuffer) {
              throw StateError(
                'SetupDiGetDeviceRegistryProperty(SPDRP_HARDWAREID) failed, '
                'WinError ${_getLastError()}',
              );
            }
          }
        }
        final szHardwareIdStr = szHardwareId.toDartString();

        final info = ListPortInfo(portName, skipLinkDetection: true);

        if (szHardwareIdStr.startsWith('USB')) {
          final m = _usbInstanceIdRe.firstMatch(szHardwareIdStr);
          if (m != null) {
            info.vid = int.parse(m.group(1)!, radix: 16);
            final g3 = m.group(3);
            if (g3 != null && g3.isNotEmpty) {
              info.pid = int.parse(g3, radix: 16);
            }
            final g5 = m.group(5);
            if (g5 != null && g5.isNotEmpty) {
              bInterfaceNumber = int.parse(g5);
            }

            final g7 = m.group(7);
            if (g7 != null && g7.isNotEmpty && _wordRe.hasMatch(g7)) {
              info.serialNumber = g7;
            } else {
              info.serialNumber = getParentSerialNumber(
                devinfo.ref.devInst,
                info.vid,
                info.pid,
              );
            }
          }

          final locPathStr = arena<Uint16>(250).cast<Utf16>();
          if (_setupDiGetDeviceRegistryProperty(
                gHdi,
                devinfo,
                _spdrpLocationPaths,
                nullptr,
                locPathStr.cast(),
                499,
                nullptr,
              ) !=
              0) {
            final location = <String>[];
            for (final g in _locationRe.allMatches(locPathStr.toDartString())) {
              final g1 = g.group(1);
              if (g1 != null && g1.isNotEmpty) {
                location.add('${int.parse(g1) + 1}');
              } else {
                if (location.length > 1) {
                  location.add('.');
                } else {
                  location.add('-');
                }
                location.add(g.group(2)!);
              }
            }
            if (bInterfaceNumber != null) {
              location.add(':x.$bInterfaceNumber');
            }
            if (location.isNotEmpty) {
              info.location = location.join();
            }
          }
          info.hwid = info.usbInfo();
        } else if (szHardwareIdStr.startsWith('FTDIBUS')) {
          final m = _ftdibusRe.firstMatch(szHardwareIdStr);
          if (m != null) {
            info.vid = int.parse(m.group(1)!, radix: 16);
            info.pid = int.parse(m.group(2)!, radix: 16);
            final g4 = m.group(4);
            if (g4 != null && g4.isNotEmpty) {
              info.serialNumber = g4;
            }
          }
          info.hwid = info.usbInfo();
        } else {
          info.hwid = szHardwareIdStr;
        }

        final szFriendlyName = arena<Uint16>(250).cast<Utf16>();
        if (_setupDiGetDeviceRegistryProperty(
              gHdi,
              devinfo,
              _spdrpFriendlyName,
              nullptr,
              szFriendlyName.cast(),
              499,
              nullptr,
            ) !=
            0) {
          info.description = szFriendlyName.toDartString();
        }

        final szManufacturer = arena<Uint16>(250).cast<Utf16>();
        if (_setupDiGetDeviceRegistryProperty(
              gHdi,
              devinfo,
              _spdrpMfg,
              nullptr,
              szManufacturer.cast(),
              499,
              nullptr,
            ) !=
            0) {
          info.manufacturer = szManufacturer.toDartString();
        }
        result.add(info);
      }
      _setupDiDestroyDeviceInfoList(gHdi);
    }

    return result;
  });
}
