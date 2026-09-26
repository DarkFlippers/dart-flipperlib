import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FlipperSessionBinding.unbound], and what `run` promises either way.
///
/// The binding is how work that outlives one async body goes on reaching the
/// Flipper it started against. The interesting half of that needs a live
/// session and is covered where sessions are; what is here is the half a
/// caller can reason about without one - which is also the half a consumer's
/// test now needs, since a fake client has to return a binding from
/// `bindCurrentSession` and had no way to build one.
/// Enough of a discovered device to build a [FlipperDevice] with.
class _Discovered implements DiscoveredDevice {
  const _Discovered(this.id);

  @override
  final String id;

  @override
  String get name => id;

  @override
  DeviceTransport get transport => DeviceTransport.usb;
}

void main() {
  group('a binding to nothing', () {
    const binding = FlipperSessionBinding.unbound();

    test('has no device', () {
      expect(binding.device, isNull);
    });

    test('is not alive', () {
      expect(
        binding.isAlive,
        isFalse,
        reason: 'requests under a dead binding fail rather than retarget',
      );
    });

    test('is const, so it costs nothing to hand back', () {
      expect(
        identical(
          const FlipperSessionBinding.unbound(),
          const FlipperSessionBinding.unbound(),
        ),
        isTrue,
      );
    });
  });

  group('a binding that names a device', () {
    final target = FlipperDevice(
      id: 'A',
      name: 'Kitchen',
      link: FlipperLink.usb,
      source: _Discovered('A'),
    );
    final binding = FlipperSessionBinding.to(target);

    test('reports it', () {
      expect(binding.device, same(target));
    });

    test('is alive', () {
      expect(binding.isAlive, isTrue);
    });

    // It describes a device; it does not stand in for a session. A caller
    // that reads `device` to decide what to do gets an answer; a request made
    // inside `run` is bound to nothing, because there is nothing to bind to.
    test('still runs a body, and still returns its value', () {
      expect(binding.run(() => 'ran'), 'ran');
    });
  });

  group('run', () {
    const binding = FlipperSessionBinding.unbound();

    test('hands back what the body returned', () {
      expect(binding.run(() => 7), 7);
    });

    test('keeps the body synchronous when it is', () {
      var ran = false;
      binding.run(() => ran = true);
      expect(ran, isTrue, reason: 'not deferred to a microtask');
    });

    test('lets a throw out', () {
      expect(
        () => binding.run(() => throw StateError('from the body')),
        throwsStateError,
      );
    });

    test('hands back a future the caller can await', () async {
      final value = await binding.run(() async => 7);
      expect(value, 7);
    });

    // The zone is entered for the body and left with it; a task that binds
    // must not leave the next one bound to its session.
    test('does not outlive the body', () {
      Object? inside;
      Object? after;
      binding.run(() => inside = Zone.current);
      after = Zone.current;

      expect(inside, isNot(same(after)));
    });

    test('nests', () {
      expect(binding.run(() => binding.run(() => 'inner')), 'inner');
    });
  });
}
