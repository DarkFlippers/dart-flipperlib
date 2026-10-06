import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flipperlib/src/model/enums.dart';
import 'package:flipperlib/src/transport/usb/isolate.dart';
import 'package:flipperlib/src/transport/usb/link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Does the USB transport actually hand the serial port back?
///
/// Behavioural, against the real `SerialUsbTransportBase`, because the first
/// attempt at this was a source assertion that grepped `onFaultExtra` for the
/// text `_release()` - and the span it searched included a sixteen-line comment
/// that says `_release()`, so replacing the call with `// TODO: call _release()`
/// passed. It also could not see the defect that mattered: the release *was*
/// called, and then killed the isolate before it could act.
///
/// `SerialUsbTransportBase`'s constructor takes its four collaborators, so a
/// fake `SendPort` can record what the isolate was actually told. Only
/// `createFor` spawns anything.
class _RecordingSendPort implements SendPort {
  final messages = <Object?>[];

  @override
  void send(Object? message) => messages.add(message);

  @override
  bool operator ==(Object other) => other is _RecordingSendPort;

  @override
  int get hashCode => 0;
}

class _TestUsbTransport extends SerialUsbTransportBase {
  _TestUsbTransport(super.isolate, super.eventPort, super.events, super.port);

  @override
  bool get supportsCli => true;

  @override
  FlipperMode get initialMode => FlipperMode.cli;
}

({
  _TestUsbTransport transport,
  _RecordingSendPort commands,
  StreamController<dynamic> events,
})
build() {
  final commands = _RecordingSendPort();
  final events = StreamController<dynamic>.broadcast();
  // A real ReceivePort, because the transport closes it; nothing listens.
  final eventPort = ReceivePort();
  // An Isolate over a control port nobody services, so the transport's
  // kill() is a harmless no-op. Emphatically not Isolate.current, which would
  // have the release kill the test runner - it does, and every test in the
  // file then reports "did not complete".
  final killable = Isolate(ReceivePort().sendPort);
  final transport = _TestUsbTransport(
    killable,
    eventPort,
    events.stream,
    commands,
  );
  return (transport: transport, commands: commands, events: events);
}

void main() {
  group('a USB transport that faults', () {
    test('tells the isolate to shut the port down', () async {
      final parts = build();
      addTearDown(parts.events.close);
      await parts.transport.open();

      parts.transport.onTransportFault(StateError('write ack failed'));
      // The release waits on the isolate's own exit notice before killing it.
      parts.events.add(const DesktopUsbExited());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        parts.commands.messages.whereType<DesktopUsbShutdown>(),
        isNotEmpty,
        reason:
            'this message is the only thing that makes the isolate call '
            'port.close() and port.dispose()',
      );
    });

    // The defect the source assertion could not see. onFaultExtra used to
    // complete _exited itself, which resolved the release's wait on the next
    // microtask - so the isolate was killed microseconds after being told to
    // shut down, before it could dequeue the message. A killed Dart isolate
    // runs no C-level cleanup, so the handle leaked to the process, and with
    // the isolate dead nothing could ever ask again.
    test('waits for the isolate before giving up on it', () async {
      final parts = build();
      addTearDown(parts.events.close);
      await parts.transport.open();

      parts.transport.onTransportFault(StateError('write ack failed'));
      // Nothing has confirmed the isolate is gone yet.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        parts.transport.releaseFinished,
        isFalse,
        reason: 'killing it now is what leaked the port',
      );

      parts.events.add(const DesktopUsbExited());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        parts.transport.releaseFinished,
        isTrue,
        reason: 'and once it has confirmed, the release completes',
      );
    });

    test('releases once, however many faults arrive', () async {
      final parts = build();
      addTearDown(parts.events.close);
      await parts.transport.open();

      parts.transport.onTransportFault(StateError('first'));
      parts.transport.onTransportFault(StateError('second'));
      parts.events.add(const DesktopUsbExited());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await parts.transport.close();

      expect(
        parts.commands.messages.whereType<DesktopUsbShutdown>().length,
        1,
        reason: 'a fault, a repeat fault and a close all reach the release',
      );
    });

    test('an in-flight write is failed, not left hanging', () async {
      final parts = build();
      addTearDown(parts.events.close);
      await parts.transport.open();

      final write = parts.transport.rawWrite(Uint8List.fromList(const [1, 2]));
      parts.transport.onTransportFault(StateError('link dropped'));

      await expectLater(write, throwsA(isA<StateError>()));
    });
  });

  group('a USB transport closed in order', () {
    test('also tells the isolate to shut the port down', () async {
      final parts = build();
      addTearDown(parts.events.close);
      await parts.transport.open();

      final closing = parts.transport.close();
      parts.events.add(const DesktopUsbExited());
      await closing;

      expect(
        parts.commands.messages.whereType<DesktopUsbShutdown>(),
        isNotEmpty,
      );
      expect(parts.transport.isClosed, isTrue);
    });
  });
}
