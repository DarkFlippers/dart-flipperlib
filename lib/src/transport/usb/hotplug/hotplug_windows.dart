import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../../common/log.dart';
import 'hotplug.dart';

// A hidden top-level window on a background isolate, subscribed to device
// interface changes via RegisterDeviceNotification. Its GetMessage loop blocks
// (0 % CPU) until Windows broadcasts WM_DEVICECHANGE or the main isolate posts
// WM_CLOSE to tear it down. The window procedure is dispatched synchronously on
// the loop's own thread, so an isolate-local NativeCallable is valid.

const int _wmClose = 0x0010;
const int _wmDestroy = 0x0002;
const int _wmDeviceChange = 0x0219;
const int _dbtDevtypDeviceInterface = 0x00000005;
const int _deviceNotifyWindowHandle = 0x00000000;
const int _deviceNotifyAllInterfaceClasses = 0x00000004;

final class _Wndclassexw extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int style;
  external Pointer<NativeFunction<_WndProcNative>> lpfnWndProc;
  @Int32()
  external int cbClsExtra;
  @Int32()
  external int cbWndExtra;
  external Pointer<Void> hInstance;
  external Pointer<Void> hIcon;
  external Pointer<Void> hCursor;
  external Pointer<Void> hbrBackground;
  external Pointer<Utf16> lpszMenuName;
  external Pointer<Utf16> lpszClassName;
  external Pointer<Void> hIconSm;
}

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _Msg extends Struct {
  external Pointer<Void> hwnd;
  @Uint32()
  external int message;
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  external _Point pt;
  @Uint32()
  external int lPrivate;
}

final class _DevBroadcastDeviceInterface extends Struct {
  @Uint32()
  external int dbccSize;
  @Uint32()
  external int dbccDeviceType;
  @Uint32()
  external int dbccReserved;
  @Array<Uint8>(16)
  external Array<Uint8> dbccClassGuid;
  @Uint16()
  external int dbccName;
}

typedef _WndProcNative = IntPtr Function(Pointer<Void>, Uint32, IntPtr, IntPtr);

class WindowsHotplugWatcher implements UsbHotplugWatcher {
  Isolate? _isolate;
  ReceivePort? _recv;
  int _hwnd = 0;
  void Function()? _onEvent;

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _postMessageW = _user32
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
        int Function(int, int, int, int)
      >('PostMessageW');

  @override
  bool start(void Function() onEvent) {
    _onEvent = onEvent;
    final recv = _recv = ReceivePort();
    recv.listen((msg) {
      if (msg is int) {
        _hwnd = msg;
      } else if (msg == 'error') {
        Log.error('[USB] Windows device-notify window failed to start');
      } else {
        _onEvent?.call();
      }
    });

    Isolate.spawn(_windowEntry, recv.sendPort).then(
      (iso) {
        _isolate = iso;
      },
      onError: (Object e) {
        Log.error('[USB] Windows hotplug isolate spawn failed: $e');
      },
    );
    return true;
  }

  @override
  void stop() {
    final hwnd = _hwnd;
    _hwnd = 0;
    if (hwnd != 0) {
      // Cross-thread post is safe; drives the window to WM_DESTROY → WM_QUIT,
      // ending the isolate's message loop cleanly.
      _postMessageW(hwnd, _wmClose, 0, 0);
    }
    _recv?.close();
    _recv = null;
    _onEvent = null;
    final iso = _isolate;
    _isolate = null;
    Future<void>.delayed(const Duration(seconds: 1), () {
      iso?.kill(priority: Isolate.beforeNextEvent);
    });
  }
}

