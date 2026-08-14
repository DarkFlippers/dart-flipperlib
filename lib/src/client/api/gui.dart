import 'dart:async';

import '../../../protobuf.dart';
import '../../model/enums.dart';
import '../client.dart';

extension FlipperGuiApi on FlipperClient {
  Stream<ScreenFrame> screenFrameStream() {
    return broadcastStream.transform(
      StreamTransformer<Main, ScreenFrame>.fromHandlers(
        handleData: (frame, sink) {
          if (frame.hasGuiScreenFrame()) {
            sink.add(frame.guiScreenFrame);
          }
        },
      ),
    );
  }

  Stream<ScreenFrame> get screenFrames => screenFrameStream();

  Future<List<Main>> startScreenFrameStream({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(guiStartScreenStreamRequest: StartScreenStreamRequest()),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> stopScreenFrameStream({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(guiStopScreenStreamRequest: StopScreenStreamRequest()),
      timeout: timeout,
      priority: priority,
    );
  }

  StreamSubscription<ScreenFrame> subscribeScreenFrameStream(
    void Function(ScreenFrame frame) onFrame,
  ) {
    return screenFrameStream().listen(onFrame);
  }

  Future<List<Main>> guiStartScreenStream({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return startScreenFrameStream(timeout: timeout, priority: priority);
  }

  Future<List<Main>> guiStopScreenStream({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return stopScreenFrameStream(timeout: timeout, priority: priority);
  }

  Future<List<Main>> guiStartVirtualDisplay(
    StartVirtualDisplayRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(guiStartVirtualDisplayRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> guiStopVirtualDisplay({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(guiStopVirtualDisplayRequest: StopVirtualDisplayRequest()),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> guiSendInput(
    SendInputEventRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.rightNow,
    void Function()? onSent,
    bool pipelined = true,
  }) {
    return callRpcFrames(
      Main(guiSendInputEventRequest: request),
      timeout: timeout,
      priority: priority,
      onSent: onSent,
      pipelined: pipelined,
    );
  }

  Future<void> guiSendInputAndForget(
    SendInputEventRequest request, {
    FlipperRequestPriority priority = FlipperRequestPriority.rightNow,
  }) {
    return sendRpc(Main(guiSendInputEventRequest: request), priority: priority);
  }
}
