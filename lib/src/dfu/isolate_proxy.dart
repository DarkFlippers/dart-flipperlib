// Port-based proxy that lets the recovery isolate use a DfuUsbBackend owned by
// the main isolate. Every call is one request with its own reply port; the
// worker awaits the reply, so requests never interleave from one caller.
// Failures travel as (failure, message) pairs and are rethrown as
// DfuHostException on the worker side.
import 'dart:async';
import 'dart:isolate';

import 'backend.dart';

sealed class DfuProxyRequest {
  const DfuProxyRequest(this.reply);
  final SendPort reply;
}

class DfuProxyIsPresent extends DfuProxyRequest {
  const DfuProxyIsPresent(super.reply);
}

class DfuProxyWaitPresence extends DfuProxyRequest {
  const DfuProxyWaitPresence(super.reply, this.present, this.timeout);
  final bool present;
  final Duration timeout;
}

class DfuProxyAcquire extends DfuProxyRequest {
  const DfuProxyAcquire(super.reply);
}

class DfuProxyRelease extends DfuProxyRequest {
  const DfuProxyRelease(super.reply, this.ref);
  final DfuDeviceRef ref;
}

class DfuProxyResponse {
  const DfuProxyResponse.ok(this.value) : failure = null, error = null;
  const DfuProxyResponse.failed(this.failure, this.error) : value = null;

  final Object? value;
  final DfuHostFailure? failure;
  final String? error;
}

/// Main-isolate end: serves requests against [backend] until [close].
class DfuProxyServer {
  DfuProxyServer(this.backend) {
    _port.listen(_serve);
  }

  final DfuUsbBackend backend;
  final ReceivePort _port = ReceivePort('flipper-dfu-proxy');

  SendPort get sendPort => _port.sendPort;

  void close() => _port.close();

  Future<void> _serve(dynamic message) async {
    if (message is! DfuProxyRequest) return;
    DfuProxyResponse response;
    try {
      Object? value;
      switch (message) {
        case DfuProxyIsPresent():
          value = await backend.isPresent();
        case DfuProxyWaitPresence(:final present, :final timeout):
          value = await backend.waitPresence(present, timeout);
        case DfuProxyAcquire():
          value = await backend.acquire();
        case DfuProxyRelease(:final ref):
          await backend.release(ref);
      }
      response = DfuProxyResponse.ok(value);
    } on DfuHostException catch (e) {
      response = DfuProxyResponse.failed(e.failure, e.message);
    } catch (e) {
      response = DfuProxyResponse.failed(DfuHostFailure.other, e.toString());
    }
    message.reply.send(response);
  }
}

/// Worker-isolate end: a DfuUsbBackend whose every call is a round trip to
/// the server. [presence] is intentionally unsupported — waits go through
/// [waitPresence], which the server answers from its own subscription.
class DfuProxyClient implements DfuUsbBackend {
  DfuProxyClient(this._server);

  final SendPort _server;

  @override
  bool get available => true;

  @override
  Stream<bool> get presence =>
      throw UnsupportedError('presence is served on the main isolate');

  @override
  Future<bool> isPresent() async =>
      await _call((reply) => DfuProxyIsPresent(reply)) as bool;

  @override
  Future<bool> waitPresence(bool present, Duration timeout) async =>
      await _call((reply) => DfuProxyWaitPresence(reply, present, timeout))
          as bool;

  @override
  Future<DfuDeviceRef?> acquire() async =>
      await _call((reply) => DfuProxyAcquire(reply)) as DfuDeviceRef?;

  @override
  Future<void> release(DfuDeviceRef ref) async {
    await _call((reply) => DfuProxyRelease(reply, ref));
  }

  Future<Object?> _call(DfuProxyRequest Function(SendPort reply) build) async {
    final reply = ReceivePort();
    try {
      _server.send(build(reply.sendPort));
      final response = await reply.first as DfuProxyResponse;
      final failure = response.failure;
      if (failure != null) {
        throw DfuHostException(failure, response.error ?? failure.name);
      }
      return response.value;
    } finally {
      reply.close();
    }
  }
}
