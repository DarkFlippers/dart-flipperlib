import '../proto/generated/flipper.pb.dart';

class FlipperUnsupportedModeError extends StateError {
  FlipperUnsupportedModeError(super.message);
}

/// Thrown by storageWriteChunked when the caller cancels the upload. The
/// firmware's write stream has been closed cleanly with an empty final frame
/// and the partial file deleted (best effort).
class FlipperWriteCancelledException implements Exception {
  final String path;

  FlipperWriteCancelledException(this.path);

  @override
  String toString() => 'Write cancelled: $path';
}

class FlipperRpcException implements Exception {
  final CommandStatus status;
  final int statusValue;
  final String statusName;
  final Main response;

  FlipperRpcException(this.response)
    : status = response.commandStatus,
      statusValue = response.commandStatus.value,
      statusName = response.commandStatus.name;

  @override
  String toString() => 'FlipperRpcException($statusName=$statusValue)';
}

class FlipperRpcGeneralException extends FlipperRpcException {
  FlipperRpcGeneralException(super.response);
}

class FlipperRpcDecodeException extends FlipperRpcException {
  FlipperRpcDecodeException(super.response);
}

class FlipperRpcNotImplementedException extends FlipperRpcException {
  FlipperRpcNotImplementedException(super.response);
}

class FlipperRpcBusyException extends FlipperRpcException {
  FlipperRpcBusyException(super.response);
}

class FlipperRpcContinuousCommandInterruptedException
    extends FlipperRpcException {
  FlipperRpcContinuousCommandInterruptedException(super.response);
}

class FlipperRpcInvalidParametersException extends FlipperRpcException {
  FlipperRpcInvalidParametersException(super.response);
}

class FlipperRpcStorageNotReadyException extends FlipperRpcException {
  FlipperRpcStorageNotReadyException(super.response);
}

class FlipperRpcStorageExistException extends FlipperRpcException {
  FlipperRpcStorageExistException(super.response);
}

class FlipperRpcStorageNotExistException extends FlipperRpcException {
  FlipperRpcStorageNotExistException(super.response);
}

class FlipperRpcStorageInvalidParameterException extends FlipperRpcException {
  FlipperRpcStorageInvalidParameterException(super.response);
}

class FlipperRpcStorageDeniedException extends FlipperRpcException {
  FlipperRpcStorageDeniedException(super.response);
}

class FlipperRpcStorageInvalidNameException extends FlipperRpcException {
  FlipperRpcStorageInvalidNameException(super.response);
}

class FlipperRpcStorageInternalException extends FlipperRpcException {
  FlipperRpcStorageInternalException(super.response);
}

class FlipperRpcStorageNotImplementedException extends FlipperRpcException {
  FlipperRpcStorageNotImplementedException(super.response);
}

class FlipperRpcStorageAlreadyOpenException extends FlipperRpcException {
  FlipperRpcStorageAlreadyOpenException(super.response);
}

class FlipperRpcStorageDirNotEmptyException extends FlipperRpcException {
  FlipperRpcStorageDirNotEmptyException(super.response);
}

class FlipperRpcAppCantStartException extends FlipperRpcException {
  FlipperRpcAppCantStartException(super.response);
}

class FlipperRpcAppSystemLockedException extends FlipperRpcException {
  FlipperRpcAppSystemLockedException(super.response);
}

class FlipperRpcAppNotRunningException extends FlipperRpcException {
  FlipperRpcAppNotRunningException(super.response);
}

class FlipperRpcAppCmdErrorException extends FlipperRpcException {
  FlipperRpcAppCmdErrorException(super.response);
}

class FlipperRpcVirtualDisplayAlreadyStartedException
    extends FlipperRpcException {
  FlipperRpcVirtualDisplayAlreadyStartedException(super.response);
}

class FlipperRpcVirtualDisplayNotStartedException extends FlipperRpcException {
  FlipperRpcVirtualDisplayNotStartedException(super.response);
}

class FlipperRpcGpioModeIncorrectException extends FlipperRpcException {
  FlipperRpcGpioModeIncorrectException(super.response);
}

class FlipperRpcGpioUnknownPinModeException extends FlipperRpcException {
  FlipperRpcGpioUnknownPinModeException(super.response);
}

FlipperRpcException? exceptionFromResponse(Main response) {
  final status = response.commandStatus;
  if (status == CommandStatus.OK) return null;
  if (status == CommandStatus.ERROR_DECODE) {
    return FlipperRpcDecodeException(response);
  }
  if (status == CommandStatus.ERROR_NOT_IMPLEMENTED) {
    return FlipperRpcNotImplementedException(response);
  }
  if (status == CommandStatus.ERROR_BUSY) {
    return FlipperRpcBusyException(response);
  }
  if (status == CommandStatus.ERROR_CONTINUOUS_COMMAND_INTERRUPTED) {
    return FlipperRpcContinuousCommandInterruptedException(response);
  }
  if (status == CommandStatus.ERROR_INVALID_PARAMETERS) {
    return FlipperRpcInvalidParametersException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_NOT_READY) {
    return FlipperRpcStorageNotReadyException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_EXIST) {
    return FlipperRpcStorageExistException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_NOT_EXIST) {
    return FlipperRpcStorageNotExistException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_INVALID_PARAMETER) {
    return FlipperRpcStorageInvalidParameterException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_DENIED) {
    return FlipperRpcStorageDeniedException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_INVALID_NAME) {
    return FlipperRpcStorageInvalidNameException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_INTERNAL) {
    return FlipperRpcStorageInternalException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_NOT_IMPLEMENTED) {
    return FlipperRpcStorageNotImplementedException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_ALREADY_OPEN) {
    return FlipperRpcStorageAlreadyOpenException(response);
  }
  if (status == CommandStatus.ERROR_STORAGE_DIR_NOT_EMPTY) {
    return FlipperRpcStorageDirNotEmptyException(response);
  }
  if (status == CommandStatus.ERROR_APP_CANT_START) {
    return FlipperRpcAppCantStartException(response);
  }
  if (status == CommandStatus.ERROR_APP_SYSTEM_LOCKED) {
    return FlipperRpcAppSystemLockedException(response);
  }
  if (status == CommandStatus.ERROR_APP_NOT_RUNNING) {
    return FlipperRpcAppNotRunningException(response);
  }
  if (status == CommandStatus.ERROR_APP_CMD_ERROR) {
    return FlipperRpcAppCmdErrorException(response);
  }
  if (status == CommandStatus.ERROR_VIRTUAL_DISPLAY_ALREADY_STARTED) {
    return FlipperRpcVirtualDisplayAlreadyStartedException(response);
  }
  if (status == CommandStatus.ERROR_VIRTUAL_DISPLAY_NOT_STARTED) {
    return FlipperRpcVirtualDisplayNotStartedException(response);
  }
  if (status == CommandStatus.ERROR_GPIO_MODE_INCORRECT) {
    return FlipperRpcGpioModeIncorrectException(response);
  }
  if (status == CommandStatus.ERROR_GPIO_UNKNOWN_PIN_MODE) {
    return FlipperRpcGpioUnknownPinModeException(response);
  }
  return FlipperRpcGeneralException(response);
}
