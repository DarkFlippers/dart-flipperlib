import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

class DesktopUsbIsolateConfig {
  final String portName;
  final SendPort eventPort;
  const DesktopUsbIsolateConfig(this.portName, this.eventPort);
}

class DesktopUsbWriteRequest {
  final Uint8List bytes;
  final int seq;
  const DesktopUsbWriteRequest(this.bytes, this.seq);
}

class DesktopUsbDtrPulse {
  const DesktopUsbDtrPulse();
}

class DesktopUsbShutdown {
  const DesktopUsbShutdown();
}

class DesktopUsbReady {
  final SendPort commandPort;
  const DesktopUsbReady(this.commandPort);
}

class DesktopUsbBytes {
  final Uint8List bytes;
  const DesktopUsbBytes(this.bytes);
}

class DesktopUsbWriteAck {
  final int seq;
  final String? error;
  const DesktopUsbWriteAck(this.seq, this.error);
}

class DesktopUsbFault {
  final String message;
  const DesktopUsbFault(this.message);
}

class DesktopUsbExited {
  const DesktopUsbExited();
}

void desktopUsbIsolateEntry(DesktopUsbIsolateConfig config) {
  final commandPort = ReceivePort();
  final SerialPort port;
  try {
    port = SerialPort(config.portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError?.message;
      final details = error == null ? '' : ': $error';
      config.eventPort.send(
        DesktopUsbFault('Failed to open ${config.portName}$details'),
      );
      config.eventPort.send(const DesktopUsbExited());
      commandPort.close();
      return;
    }
    final cfg = SerialPortConfig()
      ..baudRate = 230400
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none;
    cfg.setFlowControl(SerialPortFlowControl.none);
    // Windows' usbser.sys does not assert DTR/RTS on open and the Flipper
    // firmware gates its CLI on DTR — without this, writes complete but the
    // device never answers. Harmless on macOS/Linux. Set after
    // setFlowControl, which resets both lines.
    cfg.dtr = SerialPortDtr.on;
    cfg.rts = SerialPortRts.on;
    port.config = cfg;
  } catch (e) {
    final error = SerialPort.lastError?.message;
    final details = error == null ? '$e' : '$e ($error)';
    config.eventPort.send(DesktopUsbFault('Open error: $details'));
    config.eventPort.send(const DesktopUsbExited());
    commandPort.close();
    return;
  }

  var shuttingDown = false;
  // Read-loop pacing: fast 5 ms reads while traffic flows (low latency),
  // backing off to 50 ms after ~64 consecutive empty reads so an idle open
  // port does not spin at ~200 syscalls/s burning CPU and battery. Any write
  // resets to fast mode so the response is picked up promptly.
  var idleReads = 0;

  void shutdown() {
    if (shuttingDown) return;
    shuttingDown = true;
    try {
      port.close();
    } catch (_) {}
    try {
      port.dispose();
    } catch (_) {}
    commandPort.close();
    config.eventPort.send(const DesktopUsbExited());
  }

  config.eventPort.send(DesktopUsbReady(commandPort.sendPort));

  commandPort.listen((message) {
    if (shuttingDown) return;
    if (message is DesktopUsbWriteRequest) {
      idleReads = 0;
      try {
        var offset = 0;
        while (offset < message.bytes.length) {
          final slice = offset == 0
              ? message.bytes
              : Uint8List.sublistView(message.bytes, offset);
          final n = port.write(slice, timeout: 5000);
          if (n <= 0) {
            config.eventPort.send(
              DesktopUsbWriteAck(message.seq, 'write returned $n at offset $offset'),
            );
            return;
          }
          offset += n;
        }
        config.eventPort.send(DesktopUsbWriteAck(message.seq, null));
      } catch (e) {
        config.eventPort.send(DesktopUsbWriteAck(message.seq, e.toString()));
      }
    } else if (message is DesktopUsbDtrPulse) {
      try {
        final c = port.config;
        c.dtr = 0;
        port.config = c;
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          if (shuttingDown) return;
          try {
            final c2 = port.config;
            c2.dtr = 1;
            port.config = c2;
          } catch (_) {}
        });
      } catch (_) {}
    } else if (message is DesktopUsbShutdown) {
      shutdown();
    }
  });

  // Blocking read loop: port.read returns as soon as data arrives (up to the
  // timeout), so response latency is much lower than timer polling.
  // await Future.delayed(Duration.zero) yields to the event loop between reads
  // so commandPort write requests can be processed without long delays (a
  // write also drops the loop back to fast pacing, see idleReads above).
  Timer(Duration.zero, () async {
    while (!shuttingDown) {
      try {
        final fast = idleReads < 64;
        final bytes = port.read(65536, timeout: fast ? 5 : 50);
        if (bytes.isNotEmpty) {
          idleReads = 0;
          config.eventPort.send(DesktopUsbBytes(Uint8List.fromList(bytes)));
        } else {
          idleReads++;
        }
      } catch (e) {
        if (!port.isOpen) {
          config.eventPort.send(DesktopUsbFault('Port closed: $e'));
          shutdown();
          break;
        }
      }
      await Future<void>.delayed(Duration.zero);
    }
  });
}
