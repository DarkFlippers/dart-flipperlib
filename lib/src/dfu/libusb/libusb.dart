// Minimal hand-written FFI bindings for libusb 1.0 — only the subset the DfuSe
// recovery layer needs (device enumeration, control transfers, alt settings,
// config/string descriptors, wrapping an externally opened descriptor).
// Deliberately not generated: keeps us on the project's `ffi ^2.x` (the pub
// `libusb` package is pinned to ffi 1.x) and free of an extra dependency. The
// native library is built from src/libusb on macOS (CocoaPods, see
// flipperlib.podspec), Windows and Android, and taken from the system on Linux.
//
// Struct layouts mirror libusb.h on 64-bit; field order/types are chosen so the
// ffi-computed size and alignment match the C ABI.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../common/log.dart';

// ── Constants ────────────────────────────────────────────────────────────────

/// Endpoint direction bits (bmRequestType high bit).
const int libusbEndpointIn = 0x80;
const int libusbEndpointOut = 0x00;

/// Request type / recipient bits for bmRequestType.
const int libusbRequestTypeClass = 0x01 << 5;
const int libusbRecipientInterface = 0x01;

/// libusb_error values we care about.
const int libusbSuccess = 0;
const int libusbErrorAccess = -3;
const int libusbErrorNoDevice = -4;
const int libusbErrorNotSupported = -12;

/// libusb_option: skip bus enumeration so libusb_init works without access to
/// /dev/bus/usb (Android); devices are then opened via libusb_wrap_sys_device.
const int libusbOptionNoDeviceDiscovery = 2;

// ── Opaque handles ───────────────────────────────────────────────────────────

final class LibusbContext extends Opaque {}

final class LibusbDevice extends Opaque {}

final class LibusbDeviceHandle extends Opaque {}

// ── Structs ──────────────────────────────────────────────────────────────────

final class LibusbDeviceDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint16()
  external int bcdUSB;
  @Uint8()
  external int bDeviceClass;
  @Uint8()
  external int bDeviceSubClass;
  @Uint8()
  external int bDeviceProtocol;
  @Uint8()
  external int bMaxPacketSize0;
  @Uint16()
  external int idVendor;
  @Uint16()
  external int idProduct;
  @Uint16()
  external int bcdDevice;
  @Uint8()
  external int iManufacturer;
  @Uint8()
  external int iProduct;
  @Uint8()
  external int iSerialNumber;
  @Uint8()
  external int bNumConfigurations;
}

final class LibusbInterfaceDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint8()
  external int bInterfaceNumber;
  @Uint8()
  external int bAlternateSetting;
  @Uint8()
  external int bNumEndpoints;
  @Uint8()
  external int bInterfaceClass;
  @Uint8()
  external int bInterfaceSubClass;
  @Uint8()
  external int bInterfaceProtocol;
  @Uint8()
  external int iInterface;
  external Pointer<Void> endpoint;
  external Pointer<Uint8> extra;
  @Int()
  external int extraLength;
}

final class LibusbInterface extends Struct {
  external Pointer<LibusbInterfaceDescriptor> altsetting;
  @Int()
  external int numAltsetting;
}

final class LibusbInitOptionValue extends Union {
  @Int32()
  external int ival;
  external Pointer<Void> logCb;
}

final class LibusbInitOption extends Struct {
  @Int32()
  external int option;
  external LibusbInitOptionValue value;
}

final class LibusbConfigDescriptor extends Struct {
  @Uint8()
  external int bLength;
  @Uint8()
  external int bDescriptorType;
  @Uint16()
  external int wTotalLength;
  @Uint8()
  external int bNumInterfaces;
  @Uint8()
  external int bConfigurationValue;
  @Uint8()
  external int iConfiguration;
  @Uint8()
  external int bmAttributes;
  @Uint8()
  external int maxPower;
  external Pointer<LibusbInterface> interface1;
  external Pointer<Uint8> extra;
  @Int()
  external int extraLength;
}

// ── Native function typedefs ─────────────────────────────────────────────────

typedef _InitNative = Int32 Function(Pointer<Pointer<LibusbContext>>);
typedef LibusbInit = int Function(Pointer<Pointer<LibusbContext>>);

