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

class Protocol extends $pb.ProtobufEnum {
  static const Protocol TCP = Protocol._(0, _omitEnumNames ? '' : 'TCP');
  static const Protocol UDP = Protocol._(1, _omitEnumNames ? '' : 'UDP');

  static const $core.List<Protocol> values = <Protocol>[
    TCP,
    UDP,
  ];

  static final $core.List<Protocol?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static Protocol? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Protocol._(super.value, super.name);
}

class HttpMethod extends $pb.ProtobufEnum {
  static const HttpMethod HTTP_GET =
      HttpMethod._(0, _omitEnumNames ? '' : 'HTTP_GET');
  static const HttpMethod HTTP_POST =
      HttpMethod._(1, _omitEnumNames ? '' : 'HTTP_POST');
  static const HttpMethod HTTP_PUT =
      HttpMethod._(2, _omitEnumNames ? '' : 'HTTP_PUT');
  static const HttpMethod HTTP_PATCH =
      HttpMethod._(3, _omitEnumNames ? '' : 'HTTP_PATCH');
  static const HttpMethod HTTP_DELETE =
      HttpMethod._(4, _omitEnumNames ? '' : 'HTTP_DELETE');
  static const HttpMethod HTTP_HEAD =
      HttpMethod._(5, _omitEnumNames ? '' : 'HTTP_HEAD');

  static const $core.List<HttpMethod> values = <HttpMethod>[
    HTTP_GET,
    HTTP_POST,
    HTTP_PUT,
    HTTP_PATCH,
    HTTP_DELETE,
    HTTP_HEAD,
  ];

  static final $core.List<HttpMethod?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static HttpMethod? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const HttpMethod._(super.value, super.name);
}

class ConnectionState extends $pb.ProtobufEnum {
  static const ConnectionState DISCONNECTED =
      ConnectionState._(0, _omitEnumNames ? '' : 'DISCONNECTED');
  static const ConnectionState CONNECTING =
      ConnectionState._(1, _omitEnumNames ? '' : 'CONNECTING');
  static const ConnectionState CONNECTED =
      ConnectionState._(2, _omitEnumNames ? '' : 'CONNECTED');
  static const ConnectionState ERROR =
      ConnectionState._(3, _omitEnumNames ? '' : 'ERROR');

  static const $core.List<ConnectionState> values = <ConnectionState>[
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR,
  ];

  static final $core.List<ConnectionState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ConnectionState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConnectionState._(super.value, super.name);
}

class ErrorCode extends $pb.ProtobufEnum {
  static const ErrorCode NONE = ErrorCode._(0, _omitEnumNames ? '' : 'NONE');
  static const ErrorCode DNS_FAILED =
      ErrorCode._(1, _omitEnumNames ? '' : 'DNS_FAILED');
  static const ErrorCode TIMEOUT =
      ErrorCode._(2, _omitEnumNames ? '' : 'TIMEOUT');
  static const ErrorCode CONNECTION_REFUSED =
      ErrorCode._(3, _omitEnumNames ? '' : 'CONNECTION_REFUSED');
  static const ErrorCode NETWORK_UNREACHABLE =
      ErrorCode._(4, _omitEnumNames ? '' : 'NETWORK_UNREACHABLE');
  static const ErrorCode HOST_UNREACHABLE =
      ErrorCode._(5, _omitEnumNames ? '' : 'HOST_UNREACHABLE');
  static const ErrorCode INVALID_CONNECTION =
      ErrorCode._(6, _omitEnumNames ? '' : 'INVALID_CONNECTION');
  static const ErrorCode NOT_CONNECTED =
      ErrorCode._(7, _omitEnumNames ? '' : 'NOT_CONNECTED');
  static const ErrorCode SEND_FAILED =
      ErrorCode._(8, _omitEnumNames ? '' : 'SEND_FAILED');
  static const ErrorCode RECEIVE_FAILED =
      ErrorCode._(9, _omitEnumNames ? '' : 'RECEIVE_FAILED');
  static const ErrorCode MAX_CONNECTIONS =
      ErrorCode._(10, _omitEnumNames ? '' : 'MAX_CONNECTIONS');
  static const ErrorCode INVALID_PROTOCOL =
      ErrorCode._(11, _omitEnumNames ? '' : 'INVALID_PROTOCOL');
  static const ErrorCode INTERNAL_ERROR =
      ErrorCode._(12, _omitEnumNames ? '' : 'INTERNAL_ERROR');
  static const ErrorCode TLS_FAILED =
      ErrorCode._(13, _omitEnumNames ? '' : 'TLS_FAILED');
  static const ErrorCode INVALID_URL =
      ErrorCode._(14, _omitEnumNames ? '' : 'INVALID_URL');
  static const ErrorCode FILE_ERROR =
      ErrorCode._(15, _omitEnumNames ? '' : 'FILE_ERROR');

  static const $core.List<ErrorCode> values = <ErrorCode>[
    NONE,
    DNS_FAILED,
    TIMEOUT,
    CONNECTION_REFUSED,
    NETWORK_UNREACHABLE,
    HOST_UNREACHABLE,
    INVALID_CONNECTION,
    NOT_CONNECTED,
    SEND_FAILED,
    RECEIVE_FAILED,
    MAX_CONNECTIONS,
    INVALID_PROTOCOL,
    INTERNAL_ERROR,
    TLS_FAILED,
    INVALID_URL,
    FILE_ERROR,
  ];

  static final $core.List<ErrorCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 15);
  static ErrorCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ErrorCode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
