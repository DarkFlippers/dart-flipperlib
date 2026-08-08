import 'dart:async';

import '../../../protobuf.dart';
import '../../model/device.dart';
import '../../model/enums.dart';
import '../client.dart';

extension FlipperGpioApi on FlipperClient {
  Future<List<Main>> gpioSetPinMode(
    SetPinMode request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(gpioSetPinMode: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> gpioSetInputPull(
    SetInputPull request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(gpioSetInputPull: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<GetPinModeResponse>> gpioGetPinMode(
    GetPinMode request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(gpioGetPinMode: request),
      (frame) => frame.hasGpioGetPinModeResponse()
          ? frame.gpioGetPinModeResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<ReadPinResponse>> gpioReadPin(
    ReadPin request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(gpioReadPin: request),
      (frame) =>
          frame.hasGpioReadPinResponse() ? frame.gpioReadPinResponse : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> gpioWritePin(
    WritePin request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(gpioWritePin: request),
      timeout: timeout,
      priority: priority,
    );
  }

  Future<FlipperRpcBatch<GetOtgModeResponse>> gpioGetOtgMode({
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpc(
      Main(gpioGetOtgMode: GetOtgMode()),
      (frame) => frame.hasGpioGetOtgModeResponse()
          ? frame.gpioGetOtgModeResponse
          : null,
      timeout: timeout,
      priority: priority,
    );
  }

  Future<List<Main>> gpioSetOtgMode(
    SetOtgMode request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.foreground,
  }) {
    return callRpcFrames(
      Main(gpioSetOtgMode: request),
      timeout: timeout,
      priority: priority,
    );
  }
}