typedef _InitContextNative =
    Int32 Function(
      Pointer<Pointer<LibusbContext>>,
      Pointer<LibusbInitOption>,
      Int32,
    );
typedef LibusbInitContext =
    int Function(
      Pointer<Pointer<LibusbContext>>,
      Pointer<LibusbInitOption>,
      int,
    );

typedef _ExitNative = Void Function(Pointer<LibusbContext>);
typedef LibusbExit = void Function(Pointer<LibusbContext>);

typedef _WrapSysDeviceNative =
    Int32 Function(
      Pointer<LibusbContext>,
      IntPtr,
      Pointer<Pointer<LibusbDeviceHandle>>,
    );
typedef LibusbWrapSysDevice =
    int Function(
      Pointer<LibusbContext>,
      int,
      Pointer<Pointer<LibusbDeviceHandle>>,
    );

typedef _GetDeviceNative =
    Pointer<LibusbDevice> Function(Pointer<LibusbDeviceHandle>);
typedef LibusbGetDevice =
    Pointer<LibusbDevice> Function(Pointer<LibusbDeviceHandle>);

typedef _GetDeviceListNative =
    IntPtr Function(
      Pointer<LibusbContext>,
      Pointer<Pointer<Pointer<LibusbDevice>>>,
    );
typedef LibusbGetDeviceList =
    int Function(
      Pointer<LibusbContext>,
      Pointer<Pointer<Pointer<LibusbDevice>>>,
    );

typedef _FreeDeviceListNative =
    Void Function(Pointer<Pointer<LibusbDevice>>, Int32);
typedef LibusbFreeDeviceList =
    void Function(Pointer<Pointer<LibusbDevice>>, int);

typedef _GetDeviceDescriptorNative =
    Int32 Function(Pointer<LibusbDevice>, Pointer<LibusbDeviceDescriptor>);
typedef LibusbGetDeviceDescriptor =
    int Function(Pointer<LibusbDevice>, Pointer<LibusbDeviceDescriptor>);

typedef _OpenNative =
    Int32 Function(Pointer<LibusbDevice>, Pointer<Pointer<LibusbDeviceHandle>>);
typedef LibusbOpen =
    int Function(Pointer<LibusbDevice>, Pointer<Pointer<LibusbDeviceHandle>>);

typedef _CloseNative = Void Function(Pointer<LibusbDeviceHandle>);
typedef LibusbClose = void Function(Pointer<LibusbDeviceHandle>);

typedef _ClaimNative = Int32 Function(Pointer<LibusbDeviceHandle>, Int32);
typedef LibusbClaim = int Function(Pointer<LibusbDeviceHandle>, int);

typedef _SetAltNative =
    Int32 Function(Pointer<LibusbDeviceHandle>, Int32, Int32);
typedef LibusbSetAlt = int Function(Pointer<LibusbDeviceHandle>, int, int);

typedef _ControlTransferNative =
    Int32 Function(
      Pointer<LibusbDeviceHandle>,
      Uint8,
      Uint8,
      Uint16,
      Uint16,
      Pointer<Uint8>,
      Uint16,
      Uint32,
    );
typedef LibusbControlTransfer =
    int Function(
      Pointer<LibusbDeviceHandle>,
      int,
      int,
      int,
      int,
      Pointer<Uint8>,
      int,
      int,
    );

typedef _GetConfigDescriptorNative =
    Int32 Function(
      Pointer<LibusbDevice>,
      Uint8,
      Pointer<Pointer<LibusbConfigDescriptor>>,
    );
typedef LibusbGetConfigDescriptor =
    int Function(
      Pointer<LibusbDevice>,
      int,
      Pointer<Pointer<LibusbConfigDescriptor>>,
    );

typedef _FreeConfigDescriptorNative =
    Void Function(Pointer<LibusbConfigDescriptor>);
typedef LibusbFreeConfigDescriptor =
    void Function(Pointer<LibusbConfigDescriptor>);

typedef _GetStringDescriptorAsciiNative =
    Int32 Function(Pointer<LibusbDeviceHandle>, Uint8, Pointer<Uint8>, Int32);
typedef LibusbGetStringDescriptorAscii =
    int Function(Pointer<LibusbDeviceHandle>, int, Pointer<Uint8>, int);

typedef _ErrorNameNative = Pointer<Utf8> Function(Int32);
typedef LibusbErrorName = Pointer<Utf8> Function(int);

