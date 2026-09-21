import 'dart:async';

import '../../../protobuf.dart';
import '../../model/enums.dart';
import '../client.dart';

extension FlipperDesktopApi on FlipperClient {
  Stream<Status> desktopStatusStream() {
    return notificationStream.transform(
      StreamTransformer<Main, Status>.fromHandlers(
        handleData: (frame, sink) {
          if (frame.hasDesktopStatus()) sink.add(frame.desktopStatus);
        },
      ),
    );
  }

  /// Ordinary priority rather than foreground: the remote screen asks this as
  /// part of starting its stream, so it has to reach the Flipper that stream is
  /// on and not the one that happens to be active by the time it goes out.
  Future<List<Main>> desktopIsLocked({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) {
    return callRpcFrames(
      Main(desktopIsLockedRequest: IsLockedRequest()),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> desktopUnlock(
    UnlockRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) {
    return callRpcFrames(
      Main(desktopUnlockRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> desktopStatusSubscribe({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) {
    return callRpcFrames(
      Main(desktopStatusSubscribeRequest: StatusSubscribeRequest()),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> desktopStatusUnsubscribe({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
  }) {
    return callRpcFrames(
      Main(desktopStatusUnsubscribeRequest: StatusUnsubscribeRequest()),
      timeout: timeout,
      priority: priority,
    );
  }
}