void _windowEntry(SendPort mainSend) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final user32 = DynamicLibrary.open('user32.dll');

  final getModuleHandleW = kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf16>),
        Pointer<Void> Function(Pointer<Utf16>)
      >('GetModuleHandleW');
  final registerClassExW = user32
      .lookupFunction<
        Uint16 Function(Pointer<_Wndclassexw>),
        int Function(Pointer<_Wndclassexw>)
      >('RegisterClassExW');
  final createWindowExW = user32
      .lookupFunction<
        Pointer<Void> Function(
          Uint32,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
          Int32,
          Int32,
          Int32,
          Int32,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          int,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
          int,
          int,
          int,
          int,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
        )
      >('CreateWindowExW');
  final defWindowProcW = user32
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Uint32, IntPtr, IntPtr),
        int Function(Pointer<Void>, int, int, int)
      >('DefWindowProcW');
  final destroyWindow = user32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('DestroyWindow');
  final postQuitMessage = user32
      .lookupFunction<Void Function(Int32), void Function(int)>(
        'PostQuitMessage',
      );
  final registerDeviceNotificationW = user32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Uint32),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int)
      >('RegisterDeviceNotificationW');
  final unregisterDeviceNotification = user32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('UnregisterDeviceNotification');
  final getMessageW = user32
      .lookupFunction<
        Int32 Function(Pointer<_Msg>, Pointer<Void>, Uint32, Uint32),
        int Function(Pointer<_Msg>, Pointer<Void>, int, int)
      >('GetMessageW');
  final translateMessage = user32
      .lookupFunction<
        Int32 Function(Pointer<_Msg>),
        int Function(Pointer<_Msg>)
      >('TranslateMessage');
  final dispatchMessageW = user32
      .lookupFunction<
        IntPtr Function(Pointer<_Msg>),
        int Function(Pointer<_Msg>)
      >('DispatchMessageW');

  final className = 'QUnleashedUsbHotplug'.toNativeUtf16();
  Pointer<Void> hwnd = nullptr;
  Pointer<Void> notify = nullptr;

  int wndProc(Pointer<Void> hWnd, int msg, int wParam, int lParam) {
    switch (msg) {
      case _wmDeviceChange:
        mainSend.send(null);
        return 1;
      case _wmClose:
        destroyWindow(hWnd);
        return 0;
      case _wmDestroy:
        postQuitMessage(0);
        return 0;
      default:
        return defWindowProcW(hWnd, msg, wParam, lParam);
    }
  }

  final callback = NativeCallable<_WndProcNative>.isolateLocal(
    wndProc,
    exceptionalReturn: 0,
  );

  final wc = calloc<_Wndclassexw>();
  final filter = calloc<_DevBroadcastDeviceInterface>();
  final msg = calloc<_Msg>();
  try {
    final hInstance = getModuleHandleW(nullptr);
    wc.ref
      ..cbSize = sizeOf<_Wndclassexw>()
      ..lpfnWndProc = callback.nativeFunction
      ..hInstance = hInstance
      ..lpszClassName = className;
    if (registerClassExW(wc) == 0) {
      mainSend.send('error');
      return;
    }

    hwnd = createWindowExW(
      0,
      className,
      nullptr,
      0,
      0,
      0,
      0,
      0,
      nullptr,
      nullptr,
      hInstance,
      nullptr,
    );
    if (hwnd == nullptr) {
      mainSend.send('error');
      return;
    }

    filter.ref
      ..dbccSize = sizeOf<_DevBroadcastDeviceInterface>()
      ..dbccDeviceType = _dbtDevtypDeviceInterface
      ..dbccReserved = 0;
    notify = registerDeviceNotificationW(
      hwnd,
      filter.cast(),
      _deviceNotifyWindowHandle | _deviceNotifyAllInterfaceClasses,
    );

    // Hand the window handle to the main isolate so it can post WM_CLOSE.
    mainSend.send(hwnd.address);

    while (getMessageW(msg, nullptr, 0, 0) > 0) {
      translateMessage(msg);
      dispatchMessageW(msg);
    }
  } finally {
    if (notify != nullptr) unregisterDeviceNotification(notify);
    if (hwnd != nullptr) destroyWindow(hwnd);
    callback.close();
    calloc.free(wc);
    calloc.free(filter);
    calloc.free(msg);
    malloc.free(className);
  }
}
