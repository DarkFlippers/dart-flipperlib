import 'dart:typed_data';

import '../common/log.dart';
import '../proto/generated/flipper.pb.dart';

class RpcProtocol {
  static Uint8List encode(Main message) {
    final payload = message.writeToBuffer();
    final prefix = _encodeVarint(payload.length);
    final buffer = Uint8List(prefix.length + payload.length);
    buffer.setRange(0, prefix.length, prefix);
    buffer.setRange(prefix.length, buffer.length, payload);
    return buffer;
  }

  static List<int> _encodeVarint(int value) {
    final bytes = <int>[];
    while (value > 0x7F) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);
    return bytes;
  }
}

class FrameBufferPushResult {
  FrameBufferPushResult(this.frames, this.pendingState);
  final List<Main> frames;
  final FrameBufferPendingState? pendingState;
}

class FrameBufferPendingState {
  FrameBufferPendingState({
    required this.bytesInBuffer,
    required this.varintComplete,
    required this.declaredLength,
    required this.bytesAvailableForPayload,
    required this.bytesNeeded,
    required this.headerHex,
  });
  final int bytesInBuffer;
  final bool varintComplete;
  final int? declaredLength;
  final int? bytesAvailableForPayload;
  final int? bytesNeeded;
  final String headerHex;

  @override
  String toString() {
    if (!varintComplete) {
      return 'partial varint, bytesInBuffer=$bytesInBuffer head=$headerHex';
    }
    return 'waiting payload: declared=$declaredLength '
        'have=$bytesAvailableForPayload need=$bytesNeeded '
        'bytesInBuffer=$bytesInBuffer head=$headerHex';
  }
}

class FrameBuffer {
  static const _initialCapacity = 512;
  static const _shrinkThreshold = 8192;
  Uint8List _buf = Uint8List(_initialCapacity);
  int _writePos = 0;
  int _readPos = 0;

  void _makeRoom(int needed) {
    if (_writePos + needed <= _buf.length) return;
    if (_readPos > 0) {
      final unread = _writePos - _readPos;
      _buf.setRange(0, unread, _buf, _readPos);
      _writePos = unread;
      _readPos = 0;
      if (_writePos + needed <= _buf.length) return;
    }
    var cap = _buf.length;
    while (cap < _writePos + needed) {
      cap *= 2;
    }
    final next = Uint8List(cap);
    next.setRange(0, _writePos, _buf);
    _buf = next;
  }

  FrameBufferPushResult push(
    List<int> chunk, {
    void Function(Object error)? onParseError,
  }) {
    _makeRoom(chunk.length);
    _buf.setRange(_writePos, _writePos + chunk.length, chunk);
    _writePos += chunk.length;

    final messages = <Main>[];
    while (true) {
      final frame = _tryParse(onParseError);
      if (frame == null) break;
      messages.add(frame);
    }
    if (_readPos == _writePos) {
      _readPos = 0;
      _writePos = 0;
      // Fully drained: release the capacity a peak frame forced (the buffer
      // would otherwise hold up to ~128 KB for the rest of the session).
      if (_buf.length > _shrinkThreshold) {
        _buf = Uint8List(_initialCapacity);
      }
    } else if (_readPos > 4096) {
      final unread = _writePos - _readPos;
      _buf.setRange(0, unread, _buf, _readPos);
      _writePos = unread;
      _readPos = 0;
    }

    FrameBufferPendingState? pending;
    // Diagnostics only (hex preview + varint walk): never burn this on the
    // RX hot path in release builds.
    if (Log.debugOn && _readPos < _writePos) {
      pending = _describePending();
    }
    return FrameBufferPushResult(messages, pending);
  }

  FrameBufferPendingState _describePending() {
    final available = _writePos - _readPos;
    final previewLen = available < 16 ? available : 16;
    final preview = _buf.sublist(_readPos, _readPos + previewLen);
    final hex = preview
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    var length = 0;
    var shift = 0;
    var offset = _readPos;
    var varintComplete = false;
    while (offset < _writePos) {
      final byte = _buf[offset++];
      length |= (byte & 0x7F) << shift;
      shift += 7;
      if ((byte & 0x80) == 0) {
        varintComplete = true;
        break;
      }
      if (shift >= 35) break;
    }

    if (!varintComplete) {
      return FrameBufferPendingState(
        bytesInBuffer: available,
        varintComplete: false,
        declaredLength: null,
        bytesAvailableForPayload: null,
        bytesNeeded: null,
        headerHex: hex,
      );
    }
    final payloadAvail = _writePos - offset;
    final need = length - payloadAvail;
    return FrameBufferPendingState(
      bytesInBuffer: available,
      varintComplete: true,
      declaredLength: length,
      bytesAvailableForPayload: payloadAvail,
      bytesNeeded: need > 0 ? need : 0,
      headerHex: hex,
    );
  }

  void clear() {
    _writePos = 0;
    _readPos = 0;
  }

  Main? _tryParse(void Function(Object error)? onParseError) {
    if (_readPos >= _writePos) return null;

    var length = 0;
    var shift = 0;
    var offset = _readPos;

    while (offset < _writePos) {
      final byte = _buf[offset++];
      length |= (byte & 0x7F) << shift;
      shift += 7;

      if ((byte & 0x80) == 0) {
        if (length > 65536) {
          Log.error(
            '[FrameBuffer] bad varint length=$length '
            '(0x${_buf[_readPos].toRadixString(16)}), dropping first byte',
          );
          _readPos += 1;
          onParseError?.call(
            FormatException('Bad protobuf varint length: $length'),
          );
          return null;
        }
        if (length == 0) {
          // The firmware never sends an empty Main; a zero-length frame is
          // noise (e.g. a stray 0x00 after desync) and must count toward the
          // desync streak instead of resetting it with a fake empty message.
          Log.error('[FrameBuffer] empty frame, dropping first byte');
          _readPos += 1;
          onParseError?.call(
            const FormatException('Zero-length protobuf frame'),
          );
          return null;
        }
        if (_writePos < offset + length) return null;

        final payload = _buf.sublist(offset, offset + length);
        _readPos = offset + length;

        try {
          return Main.fromBuffer(payload);
        } catch (error) {
          Log.error(
            '[FrameBuffer] protobuf parse error (length=$length): $error',
          );
          onParseError?.call(error);
          return null;
        }
      }

      if (shift >= 35) {
        Log.error(
          '[FrameBuffer] varint overflow, dropping first byte '
          '(0x${_buf[_readPos].toRadixString(16)})',
        );
        _readPos += 1;
        onParseError?.call(const FormatException('Protobuf varint overflow'));
        return null;
      }
    }

    return null;
  }
}