typedef _SetAutoDetachNative =
    Int32 Function(Pointer<LibusbDeviceHandle>, Int32);
typedef LibusbSetAutoDetach = int Function(Pointer<LibusbDeviceHandle>, int);

typedef _RefDeviceNative =
    Pointer<LibusbDevice> Function(Pointer<LibusbDevice>);
typedef LibusbRefDevice = Pointer<LibusbDevice> Function(Pointer<LibusbDevice>);

typedef _UnrefDeviceNative = Void Function(Pointer<LibusbDevice>);
typedef LibusbUnrefDevice = void Function(Pointer<LibusbDevice>);

/// Thin object-style wrapper over the resolved libusb symbols.
class Libusb {
  Libusb._(this._lib) {
    init = _lib.lookupFunction<_InitNative, LibusbInit>('libusb_init');
    initContext = _lib.lookupFunction<_InitContextNative, LibusbInitContext>(
      'libusb_init_context',
    );
    exit = _lib.lookupFunction<_ExitNative, LibusbExit>('libusb_exit');
    wrapSysDevice = _lib
        .lookupFunction<_WrapSysDeviceNative, LibusbWrapSysDevice>(
          'libusb_wrap_sys_device',
        );
    getDevice = _lib.lookupFunction<_GetDeviceNative, LibusbGetDevice>(
      'libusb_get_device',
    );
    getDeviceList = _lib
        .lookupFunction<_GetDeviceListNative, LibusbGetDeviceList>(
          'libusb_get_device_list',
        );
    freeDeviceList = _lib
        .lookupFunction<_FreeDeviceListNative, LibusbFreeDeviceList>(
          'libusb_free_device_list',
        );
    getDeviceDescriptor = _lib
        .lookupFunction<_GetDeviceDescriptorNative, LibusbGetDeviceDescriptor>(
          'libusb_get_device_descriptor',
        );
    open = _lib.lookupFunction<_OpenNative, LibusbOpen>('libusb_open');
    close = _lib.lookupFunction<_CloseNative, LibusbClose>('libusb_close');
    claimInterface = _lib.lookupFunction<_ClaimNative, LibusbClaim>(
      'libusb_claim_interface',
    );
    releaseInterface = _lib.lookupFunction<_ClaimNative, LibusbClaim>(
      'libusb_release_interface',
    );
    setInterfaceAltSetting = _lib.lookupFunction<_SetAltNative, LibusbSetAlt>(
      'libusb_set_interface_alt_setting',
    );
    controlTransfer = _lib
        .lookupFunction<_ControlTransferNative, LibusbControlTransfer>(
          'libusb_control_transfer',
        );
    getConfigDescriptor = _lib
        .lookupFunction<_GetConfigDescriptorNative, LibusbGetConfigDescriptor>(
          'libusb_get_config_descriptor',
        );
    freeConfigDescriptor = _lib
        .lookupFunction<
          _FreeConfigDescriptorNative,
          LibusbFreeConfigDescriptor
        >('libusb_free_config_descriptor');
    getStringDescriptorAscii = _lib
        .lookupFunction<
          _GetStringDescriptorAsciiNative,
          LibusbGetStringDescriptorAscii
        >('libusb_get_string_descriptor_ascii');
    errorName = _lib.lookupFunction<_ErrorNameNative, LibusbErrorName>(
      'libusb_error_name',
    );
    setAutoDetachKernelDriver = _lib
        .lookupFunction<_SetAutoDetachNative, LibusbSetAutoDetach>(
          'libusb_set_auto_detach_kernel_driver',
        );
    refDevice = _lib.lookupFunction<_RefDeviceNative, LibusbRefDevice>(
      'libusb_ref_device',
    );
    unrefDevice = _lib.lookupFunction<_UnrefDeviceNative, LibusbUnrefDevice>(
      'libusb_unref_device',
    );
  }

  final DynamicLibrary _lib;

