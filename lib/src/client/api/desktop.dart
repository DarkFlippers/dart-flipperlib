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

  Future<List<Main>> desktopIsLocked({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
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
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(desktopUnlockRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> desktopStatusSubscribe({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(desktopStatusSubscribeRequest: StatusSubscribeRequest()),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> desktopStatusUnsubscribe({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(desktopStatusUnsubscribeRequest: StatusUnsubscribeRequest()),
      timeout: timeout,
      priority: priority,
    );
  }
}
