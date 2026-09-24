import 'package:flipperlib/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flipperlib/src/model/enums.dart';
import 'package:flipperlib/src/session/queue.dart';

/// The two settle-exactly-once objects the RPC session is built on.
///
/// `QueuedRequest` is a frame waiting for the transport; `PendingRpc` is the
/// call already on the wire. Both promise to settle once, and both are
/// reachable from more than one place — a drop, a timeout and a normal
/// completion can all arrive for the same call.
///
/// Neither needs a device: they are data and a timer.
Main frame(int commandId) => Main()..commandId = commandId;

QueuedRequest request({
  int seq = 0,
  FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  void Function()? onSent,
  void Function(Object error)? onError,
}) => QueuedRequest(
  frame: frame(seq),
  priority: priority,
  seq: seq,
  holdsTxUntilAnswer: false,
  onSent: onSent,
  onError: onError,
);

void main() {
  group('the order frames leave in', () {
    test('is by priority before it is by arrival', () {
      final later = request(seq: 99, priority: FlipperRequestPriority.rightNow);
      final earlier = request(
        seq: 1,
        priority: FlipperRequestPriority.background,
      );

      expect(
        later.compareTo(earlier),
        lessThan(0),
        reason: 'rightNow outranks background however long it has waited',
      );
    });

    test('is by arrival when the priority is the same', () {
      final first = request(seq: 1);
      final second = request(seq: 2);

      expect(first.compareTo(second), lessThan(0));
      expect(second.compareTo(first), greaterThan(0));
      expect(first.compareTo(request(seq: 1)), 0);
    });

    // The enum's declaration order is the priority order. A reordering there
    // is invisible at every call site and changes what goes out first.
    test('follows the order the priorities are declared in', () {
      final queue = [
        request(seq: 4, priority: FlipperRequestPriority.background),
        request(seq: 3, priority: FlipperRequestPriority.unattended),
        request(seq: 2, priority: FlipperRequestPriority.foreground),
        request(seq: 1, priority: FlipperRequestPriority.rightNow),
      ]..sort();

      expect(queue.map((r) => r.priority), [
        FlipperRequestPriority.rightNow,
        FlipperRequestPriority.foreground,
        FlipperRequestPriority.unattended,
        FlipperRequestPriority.background,
      ]);
    });

    test('keeps arrival order inside one priority', () {
      final queue = [request(seq: 3), request(seq: 1), request(seq: 2)]..sort();

      expect(queue.map((r) => r.seq), [1, 2, 3]);
    });
  });

  group('a queued frame', () {
    test('reports being sent once', () {
      var sent = 0;
      final r = request(onSent: () => sent++);

      r.markSent();
      r.markSent();

      expect(sent, 1);
    });

    test('reports failing once', () {
      var failed = 0;
      final r = request(onError: (_) => failed++);

      r.fail(Exception('first'));
      r.fail(Exception('second'));

      expect(failed, 1);
    });

    // Both of these really happen: a frame reaches the transport and the link
    // then drops, or a drop is noticed while the frame is still queued. The
    // caller must hear one outcome, not two.
    test('does not fail after it has been sent', () {
      var sent = 0;
      var failed = 0;
      final r = request(onSent: () => sent++, onError: (_) => failed++);

      r.markSent();
      r.fail(Exception('link dropped after the frame went out'));

      expect(sent, 1);
      expect(failed, 0);
    });

    test('does not report being sent after it has failed', () {
      var sent = 0;
      var failed = 0;
      final r = request(onSent: () => sent++, onError: (_) => failed++);

      r.fail(Exception('dropped while queued'));
      r.markSent();

      expect(failed, 1);
      expect(sent, 0);
    });

    test('carries the error to the caller', () {
      Object? seen;
      final r = request(onError: (e) => seen = e);
      final boom = StateError('no transport');

      r.fail(boom);

      expect(seen, same(boom));
    });

    test('settles without callbacks', () {
      expect(() => request().markSent(), returnsNormally);
      expect(() => request().fail(Exception('x')), returnsNormally);
    });
  });

  group('a call on the wire', () {
    test('hands back the frames it collected', () async {
      final rpc = PendingRpc(7)
        ..add(frame(1))
        ..add(frame(2));

      rpc.complete();

      expect((await rpc.future).map((f) => f.commandId), [1, 2]);
      expect(rpc.frameCount, 2);
    });

    test('hands back a list the caller cannot change', () async {
      final rpc = PendingRpc(7)..add(frame(1));
      rpc.complete();

      final frames = await rpc.future;
      expect(() => frames.add(frame(2)), throwsUnsupportedError);
    });

    test('completes once', () async {
      final rpc = PendingRpc(7)..add(frame(1));

      rpc.complete();
      rpc.complete();
      rpc.completeError(Exception('too late'));

      expect((await rpc.future), hasLength(1));
    });

    test('does not complete after an error', () async {
      final rpc = PendingRpc(7);
      final boom = StateError('link dropped');

      rpc.completeError(boom);
      rpc.complete();

      await expectLater(rpc.future, throwsA(same(boom)));
    });

    // The TX worker waits on `settled` without a try/catch, so it must resolve
    // on both outcomes and never carry the error.
    test('settles on success and on failure, and never errors', () async {
      final ok = PendingRpc(1)..complete();
      await expectLater(ok.settled, completes);

      final bad = PendingRpc(2)..completeError(Exception('dropped'));
      await expectLater(bad.settled, completes);
      // Consume the rejection so the zone does not see it as unhandled.
      await bad.future.catchError((Object _) => <Main>[]);
    });

    // Large transfers would otherwise hold every protobuf frame until the
    // call finishes.
    test('can count frames without keeping them', () async {
      final seen = <int>[];
      final rpc = PendingRpc(7)
        ..retainFrames = false
        // Not part of the cascade: a `..` after a lambda body attaches to the
        // lambda's own expression, not to rpc.
        ..onFrame = ((f) => seen.add(f.commandId));

      rpc
        ..add(frame(1))
        ..add(frame(2))
        ..complete();

      expect(await rpc.future, isEmpty, reason: 'nothing was retained');
      expect(rpc.frameCount, 2, reason: 'but both were counted');
      expect(seen, [1, 2], reason: 'and both were delivered');
    });

    // A progress handler that throws must not cost the rest of the chunk.
    test('keeps routing frames when a callback throws', () {
      var delivered = 0;
      final rpc = PendingRpc(7)
        ..onFrame = (_) {
          delivered++;
          throw StateError('a progress handler blew up');
        };

      expect(() => rpc.add(frame(1)), returnsNormally);
      expect(() => rpc.add(frame(2)), returnsNormally);

      expect(delivered, 2);
      expect(rpc.frameCount, 2);
    });
  });

  group('the response watchdog', () {
    test('fires when nothing answers', () async {
      var fired = 0;
      PendingRpc(7).armTimeout(const Duration(milliseconds: 10), () => fired++);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fired, 1);
    });

    test('does not fire once the call has completed', () async {
      var fired = 0;
      final rpc = PendingRpc(7)
        ..armTimeout(const Duration(milliseconds: 10), () => fired++);

      rpc.complete();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fired, 0);
    });

    test('is cancelled on request', () async {
      var fired = 0;
      PendingRpc(7)
        ..armTimeout(const Duration(milliseconds: 10), () => fired++)
        ..cancelTimeout();

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fired, 0);
    });

    // Every answered frame restarts the clock, so a long transfer that keeps
    // producing frames is not killed by a deadline meant for silence.
    test('starts again on a re-arm', () async {
      var fired = 0;
      final rpc = PendingRpc(7)
        ..armTimeout(const Duration(milliseconds: 40), () => fired++);

      await Future<void>.delayed(const Duration(milliseconds: 25));
      rpc.rearmTimeout();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(fired, 0, reason: 'the re-arm moved the deadline out');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fired, 1, reason: 'and it still fires when silence continues');
    });

    test('does nothing on a re-arm that was never armed', () async {
      expect(() => PendingRpc(7).rearmTimeout(), returnsNormally);
    });
  });
}