  late final LibusbInit init;
  late final LibusbInitContext initContext;
  late final LibusbExit exit;
  late final LibusbWrapSysDevice wrapSysDevice;
  late final LibusbGetDevice getDevice;
  late final LibusbGetDeviceList getDeviceList;
  late final LibusbFreeDeviceList freeDeviceList;
  late final LibusbGetDeviceDescriptor getDeviceDescriptor;
  late final LibusbOpen open;
  late final LibusbClose close;
  late final LibusbClaim claimInterface;
  late final LibusbClaim releaseInterface;
  late final LibusbSetAlt setInterfaceAltSetting;
  late final LibusbControlTransfer controlTransfer;
  late final LibusbGetConfigDescriptor getConfigDescriptor;
  late final LibusbFreeConfigDescriptor freeConfigDescriptor;
  late final LibusbGetStringDescriptorAscii getStringDescriptorAscii;
  late final LibusbErrorName errorName;
  late final LibusbSetAutoDetach setAutoDetachKernelDriver;
  late final LibusbRefDevice refDevice;
  late final LibusbUnrefDevice unrefDevice;

  /// Decodes a libusb negative error code into its symbolic name.
  String errorString(int code) {
    try {
      return errorName(code).toDartString();
    } catch (_) {
      return 'libusb error $code';
    }
  }

  static Libusb? _instance;
  static bool _unavailable = false;

  /// Loads libusb once per isolate. Returns null when the platform has no
  /// libusb build (so callers can degrade gracefully instead of crashing).
  static Libusb? get instance {
    if (_instance != null) return _instance;
    if (_unavailable) return null;
    final lib = _tryLoad();
    if (lib == null) {
      _unavailable = true;
      return null;
    }
    return _instance = Libusb._(lib);
  }

  static DynamicLibrary? _tryLoad() {
    final candidates = <DynamicLibrary Function()>[
      if (Platform.isMacOS) ...[
        // Compiled into the flipperlib pod — symbols are already in the process.
        () => DynamicLibrary.process(),
        () => DynamicLibrary.open(
          '/opt/homebrew/opt/libusb/lib/libusb-1.0.0.dylib',
        ),
        () =>
            DynamicLibrary.open('/usr/local/opt/libusb/lib/libusb-1.0.0.dylib'),
      ],
      if (Platform.isLinux) ...[
        () => DynamicLibrary.open('libusb-1.0.so.0'),
        () => DynamicLibrary.open('libusb-1.0.so'),
      ],
      if (Platform.isWindows) ...[
        // The DLL built from src/libusb is installed next to the executable;
        // load it by absolute path so a stray copy on PATH can not shadow it.
        () => DynamicLibrary.open(
          '${File(Platform.resolvedExecutable).parent.path}'
          '${Platform.pathSeparator}libusb-1.0.dll',
        ),
        () => DynamicLibrary.open('libusb-1.0.dll'),
      ],
      // Built from src/libusb by the plugin's externalNativeBuild.
      if (Platform.isAndroid) () => DynamicLibrary.open('libusb1.0.so'),
    ];
    for (final load in candidates) {
      try {
        final lib = load();
        // Confirm the symbols are actually here before committing to this lib.
        lib.lookup<NativeFunction<_InitNative>>('libusb_init');
        return lib;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

/// The isolate's libusb context. Created on first use; on Android it is
/// initialised with LIBUSB_OPTION_NO_DEVICE_DISCOVERY because the bus can not
/// be enumerated without root — devices arrive as descriptors from UsbManager
/// and are attached with libusb_wrap_sys_device.
abstract final class LibusbSession {
  static Pointer<LibusbContext> _ctx = nullptr;
  static bool _initFailed = false;

  static Pointer<LibusbContext>? get context {
    if (_ctx != nullptr) return _ctx;
    if (_initFailed) return null;
    final usb = Libusb.instance;
    if (usb == null) {
      _initFailed = true;
      return null;
    }
    final out = malloc<Pointer<LibusbContext>>();
    try {
      final int err;
      if (Platform.isAndroid) {
        final options = calloc<LibusbInitOption>();
        try {
          options.ref.option = libusbOptionNoDeviceDiscovery;
          err = usb.initContext(out, options, 1);
        } finally {
          calloc.free(options);
        }
      } else {
        err = usb.init(out);
      }
      if (err != libusbSuccess) {
        Log.error('[DFU] libusb_init failed: ${usb.errorString(err)}');
        _initFailed = true;
        return null;
      }
      _ctx = out.value;
      return _ctx;
    } finally {
      malloc.free(out);
    }
  }
}
