import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../common/log.dart';
import '../model/enums.dart';

class FlipperTransportError implements Exception {
  final String message;

  FlipperTransportError(this.message);

  @override
  String toString() => message;
}

// Logical transport lifecycle (the byte pipe), distinct from the BLE platform
// link state `BleLinkState` one layer down: `active` means writes/reads are
// allowed, regardless of how the underlying link is being established or torn
// down. Invariant across the layers: once this reaches `closed` the BLE
// subclass is always `BleLinkState.disconnected` (onTransportFault ->
// onFaultExtra -> _markBleDisconnected), so `isActive` and a live platform link
// never disagree.
enum TransportLifecycle { active, closing, closed }

// One buffered transport write. Settles exactly once.
class TransportPendingWrite {
  final Uint8List bytes;
  final Completer<void> _completer = Completer<void>();

  TransportPendingWrite(this.bytes);

  Future<void> get future => _completer.future;

  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void fail(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}

// Byte transport (BLE / USB serial). Writes are serialized: rawWrite never
// runs concurrently. An unexpected death goes through onTransportFault exactly
// once: pending writes fail, bytesStream closes without an error event, and
// closeReason keeps the diagnosis. close() is the orderly path and never
// throws.
abstract class Transport {
  static const int bleChunkSize = 512;

  final _bytesCtrl = StreamController<List<int>>.broadcast();
  final List<TransportPendingWrite> _writeQueue = [];
  bool _writePumpRunning = false;
  TransportLifecycle _lifecycle = TransportLifecycle.active;
  Object? _closeReason;

  Stream<List<int>> get bytesStream => _bytesCtrl.stream;

  bool get isClosed => _lifecycle == TransportLifecycle.closed;

  bool get isActive => _lifecycle == TransportLifecycle.active;

  Object? get closeReason => _closeReason;

  void addBytes(List<int> bytes) {
    if (!isActive || _bytesCtrl.isClosed) return;
    _bytesCtrl.add(bytes);
  }

  bool get supportsCli;

  FlipperMode get initialMode;

  int get storageChunkSize => bleChunkSize;

  int get maxWriteBatchSize => bleChunkSize;

  Future<void> open();

  Future<void> write(Uint8List bytes) {
    if (!isActive) {
      return Future.error(StateError('Transport closed'));
    }
    final pending = TransportPendingWrite(bytes);
    _writeQueue.add(pending);
    _startWritePump();
    return pending.future;
  }

  void _startWritePump() {
    if (_writePumpRunning) return;
    _writePumpRunning = true;
    unawaited(_runWritePump());
  }

  Future<void> _runWritePump() async {
    while (_writeQueue.isNotEmpty) {
      final pending = _writeQueue.removeAt(0);
      if (!isActive) {
        pending.fail(StateError('Transport closed'));
        continue;
      }
      try {
        await rawWrite(pending.bytes);
        pending.complete();
      } catch (error) {
        pending.fail(error);
      }
    }
    _writePumpRunning = false;
  }

  Future<void> rawWrite(Uint8List bytes);

  Future<void> writeAscii(String text) =>
      write(Uint8List.fromList(ascii.encode(text)));

  Future<void> nudgeCli();

  void _failPendingWrites(Object error) {
    while (_writeQueue.isNotEmpty) {
      _writeQueue.removeAt(0).fail(error);
    }
  }

  void onTransportFault(Object reason) {
    if (_lifecycle == TransportLifecycle.closed) return;
    _lifecycle = TransportLifecycle.closed;
    _closeReason = reason;
    Log.error('[Transport] fault: $reason');
    _failPendingWrites(reason);
    onFaultExtra(reason);
    if (!_bytesCtrl.isClosed) {
      _bytesCtrl.close();
    }
  }

  // Releases platform resources and wakes internal waiters after a fault.
  // Must not throw.
  void onFaultExtra(Object error) {}

  Future<void> close() async {
    if (_lifecycle != TransportLifecycle.active) return;
    _lifecycle = TransportLifecycle.closing;
    _failPendingWrites(StateError('Transport closed'));
    try {
      await doClose();
    } catch (e) {
      Log.error('[Transport] doClose error: $e');
    }
    _lifecycle = TransportLifecycle.closed;
    if (!_bytesCtrl.isClosed) {
      await _bytesCtrl.close();
    }
  }

  Future<void> doClose();
}

// Completes a one-shot wake-up signal if it is armed and not already fired.
// Shared by the client and the BLE transport, which both juggle several
// `Completer<void>?` signals (queue, scan-phase, budget, rpc-active, disconnect,
// setup-guard) with identical fire semantics.
void fireOnce(Completer<void>? signal) {
  if (signal != null && !signal.isCompleted) signal.complete();
}
