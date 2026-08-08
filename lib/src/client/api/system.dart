import 'dart:async';

import '../../../protobuf.dart';
import '../../model/device.dart';
import '../../model/enums.dart';
import '../client.dart';

extension FlipperSystemApi on FlipperClient {
  Future<FlipperRpcBatch<PingResponse>> ping(
    PingRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.rightNow,
  }) {
    return callRpc(
      Main(systemPingRequest: request),
      (frame) =>
          frame.hasSystemPingResponse() ? frame.systemPingResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<ProtobufVersionResponse>> protobufVersion({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(systemProtobufVersionRequest: ProtobufVersionRequest()),
      (frame) => frame.hasSystemProtobufVersionResponse()
          ? frame.systemProtobufVersionResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<DeviceInfoResponse>> deviceInfo({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(systemDeviceInfoRequest: DeviceInfoRequest()),
      (frame) => frame.hasSystemDeviceInfoResponse()
          ? frame.systemDeviceInfoResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<PowerInfoResponse>> powerInfo({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.background,
  }) {
    return callRpc(
      Main(systemPowerInfoRequest: PowerInfoRequest()),
      (frame) => frame.hasSystemPowerInfoResponse()
          ? frame.systemPowerInfoResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<GetDateTimeResponse>> getDateTime({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(systemGetDatetimeRequest: GetDateTimeRequest()),
      (frame) => frame.hasSystemGetDatetimeResponse()
          ? frame.systemGetDatetimeResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> setDateTime(
    SetDateTimeRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(systemSetDatetimeRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> update(
    UpdateRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(systemUpdateRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<UpdateResponse>> updateStatus({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.background,
  }) {
    return callRpc(
      Main(systemUpdateRequest: UpdateRequest()),
      (frame) =>
          frame.hasSystemUpdateResponse() ? frame.systemUpdateResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> factoryReset(
    FactoryResetRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(systemFactoryResetRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<void> reboot(RebootRequest request) async {
    unawaited(
      callRpcFrames(
        Main(systemRebootRequest: request),
        timeout: const Duration(seconds: 5),
        priority: FlipperRequestPriority.rightNow,
      ).catchError((_) => <Main>[]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await disconnect();
  }

  Future<void> runUpdate(UpdateRequest request) async {
    await update(request);
    await reboot(RebootRequest(mode: RebootRequest_RebootMode.UPDATE));
  }

  Future<List<Main>> playAudiovisualAlert(
    PlayAudiovisualAlertRequest request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(systemPlayAudiovisualAlertRequest: request),
      timeout: timeout,
      priority: priority,
    );
  }
}
