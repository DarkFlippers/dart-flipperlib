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

// What the OS said about a failed open, code included.
//
// The message alone is not diagnostic and has sent us down the wrong path
// before. libserialport reads `lastError` as a live GetLastError() after the
// fact, and every failure path in sp_open that gets past CreateFile calls
// sp_close() first - which succeeds and clobbers it. So a port genuinely held
// by someone reports "Access is denied." (5), while a configuration IOCTL
// failing on a half-ready device reports *success* (0). Without the number
// those are indistinguishable, and so are "held by another process", "device
// unplugged" and "device still enumerating":
//
//   5 - held by someone, us included
//   2 - the device is gone
//   0 - the open got past CreateFile; a config call failed. Not ready.
String _lastOpenError() {
  final error = SerialPort.lastError;
  if (error == null) return '';
  // Not `message.isEmpty`: on Windows FormatMessageA(0) returns a non-empty
  // "The operation completed successfully.", which is why the code matters.
  return ': ${error.message} (code ${error.errorCode})';
}

void desktopUsbIsolateEntry(DesktopUsbIsolateConfig config) {
  final commandPort = ReceivePort();
  final SerialPort port;
  // Mirrors `port` for the catch below, which cannot read a final that the
  // constructor itself might have thrown before assigning.
  SerialPort? constructed;
  try {
    port = SerialPort(config.portName);
    constructed = port;
    if (!port.openReadWrite()) {
      final details = _lastOpenError();
      // Nothing to close - libserialport's own sp_open already ran sp_close on
      // every path that returns false - but the sp_port struct is ours.
      try {
        port.dispose();
      } catch (_) {}
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
    final details = '$e${_lastOpenError()}';
    // The handle is open by this point: openReadWrite() succeeded and the throw
    // came from configuring the port (`port.config = cfg` goes through
    // Util.call, which throws). Returning without closing left the OS handle
    // held with nothing referencing it - so the next open of the same COM port
    // was refused by our own orphan. Best-effort, and legitimately so: nothing
    // is waiting on it and the isolate is about to end either way.
    try {
      constructed?.close();
    } catch (_) {}
    try {
      constructed?.dispose();
    } catch (_) {}
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
              DesktopUsbWriteAck(
                message.seq,
                'write returned $n at offset $offset',
              ),
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
