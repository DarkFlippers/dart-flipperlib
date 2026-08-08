import 'dart:async';

import '../../../protobuf.dart';
import '../../model/device.dart';
import '../../model/enums.dart';
import '../client.dart';

extension FlipperAppApi on FlipperClient {
  Future<List<Main>> appStart(
    StartRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(appStartRequest: request),
      timeout: timeout,
      priority: priority,
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
