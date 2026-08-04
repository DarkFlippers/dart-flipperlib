import 'dart:async';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import '../../common/log.dart';
import '../../model/device.dart';
import '../../model/discovered.dart';
import '../../model/enums.dart';
import '../transport.dart';
import 'platform.dart';

class AndroidUsbPlatform extends UsbPlatform {
  const AndroidUsbPlatform();

  // Native USB attach / detach broadcasts — true event-driven discovery.
  @override
  Stream<void> get usbEvents =>
      UsbSerial.usbEventStream?.map((_) {}) ?? const Stream<void>.empty();

  @override
  Future<List<FlipperDevice>> loadDevices() async {
    final devices = await UsbSerial.listDevices();
    return devices
        .map(
          (device) => FlipperDevice(
            id: '${device.vid}:${device.pid}',
            name: (device.productName?.isNotEmpty == true)
                ? device.productName!
                : 'USB VID:0x${device.vid?.toRadixString(16) ?? '?'} PID:0x${device.pid?.toRadixString(16) ?? '?'}',
            link: FlipperLink.usb,
            source: AndroidUsbDiscoveredDevice(device),
            vendorId: device.vid,
            productId: device.pid,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Transport> openTransport(UsbDiscoveredDevice device) {
    if (device is! AndroidUsbDiscoveredDevice) {
      throw UnsupportedError(
        'Android USB transport requires Android USB device',
      );
    }
    return AndroidUsbTransport.create(device);
  }
}

class AndroidUsbTransport extends Transport {
  final UsbPort _port;
  StreamSubscription<Uint8List>? _inputSub;

  AndroidUsbTransport._(this._port);

  static Future<AndroidUsbTransport> create(
    AndroidUsbDiscoveredDevice device,
  ) async {
    final port = await device.usbDevice.create();
    if (port == null) {
      throw StateError('USB permission denied or port unavailable');
    }
    final opened = await port.open();
    if (!opened) {
      throw StateError('Failed to open USB port');
    }
    await port.setPortParameters(
      230400,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    return AndroidUsbTransport._(port);
  }

  @override
  bool get supportsCli => true;

  @override
  FlipperMode get initialMode => FlipperMode.cli;

  @override
  int get storageChunkSize => 1024;

  @override
  Future<void> open() async {
    _inputSub = _port.inputStream?.listen(
      addBytes,
      onError: (Object error, StackTrace stackTrace) {
        Log.error('[FlipperClient] Android USB read error: $error');
        onTransportFault(error);
      },
      onDone: () {
        onTransportFault(StateError('USB input stream closed'));
      },
    );
  }

  @override
  Future<void> rawWrite(Uint8List bytes) async {
    if (!isActive) {
      throw StateError('Transport closed');
    }
    try {
      // The plugin offers no write timeout of its own; a hung native write
      // would block the TX worker forever and with it every queued request.
      await _port.write(bytes).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      final error = FlipperTransportError(
        'Android USB write timed out (${bytes.length} bytes); '
        'port presumed dead',
      );
      onTransportFault(error);
      throw error;
    }
  }

  @override
  Future<void> nudgeCli() async {
    if (!isActive) {
      throw StateError('Transport closed');
    }
    await _port.setDTR(false);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _port.setDTR(true);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await writeAscii('\r');
  }

  @override
  Future<void> doClose() async {
    await _inputSub?.cancel();
    _inputSub = null;
    try {
      await _port.close();
    } catch (e) {
      Log.error('[FlipperClient] Android USB close error: $e');
    }
  }
}
