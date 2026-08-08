// This is a generated file - do not edit.
//
// Generated from network.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'network.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'network.pbenum.dart';

class ConnectRequest extends $pb.GeneratedMessage {
  factory ConnectRequest({
    $core.String? host,
    $core.int? port,
    Protocol? protocol,
    $core.int? timeoutMs,
    $core.int? connectionId,
  }) {
    final result = create();
    if (host != null) result.host = host;
    if (port != null) result.port = port;
    if (protocol != null) result.protocol = protocol;
    if (timeoutMs != null) result.timeoutMs = timeoutMs;
    if (connectionId != null) result.connectionId = connectionId;
    return result;
  }

  ConnectRequest._();

  factory ConnectRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'host')
    ..aI(2, _omitFieldNames ? '' : 'port', fieldType: $pb.PbFieldType.OU3)
    ..aE<Protocol>(3, _omitFieldNames ? '' : 'protocol',
        enumValues: Protocol.values)
    ..aI(4, _omitFieldNames ? '' : 'timeoutMs', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectRequest copyWith(void Function(ConnectRequest) updates) =>
      super.copyWith((message) => updates(message as ConnectRequest))
          as ConnectRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectRequest create() => ConnectRequest._();
  @$core.override
  ConnectRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectRequest>(create);
  static ConnectRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get host => $_getSZ(0);
  @$pb.TagNumber(1)
  set host($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHost() => $_has(0);
  @$pb.TagNumber(1)
  void clearHost() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get port => $_getIZ(1);
  @$pb.TagNumber(2)
  set port($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPort() => $_has(1);
  @$pb.TagNumber(2)
  void clearPort() => $_clearField(2);

  @$pb.TagNumber(3)
  Protocol get protocol => $_getN(2);
  @$pb.TagNumber(3)
  set protocol(Protocol value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProtocol() => $_has(2);
  @$pb.TagNumber(3)
  void clearProtocol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get timeoutMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set timeoutMs($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimeoutMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimeoutMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get connectionId => $_getIZ(4);
  @$pb.TagNumber(5)
  set connectionId($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasConnectionId() => $_has(4);
  @$pb.TagNumber(5)
  void clearConnectionId() => $_clearField(5);
}

class ConnectResponse extends $pb.GeneratedMessage {
  factory ConnectResponse({
    $core.int? connectionId,
    ConnectionState? state,
    ErrorCode? error,
    $core.String? resolvedIp,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (state != null) result.state = state;
    if (error != null) result.error = error;
    if (resolvedIp != null) result.resolvedIp = resolvedIp;
    return result;
  }

  ConnectResponse._();

  factory ConnectResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConnectResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConnectResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<ConnectionState>(2, _omitFieldNames ? '' : 'state',
        enumValues: ConnectionState.values)
    ..aE<ErrorCode>(3, _omitFieldNames ? '' : 'error',
        enumValues: ErrorCode.values)
    ..aOS(4, _omitFieldNames ? '' : 'resolvedIp')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConnectResponse copyWith(void Function(ConnectResponse) updates) =>
      super.copyWith((message) => updates(message as ConnectResponse))
          as ConnectResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConnectResponse create() => ConnectResponse._();
  @$core.override
  ConnectResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConnectResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConnectResponse>(create);
  static ConnectResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  ConnectionState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(ConnectionState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  ErrorCode get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(ErrorCode value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get resolvedIp => $_getSZ(3);
  @$pb.TagNumber(4)
  set resolvedIp($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResolvedIp() => $_has(3);
  @$pb.TagNumber(4)
  void clearResolvedIp() => $_clearField(4);
}

class SendRequest extends $pb.GeneratedMessage {
  factory SendRequest({
    $core.int? connectionId,
    $core.List<$core.int>? data,
    $core.bool? binary,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (data != null) result.data = data;
    if (binary != null) result.binary = binary;
    return result;
  }

  SendRequest._();

  factory SendRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'binary')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendRequest copyWith(void Function(SendRequest) updates) =>
      super.copyWith((message) => updates(message as SendRequest))
          as SendRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendRequest create() => SendRequest._();
  @$core.override
  SendRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendRequest>(create);
  static SendRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get binary => $_getBF(2);
  @$pb.TagNumber(3)
  set binary($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBinary() => $_has(2);
  @$pb.TagNumber(3)
  void clearBinary() => $_clearField(3);
}

class SendResponse extends $pb.GeneratedMessage {
  factory SendResponse({
    $core.int? connectionId,
    $core.int? bytesSent,
    ErrorCode? error,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (bytesSent != null) result.bytesSent = bytesSent;
    if (error != null) result.error = error;
    return result;
  }

  SendResponse._();

  factory SendResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SendResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SendResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'bytesSent', fieldType: $pb.PbFieldType.OU3)
    ..aE<ErrorCode>(3, _omitFieldNames ? '' : 'error',
        enumValues: ErrorCode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SendResponse copyWith(void Function(SendResponse) updates) =>
      super.copyWith((message) => updates(message as SendResponse))
          as SendResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SendResponse create() => SendResponse._();
  @$core.override
  SendResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SendResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SendResponse>(create);
  static SendResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get bytesSent => $_getIZ(1);
  @$pb.TagNumber(2)
  set bytesSent($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBytesSent() => $_has(1);
  @$pb.TagNumber(2)
  void clearBytesSent() => $_clearField(2);

  @$pb.TagNumber(3)
  ErrorCode get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(ErrorCode value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
}

class ReceiveData extends $pb.GeneratedMessage {
  factory ReceiveData({
    $core.int? connectionId,
    $core.List<$core.int>? data,
    $core.bool? binary,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (data != null) result.data = data;
    if (binary != null) result.binary = binary;
    return result;
  }

  ReceiveData._();

  factory ReceiveData.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReceiveData.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReceiveData',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOB(3, _omitFieldNames ? '' : 'binary')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReceiveData clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReceiveData copyWith(void Function(ReceiveData) updates) =>
      super.copyWith((message) => updates(message as ReceiveData))
          as ReceiveData;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReceiveData create() => ReceiveData._();
  @$core.override
  ReceiveData createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReceiveData getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReceiveData>(create);
  static ReceiveData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get data => $_getN(1);
  @$pb.TagNumber(2)
  set data($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get binary => $_getBF(2);
  @$pb.TagNumber(3)
  set binary($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBinary() => $_has(2);
  @$pb.TagNumber(3)
  void clearBinary() => $_clearField(3);
}

class CloseRequest extends $pb.GeneratedMessage {
  factory CloseRequest({
    $core.int? connectionId,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    return result;
  }

  CloseRequest._();

  factory CloseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CloseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CloseRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseRequest copyWith(void Function(CloseRequest) updates) =>
      super.copyWith((message) => updates(message as CloseRequest))
          as CloseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CloseRequest create() => CloseRequest._();
  @$core.override
  CloseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CloseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CloseRequest>(create);
  static CloseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);
}

class CloseResponse extends $pb.GeneratedMessage {
  factory CloseResponse({
    $core.int? connectionId,
    ErrorCode? error,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (error != null) result.error = error;
    return result;
  }

  CloseResponse._();

  factory CloseResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CloseResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CloseResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<ErrorCode>(2, _omitFieldNames ? '' : 'error',
        enumValues: ErrorCode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseResponse copyWith(void Function(CloseResponse) updates) =>
      super.copyWith((message) => updates(message as CloseResponse))
          as CloseResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CloseResponse create() => CloseResponse._();
  @$core.override
  CloseResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CloseResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CloseResponse>(create);
  static CloseResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  ErrorCode get error => $_getN(1);
  @$pb.TagNumber(2)
  set error(ErrorCode value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => $_clearField(2);
}

class StateChanged extends $pb.GeneratedMessage {
  factory StateChanged({
    $core.int? connectionId,
    ConnectionState? state,
    ErrorCode? error,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (state != null) result.state = state;
    if (error != null) result.error = error;
    return result;
  }

  StateChanged._();

  factory StateChanged.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StateChanged.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StateChanged',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<ConnectionState>(2, _omitFieldNames ? '' : 'state',
        enumValues: ConnectionState.values)
    ..aE<ErrorCode>(3, _omitFieldNames ? '' : 'error',
        enumValues: ErrorCode.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateChanged clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateChanged copyWith(void Function(StateChanged) updates) =>
      super.copyWith((message) => updates(message as StateChanged))
          as StateChanged;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StateChanged create() => StateChanged._();
  @$core.override
  StateChanged createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StateChanged getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StateChanged>(create);
  static StateChanged? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  ConnectionState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(ConnectionState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  ErrorCode get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(ErrorCode value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
}

class HttpRequest extends $pb.GeneratedMessage {
  factory HttpRequest({
    $core.int? requestId,
    HttpMethod? method,
    $core.String? url,
    $core.String? headers,
    $core.List<$core.int>? body,
    $core.String? sendPath,
    $core.String? savePath,
    $core.int? timeoutMs,
    $core.bool? includeHeaders,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (method != null) result.method = method;
    if (url != null) result.url = url;
    if (headers != null) result.headers = headers;
    if (body != null) result.body = body;
    if (sendPath != null) result.sendPath = sendPath;
    if (savePath != null) result.savePath = savePath;
    if (timeoutMs != null) result.timeoutMs = timeoutMs;
    if (includeHeaders != null) result.includeHeaders = includeHeaders;
    return result;
  }

  HttpRequest._();

  factory HttpRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HttpRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HttpRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'requestId', fieldType: $pb.PbFieldType.OU3)
    ..aE<HttpMethod>(2, _omitFieldNames ? '' : 'method',
        enumValues: HttpMethod.values)
    ..aOS(3, _omitFieldNames ? '' : 'url')
    ..aOS(4, _omitFieldNames ? '' : 'headers')
    ..a<$core.List<$core.int>>(
        5, _omitFieldNames ? '' : 'body', $pb.PbFieldType.OY)
    ..aOS(6, _omitFieldNames ? '' : 'sendPath')
    ..aOS(7, _omitFieldNames ? '' : 'savePath')
    ..aI(8, _omitFieldNames ? '' : 'timeoutMs', fieldType: $pb.PbFieldType.OU3)
    ..aOB(9, _omitFieldNames ? '' : 'includeHeaders')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HttpRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HttpRequest copyWith(void Function(HttpRequest) updates) =>
      super.copyWith((message) => updates(message as HttpRequest))
          as HttpRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HttpRequest create() => HttpRequest._();
  @$core.override
  HttpRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HttpRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HttpRequest>(create);
  static HttpRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get requestId => $_getIZ(0);
  @$pb.TagNumber(1)
  set requestId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  HttpMethod get method => $_getN(1);
  @$pb.TagNumber(2)
  set method(HttpMethod value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasMethod() => $_has(1);
  @$pb.TagNumber(2)
  void clearMethod() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get url => $_getSZ(2);
  @$pb.TagNumber(3)
  set url($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearUrl() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get headers => $_getSZ(3);
  @$pb.TagNumber(4)
  set headers($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeaders() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeaders() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.int> get body => $_getN(4);
  @$pb.TagNumber(5)
  set body($core.List<$core.int> value) => $_setBytes(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBody() => $_has(4);
  @$pb.TagNumber(5)
  void clearBody() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get sendPath => $_getSZ(5);
  @$pb.TagNumber(6)
  set sendPath($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSendPath() => $_has(5);
  @$pb.TagNumber(6)
  void clearSendPath() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get savePath => $_getSZ(6);
  @$pb.TagNumber(7)
  set savePath($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSavePath() => $_has(6);
  @$pb.TagNumber(7)
  void clearSavePath() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get timeoutMs => $_getIZ(7);
  @$pb.TagNumber(8)
  set timeoutMs($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTimeoutMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearTimeoutMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get includeHeaders => $_getBF(8);
  @$pb.TagNumber(9)
  set includeHeaders($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasIncludeHeaders() => $_has(8);
  @$pb.TagNumber(9)
  void clearIncludeHeaders() => $_clearField(9);
}

class HttpResponse extends $pb.GeneratedMessage {
  factory HttpResponse({
    $core.int? requestId,
    $core.int? status,
    ErrorCode? error,
    $core.String? headers,
    $core.int? bodySize,
    $core.bool? savedToFile,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (status != null) result.status = status;
    if (error != null) result.error = error;
    if (headers != null) result.headers = headers;
    if (bodySize != null) result.bodySize = bodySize;
    if (savedToFile != null) result.savedToFile = savedToFile;
    return result;
  }

  HttpResponse._();

  factory HttpResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HttpResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HttpResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'requestId', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'status', fieldType: $pb.PbFieldType.OU3)
    ..aE<ErrorCode>(3, _omitFieldNames ? '' : 'error',
        enumValues: ErrorCode.values)
    ..aOS(4, _omitFieldNames ? '' : 'headers')
    ..aI(5, _omitFieldNames ? '' : 'bodySize', fieldType: $pb.PbFieldType.OU3)
    ..aOB(6, _omitFieldNames ? '' : 'savedToFile')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HttpResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HttpResponse copyWith(void Function(HttpResponse) updates) =>
      super.copyWith((message) => updates(message as HttpResponse))
          as HttpResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HttpResponse create() => HttpResponse._();
  @$core.override
  HttpResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HttpResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HttpResponse>(create);
  static HttpResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get requestId => $_getIZ(0);
  @$pb.TagNumber(1)
  set requestId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get status => $_getIZ(1);
  @$pb.TagNumber(2)
  set status($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  ErrorCode get error => $_getN(2);
  @$pb.TagNumber(3)
  set error(ErrorCode value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get headers => $_getSZ(3);
  @$pb.TagNumber(4)
  set headers($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHeaders() => $_has(3);
  @$pb.TagNumber(4)
  void clearHeaders() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get bodySize => $_getIZ(4);
  @$pb.TagNumber(5)
  set bodySize($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBodySize() => $_has(4);
  @$pb.TagNumber(5)
  void clearBodySize() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get savedToFile => $_getBF(5);
  @$pb.TagNumber(6)
  set savedToFile($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSavedToFile() => $_has(5);
  @$pb.TagNumber(6)
  void clearSavedToFile() => $_clearField(6);
}

class WebSocketOpenRequest extends $pb.GeneratedMessage {
  factory WebSocketOpenRequest({
    $core.int? connectionId,
    $core.String? url,
    $core.String? headers,
    $core.int? timeoutMs,
  }) {
    final result = create();
    if (connectionId != null) result.connectionId = connectionId;
    if (url != null) result.url = url;
    if (headers != null) result.headers = headers;
    if (timeoutMs != null) result.timeoutMs = timeoutMs;
    return result;
  }

  WebSocketOpenRequest._();

  factory WebSocketOpenRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WebSocketOpenRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WebSocketOpenRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Network'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'connectionId',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'url')
    ..aOS(3, _omitFieldNames ? '' : 'headers')
    ..aI(4, _omitFieldNames ? '' : 'timeoutMs', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WebSocketOpenRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WebSocketOpenRequest copyWith(void Function(WebSocketOpenRequest) updates) =>
      super.copyWith((message) => updates(message as WebSocketOpenRequest))
          as WebSocketOpenRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WebSocketOpenRequest create() => WebSocketOpenRequest._();
  @$core.override
  WebSocketOpenRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WebSocketOpenRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WebSocketOpenRequest>(create);
  static WebSocketOpenRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get connectionId => $_getIZ(0);
  @$pb.TagNumber(1)
  set connectionId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConnectionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConnectionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get url => $_getSZ(1);
  @$pb.TagNumber(2)
  set url($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrl() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get headers => $_getSZ(2);
  @$pb.TagNumber(3)
  set headers($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeaders() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeaders() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get timeoutMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set timeoutMs($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimeoutMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimeoutMs() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
