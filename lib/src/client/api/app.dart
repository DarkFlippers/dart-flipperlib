import 'dart:async';

import '../../../protobuf.dart';
import '../../model/device.dart';
import '../../model/enums.dart';
import '../client.dart';

extension FlipperAppApi on FlipperClient {
  // appStart/appExit/appLoadFile opt out of TX pipelining: the firmware's app
  // RPC handler accepts exactly one of them at a time and furi_check()s (i.e.
  // crashes the Flipper) on a second one that arrives before the first is
  // answered. The TX queue must hold them back, not just the callers.
  Future<List<Main>> appStart(
    StartRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(appStartRequest: request),
      timeout: timeout,
      priority: priority,
      pipelined: false,
    );
  }

  Future<FlipperRpcBatch<LockStatusResponse>> appLockStatus({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(appLockStatusRequest: LockStatusRequest()),
      (frame) =>
          frame.hasAppLockStatusResponse() ? frame.appLockStatusResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> appExit(
    AppExitRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(appExitRequest: request),
      timeout: timeout,
      priority: priority,
      pipelined: false,
    );
  }

  Future<List<Main>> appLoadFile(
    AppLoadFileRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(appLoadFileRequest: request),
      timeout: timeout,
      priority: priority,
      pipelined: false,
    );
  }

  Future<List<Main>> appButtonPress(
    AppButtonPressRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.rightNow,
  }) {
    return callRpcFrames(
      Main(appButtonPressRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> appButtonRelease(
    AppButtonReleaseRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.rightNow,
  }) {
    return callRpcFrames(
      Main(appButtonReleaseRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> appButtonPressRelease(
    AppButtonPressReleaseRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.rightNow,
  }) {
    return callRpcFrames(
      Main(appButtonPressReleaseRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Stream<AppStateResponse> appStateStream() {
    return notificationStream.transform(
      StreamTransformer<Main, AppStateResponse>.fromHandlers(
        handleData: (frame, sink) {
          if (frame.hasAppStateResponse()) sink.add(frame.appStateResponse);
        },
      ),
    );
  }

  Future<FlipperRpcBatch<GetErrorResponse>> appGetError({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(appGetErrorRequest: GetErrorRequest()),
      (frame) =>
          frame.hasAppGetErrorResponse() ? frame.appGetErrorResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> appDataExchange(
    DataExchangeRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(appDataExchangeRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }
}
