import 'dart:async';
import 'dart:typed_data';

import '../../../protobuf.dart';
import '../../common/log.dart';
import '../../model/device.dart';
import '../../model/enums.dart';
import '../../model/exceptions.dart';
import '../../transport/ble/ble.dart';
import '../../transport/transport.dart';
import '../client.dart';

extension FlipperStorageApi on FlipperClient {
  Future<FlipperRpcBatch<ListResponse>> storageList(
    ListRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(storageListRequest: request),
      (frame) =>
          frame.hasStorageListResponse() ? frame.storageListResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<ReadResponse>> storageRead(
    ReadRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(storageReadRequest: request),
      (frame) =>
          frame.hasStorageReadResponse() ? frame.storageReadResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  /// Reads [path], reporting incremental progress as response frames arrive.
  /// When [expectedSize] is > 0 (e.g. the size from a prior directory listing),
  /// [onProgress] is called with a 0..1 ratio of bytes received; it always
  /// fires once with 1.0 on completion. Returns the assembled file bytes.
  Future<List<int>> storageReadChunked(
    String path, {
    int expectedSize = 0,
    void Function(double progress)? onProgress,
    Duration timeout = const Duration(minutes: 5),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) async {
    // Data is collected per frame into a byte builder and the frames are not
    // retained: holding every protobuf frame plus a growable List<int> copy
    // multiplied a large file's footprint by an order of magnitude.
    final bytes = BytesBuilder(copy: true);
    await callRpcFrames(
      Main(storageReadRequest: ReadRequest(path: path)),
      timeout: timeout,
      priority: priority,
      retainFrames: false,
      onFrame: (frame) {
        if (!frame.hasStorageReadResponse()) return;
        final resp = frame.storageReadResponse;
        if (!resp.hasFile()) return;
        bytes.add(resp.file.data);
        if (expectedSize > 0) {
          onProgress?.call((bytes.length / expectedSize).clamp(0.0, 1.0));
        }
      },
    );
    onProgress?.call(1.0);
    return bytes.takeBytes();
  }

  Future<List<Main>> storageWrite(
    WriteRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.background,
  }) {
    return callRpcFrames(
      Main(storageWriteRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> storageDelete(
    DeleteRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(storageDeleteRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> storageMkdir(
    MkdirRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(storageMkdirRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<Md5sumResponse>> storageMd5sum(
    Md5sumRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(storageMd5sumRequest: request),
      (frame) =>
          frame.hasStorageMd5sumResponse() ? frame.storageMd5sumResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<StatResponse>> storageStat(
    StatRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(storageStatRequest: request),
      (frame) =>
          frame.hasStorageStatResponse() ? frame.storageStatResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<InfoResponse>> storageInfo(
    InfoRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(storageInfoRequest: request),
      (frame) =>
          frame.hasStorageInfoResponse() ? frame.storageInfoResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> storageRename(
    RenameRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(storageRenameRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> storageBackupCreate(
    BackupCreateRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.background,
  }) {
    return callRpcFrames(
      Main(storageBackupCreateRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> storageBackupRestore(
    BackupRestoreRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.background,
  }) {
    return callRpcFrames(
      Main(storageBackupRestoreRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  // On modern Flipper firmware, `/int` is aliased onto the SD card, so
  // `storageInfo("/int")` returns the SD card's total/free — not the actual
  // footprint of files in the internal namespace. Use this instead to get the
  // real used-bytes count via recursive directory walk.
  Future<int> storageDu(
    String path, {
    Duration timeout = const Duration(seconds: 30),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) async {
    var total = 0;
    final queue = <String>[path];
    while (queue.isNotEmpty) {
      final dir = queue.removeLast();
      FlipperRpcBatch<ListResponse> batch;
      try {
        batch = await storageList(
          ListRequest(path: dir),
          timeout: timeout,
          priority: priority,
        );
      } catch (e) {
        Log.error('[StorageDu] list "$dir" failed: $e');
        continue;
      }
      for (final response in batch.items) {
        for (final entry in response.file) {
          if (entry.type == File_FileType.DIR) {
            final sub = dir.endsWith('/')
                ? '$dir${entry.name}'
                : '$dir/${entry.name}';
            queue.add(sub);
          } else {
            if (Log.debugOn) {
              Log.debug(
                '[StorageDu] file "$dir/${entry.name}" size=${entry.size}',
              );
            }
            total += entry.size;
          }
        }
      }
    }
    Log.info('[StorageDu] "$path" total=$total');
    return total;
  }

  Future<FlipperRpcBatch<TimestampResponse>> storageTimestamp(
    TimestampRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(storageTimestampRequest: request),
      (frame) => frame.hasStorageTimestampResponse()
          ? frame.storageTimestampResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  /// Streams [data] to [path]. The firmware opens the target with
  /// CREATE_ALWAYS, so an existing file is truncated by the first frame —
  /// deleting it beforehand is pointless. [isCancelled] is checked before
  /// every chunk; on cancellation the firmware's write stream is closed
  /// cleanly with an empty final frame, the partial file is deleted (best
  /// effort) and [FlipperWriteCancelledException] is thrown.
  Future<void> storageWriteChunked(
    String path,
    List<int> data, {
    void Function(double progress)? onProgress,
    Duration timeout = const Duration(seconds: 300),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
    bool Function()? isCancelled,
  }) async {
    final total = data.length;
    final rpcChunkSize = transport?.storageChunkSize ?? Transport.bleChunkSize;
    final totalFrames = total == 0
        ? 1
        : ((total + rpcChunkSize - 1) ~/ rpcChunkSize);
    Log.info(
      '[Storage] write "$path": ${total}B, $totalFrames frames, '
      'rpcChunk=$rpcChunkSize',
    );

    final pingPace = transport is! UniversalBleTransportBase;

    // Returns true when the upload was cancelled mid-stream (the firmware
    // still received a valid final frame and replied with its ACK).
    Future<bool> upload() async {
      var cancelled = false;
      await callRpcFramesMulti(
        (sendFrame) async {
          var offset = 0;
          var frameIndex = 0;
          while (true) {
            if (isCancelled?.call() ?? false) {
              cancelled = true;
              // Close the firmware's write stream: without a hasNext=false
              // frame its storage handler would stay in the writing state
              // until an unrelated command resets it.
              final req = WriteRequest()
                ..path = path
                ..ensureFile().data = const <int>[];
              await sendFrame(Main(hasNext: false, storageWriteRequest: req));
              Log.info(
                '[Storage] write "$path" cancelled after $frameIndex frames',
              );
              return;
            }

            final end = (offset + rpcChunkSize) > total
                ? total
                : (offset + rpcChunkSize);
            final chunk = offset == end
                ? const <int>[]
                : data.sublist(offset, end);
            final hasNext = end < total;

            final req = WriteRequest()
              ..path = path
              ..ensureFile().data = chunk;

            await sendFrame(Main(hasNext: hasNext, storageWriteRequest: req));

            offset = end;
            frameIndex++;
            if (total > 0) onProgress?.call(offset / total);
            if (!hasNext) break;

            if (pingPace && frameIndex % 16 == 0) {
              await callRpcFrames(
                Main(systemPingRequest: PingRequest()),
                timeout: const Duration(seconds: 15),
                priority: FlipperRequestPriority.rightNow,
                interleavable: true,
              );
            }
          }
          Log.info('[Storage] $frameIndex frames sent, awaiting ACK');
        },
        timeout: timeout,
        priority: priority,
      );
      return cancelled;
    }

    bool cancelled;
    try {
      cancelled = await upload();
    } catch (e) {
      if (isCancelled?.call() ?? false) {
        // The link died while the caller was cancelling anyway; the firmware
        // session (and its partial file state) died with it.
        throw FlipperWriteCancelledException(path);
      }
      if (!isLinkDropError(e)) {
        Log.error('[Storage] write "$path" failed: $e');
        rethrow;
      }
      // The link dropped mid-upload and the firmware lost the partial file.
      // If the automatic reconnect restores the session, restart the upload
      // exactly once — the firmware opens the file with CREATE_ALWAYS, so a
      // restart from offset 0 is safe.
      Log.info('[Storage] write "$path" interrupted by link drop: $e');
      final restored = await waitForRpcSession(const Duration(seconds: 30));
      if (!restored) {
        rethrow;
      }
      Log.info('[Storage] link restored, restarting write "$path"');
      cancelled = await upload();
    }

    if (cancelled) {
      await _deletePartialWrite(path);
      throw FlipperWriteCancelledException(path);
    }

    onProgress?.call(1.0);
    Log.info('[Storage] write "$path" complete');
  }

  // Best-effort cleanup of an interrupted upload's partial file.
  Future<void> _deletePartialWrite(String path) async {
    try {
      await storageDelete(
        DeleteRequest(path: path),
        priority: FlipperRequestPriority.rightNow,
      );
      Log.info('[Storage] partial file "$path" deleted');
    } catch (e) {
      Log.error('[Storage] cleanup of partial write "$path" failed: $e');
    }
  }

  Future<List<Main>> storageTarExtract(
    TarExtractRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.background,
  }) {
    return callRpcFrames(
      Main(storageTarExtractRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }
}
