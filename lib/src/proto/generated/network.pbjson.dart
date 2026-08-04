// This is a generated file - do not edit.
//
// Generated from network.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use protocolDescriptor instead')
const Protocol$json = {
  '1': 'Protocol',
  '2': [
    {'1': 'TCP', '2': 0},
    {'1': 'UDP', '2': 1},
  ],
};

/// Descriptor for `Protocol`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List protocolDescriptor =
    $convert.base64Decode('CghQcm90b2NvbBIHCgNUQ1AQABIHCgNVRFAQAQ==');

@$core.Deprecated('Use httpMethodDescriptor instead')
const HttpMethod$json = {
  '1': 'HttpMethod',
  '2': [
    {'1': 'HTTP_GET', '2': 0},
    {'1': 'HTTP_POST', '2': 1},
    {'1': 'HTTP_PUT', '2': 2},
    {'1': 'HTTP_PATCH', '2': 3},
    {'1': 'HTTP_DELETE', '2': 4},
    {'1': 'HTTP_HEAD', '2': 5},
  ],
};

/// Descriptor for `HttpMethod`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List httpMethodDescriptor = $convert.base64Decode(
    'CgpIdHRwTWV0aG9kEgwKCEhUVFBfR0VUEAASDQoJSFRUUF9QT1NUEAESDAoISFRUUF9QVVQQAh'
    'IOCgpIVFRQX1BBVENIEAMSDwoLSFRUUF9ERUxFVEUQBBINCglIVFRQX0hFQUQQBQ==');

@$core.Deprecated('Use connectionStateDescriptor instead')
const ConnectionState$json = {
  '1': 'ConnectionState',
  '2': [
    {'1': 'DISCONNECTED', '2': 0},
    {'1': 'CONNECTING', '2': 1},
    {'1': 'CONNECTED', '2': 2},
    {'1': 'ERROR', '2': 3},
  ],
};

/// Descriptor for `ConnectionState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List connectionStateDescriptor = $convert.base64Decode(
    'Cg9Db25uZWN0aW9uU3RhdGUSEAoMRElTQ09OTkVDVEVEEAASDgoKQ09OTkVDVElORxABEg0KCU'
    'NPTk5FQ1RFRBACEgkKBUVSUk9SEAM=');

@$core.Deprecated('Use errorCodeDescriptor instead')
const ErrorCode$json = {
  '1': 'ErrorCode',
  '2': [
    {'1': 'NONE', '2': 0},
    {'1': 'DNS_FAILED', '2': 1},
    {'1': 'TIMEOUT', '2': 2},
    {'1': 'CONNECTION_REFUSED', '2': 3},
    {'1': 'NETWORK_UNREACHABLE', '2': 4},
    {'1': 'HOST_UNREACHABLE', '2': 5},
    {'1': 'INVALID_CONNECTION', '2': 6},
    {'1': 'NOT_CONNECTED', '2': 7},
    {'1': 'SEND_FAILED', '2': 8},
    {'1': 'RECEIVE_FAILED', '2': 9},
    {'1': 'MAX_CONNECTIONS', '2': 10},
    {'1': 'INVALID_PROTOCOL', '2': 11},
    {'1': 'INTERNAL_ERROR', '2': 12},
    {'1': 'TLS_FAILED', '2': 13},
    {'1': 'INVALID_URL', '2': 14},
    {'1': 'FILE_ERROR', '2': 15},
  ],
};

/// Descriptor for `ErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List errorCodeDescriptor = $convert.base64Decode(
    'CglFcnJvckNvZGUSCAoETk9ORRAAEg4KCkROU19GQUlMRUQQARILCgdUSU1FT1VUEAISFgoSQ0'
    '9OTkVDVElPTl9SRUZVU0VEEAMSFwoTTkVUV09SS19VTlJFQUNIQUJMRRAEEhQKEEhPU1RfVU5S'
    'RUFDSEFCTEUQBRIWChJJTlZBTElEX0NPTk5FQ1RJT04QBhIRCg1OT1RfQ09OTkVDVEVEEAcSDw'
    'oLU0VORF9GQUlMRUQQCBISCg5SRUNFSVZFX0ZBSUxFRBAJEhMKD01BWF9DT05ORUNUSU9OUxAK'
    'EhQKEElOVkFMSURfUFJPVE9DT0wQCxISCg5JTlRFUk5BTF9FUlJPUhAMEg4KClRMU19GQUlMRU'
    'QQDRIPCgtJTlZBTElEX1VSTBAOEg4KCkZJTEVfRVJST1IQDw==');

@$core.Deprecated('Use connectRequestDescriptor instead')
const ConnectRequest$json = {
  '1': 'ConnectRequest',
  '2': [
    {'1': 'host', '3': 1, '4': 1, '5': 9, '10': 'host'},
    {'1': 'port', '3': 2, '4': 1, '5': 13, '10': 'port'},
    {
      '1': 'protocol',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.Protocol',
      '10': 'protocol'
    },
    {'1': 'timeout_ms', '3': 4, '4': 1, '5': 13, '10': 'timeoutMs'},
    {'1': 'connection_id', '3': 5, '4': 1, '5': 13, '10': 'connectionId'},
  ],
};

/// Descriptor for `ConnectRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectRequestDescriptor = $convert.base64Decode(
    'Cg5Db25uZWN0UmVxdWVzdBISCgRob3N0GAEgASgJUgRob3N0EhIKBHBvcnQYAiABKA1SBHBvcn'
    'QSMAoIcHJvdG9jb2wYAyABKA4yFC5QQl9OZXR3b3JrLlByb3RvY29sUghwcm90b2NvbBIdCgp0'
    'aW1lb3V0X21zGAQgASgNUgl0aW1lb3V0TXMSIwoNY29ubmVjdGlvbl9pZBgFIAEoDVIMY29ubm'
    'VjdGlvbklk');

@$core.Deprecated('Use connectResponseDescriptor instead')
const ConnectResponse$json = {
  '1': 'ConnectResponse',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ConnectionState',
      '10': 'state'
    },
    {
      '1': 'error',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ErrorCode',
      '10': 'error'
    },
    {'1': 'resolved_ip', '3': 4, '4': 1, '5': 9, '10': 'resolvedIp'},
  ],
};

/// Descriptor for `ConnectResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List connectResponseDescriptor = $convert.base64Decode(
    'Cg9Db25uZWN0UmVzcG9uc2USIwoNY29ubmVjdGlvbl9pZBgBIAEoDVIMY29ubmVjdGlvbklkEj'
    'EKBXN0YXRlGAIgASgOMhsuUEJfTmV0d29yay5Db25uZWN0aW9uU3RhdGVSBXN0YXRlEisKBWVy'
    'cm9yGAMgASgOMhUuUEJfTmV0d29yay5FcnJvckNvZGVSBWVycm9yEh8KC3Jlc29sdmVkX2lwGA'
    'QgASgJUgpyZXNvbHZlZElw');

@$core.Deprecated('Use sendRequestDescriptor instead')
const SendRequest$json = {
  '1': 'SendRequest',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {'1': 'data', '3': 2, '4': 1, '5': 12, '10': 'data'},
    {'1': 'binary', '3': 3, '4': 1, '5': 8, '10': 'binary'},
  ],
};

/// Descriptor for `SendRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendRequestDescriptor = $convert.base64Decode(
    'CgtTZW5kUmVxdWVzdBIjCg1jb25uZWN0aW9uX2lkGAEgASgNUgxjb25uZWN0aW9uSWQSEgoEZG'
    'F0YRgCIAEoDFIEZGF0YRIWCgZiaW5hcnkYAyABKAhSBmJpbmFyeQ==');

@$core.Deprecated('Use sendResponseDescriptor instead')
const SendResponse$json = {
  '1': 'SendResponse',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {'1': 'bytes_sent', '3': 2, '4': 1, '5': 13, '10': 'bytesSent'},
    {
      '1': 'error',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ErrorCode',
      '10': 'error'
    },
  ],
};

/// Descriptor for `SendResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sendResponseDescriptor = $convert.base64Decode(
    'CgxTZW5kUmVzcG9uc2USIwoNY29ubmVjdGlvbl9pZBgBIAEoDVIMY29ubmVjdGlvbklkEh0KCm'
    'J5dGVzX3NlbnQYAiABKA1SCWJ5dGVzU2VudBIrCgVlcnJvchgDIAEoDjIVLlBCX05ldHdvcmsu'
    'RXJyb3JDb2RlUgVlcnJvcg==');

@$core.Deprecated('Use receiveDataDescriptor instead')
const ReceiveData$json = {
  '1': 'ReceiveData',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {'1': 'data', '3': 2, '4': 1, '5': 12, '10': 'data'},
    {'1': 'binary', '3': 3, '4': 1, '5': 8, '10': 'binary'},
  ],
};

/// Descriptor for `ReceiveData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List receiveDataDescriptor = $convert.base64Decode(
    'CgtSZWNlaXZlRGF0YRIjCg1jb25uZWN0aW9uX2lkGAEgASgNUgxjb25uZWN0aW9uSWQSEgoEZG'
    'F0YRgCIAEoDFIEZGF0YRIWCgZiaW5hcnkYAyABKAhSBmJpbmFyeQ==');

@$core.Deprecated('Use closeRequestDescriptor instead')
const CloseRequest$json = {
  '1': 'CloseRequest',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
  ],
};

/// Descriptor for `CloseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closeRequestDescriptor = $convert.base64Decode(
    'CgxDbG9zZVJlcXVlc3QSIwoNY29ubmVjdGlvbl9pZBgBIAEoDVIMY29ubmVjdGlvbklk');

@$core.Deprecated('Use closeResponseDescriptor instead')
const CloseResponse$json = {
  '1': 'CloseResponse',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {
      '1': 'error',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ErrorCode',
      '10': 'error'
    },
  ],
};

/// Descriptor for `CloseResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closeResponseDescriptor = $convert.base64Decode(
    'Cg1DbG9zZVJlc3BvbnNlEiMKDWNvbm5lY3Rpb25faWQYASABKA1SDGNvbm5lY3Rpb25JZBIrCg'
    'VlcnJvchgCIAEoDjIVLlBCX05ldHdvcmsuRXJyb3JDb2RlUgVlcnJvcg==');

@$core.Deprecated('Use stateChangedDescriptor instead')
const StateChanged$json = {
  '1': 'StateChanged',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ConnectionState',
      '10': 'state'
    },
    {
      '1': 'error',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ErrorCode',
      '10': 'error'
    },
  ],
};

/// Descriptor for `StateChanged`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateChangedDescriptor = $convert.base64Decode(
    'CgxTdGF0ZUNoYW5nZWQSIwoNY29ubmVjdGlvbl9pZBgBIAEoDVIMY29ubmVjdGlvbklkEjEKBX'
    'N0YXRlGAIgASgOMhsuUEJfTmV0d29yay5Db25uZWN0aW9uU3RhdGVSBXN0YXRlEisKBWVycm9y'
    'GAMgASgOMhUuUEJfTmV0d29yay5FcnJvckNvZGVSBWVycm9y');

@$core.Deprecated('Use httpRequestDescriptor instead')
const HttpRequest$json = {
  '1': 'HttpRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 13, '10': 'requestId'},
    {
      '1': 'method',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.HttpMethod',
      '10': 'method'
    },
    {'1': 'url', '3': 3, '4': 1, '5': 9, '10': 'url'},
    {'1': 'headers', '3': 4, '4': 1, '5': 9, '10': 'headers'},
    {'1': 'body', '3': 5, '4': 1, '5': 12, '10': 'body'},
    {'1': 'send_path', '3': 6, '4': 1, '5': 9, '10': 'sendPath'},
    {'1': 'save_path', '3': 7, '4': 1, '5': 9, '10': 'savePath'},
    {'1': 'timeout_ms', '3': 8, '4': 1, '5': 13, '10': 'timeoutMs'},
    {'1': 'include_headers', '3': 9, '4': 1, '5': 8, '10': 'includeHeaders'},
  ],
};

/// Descriptor for `HttpRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List httpRequestDescriptor = $convert.base64Decode(
    'CgtIdHRwUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgNUglyZXF1ZXN0SWQSLgoGbWV0aG9kGA'
    'IgASgOMhYuUEJfTmV0d29yay5IdHRwTWV0aG9kUgZtZXRob2QSEAoDdXJsGAMgASgJUgN1cmwS'
    'GAoHaGVhZGVycxgEIAEoCVIHaGVhZGVycxISCgRib2R5GAUgASgMUgRib2R5EhsKCXNlbmRfcG'
    'F0aBgGIAEoCVIIc2VuZFBhdGgSGwoJc2F2ZV9wYXRoGAcgASgJUghzYXZlUGF0aBIdCgp0aW1l'
    'b3V0X21zGAggASgNUgl0aW1lb3V0TXMSJwoPaW5jbHVkZV9oZWFkZXJzGAkgASgIUg5pbmNsdW'
    'RlSGVhZGVycw==');

@$core.Deprecated('Use httpResponseDescriptor instead')
const HttpResponse$json = {
  '1': 'HttpResponse',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 13, '10': 'requestId'},
    {'1': 'status', '3': 2, '4': 1, '5': 13, '10': 'status'},
    {
      '1': 'error',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.PB_Network.ErrorCode',
      '10': 'error'
    },
    {'1': 'headers', '3': 4, '4': 1, '5': 9, '10': 'headers'},
    {'1': 'body_size', '3': 5, '4': 1, '5': 13, '10': 'bodySize'},
    {'1': 'saved_to_file', '3': 6, '4': 1, '5': 8, '10': 'savedToFile'},
  ],
};

/// Descriptor for `HttpResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List httpResponseDescriptor = $convert.base64Decode(
    'CgxIdHRwUmVzcG9uc2USHQoKcmVxdWVzdF9pZBgBIAEoDVIJcmVxdWVzdElkEhYKBnN0YXR1cx'
    'gCIAEoDVIGc3RhdHVzEisKBWVycm9yGAMgASgOMhUuUEJfTmV0d29yay5FcnJvckNvZGVSBWVy'
    'cm9yEhgKB2hlYWRlcnMYBCABKAlSB2hlYWRlcnMSGwoJYm9keV9zaXplGAUgASgNUghib2R5U2'
    'l6ZRIiCg1zYXZlZF90b19maWxlGAYgASgIUgtzYXZlZFRvRmlsZQ==');

@$core.Deprecated('Use webSocketOpenRequestDescriptor instead')
const WebSocketOpenRequest$json = {
  '1': 'WebSocketOpenRequest',
  '2': [
    {'1': 'connection_id', '3': 1, '4': 1, '5': 13, '10': 'connectionId'},
    {'1': 'url', '3': 2, '4': 1, '5': 9, '10': 'url'},
    {'1': 'headers', '3': 3, '4': 1, '5': 9, '10': 'headers'},
    {'1': 'timeout_ms', '3': 4, '4': 1, '5': 13, '10': 'timeoutMs'},
  ],
};

/// Descriptor for `WebSocketOpenRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List webSocketOpenRequestDescriptor = $convert.base64Decode(
    'ChRXZWJTb2NrZXRPcGVuUmVxdWVzdBIjCg1jb25uZWN0aW9uX2lkGAEgASgNUgxjb25uZWN0aW'
    '9uSWQSEAoDdXJsGAIgASgJUgN1cmwSGAoHaGVhZGVycxgDIAEoCVIHaGVhZGVycxIdCgp0aW1l'
    'b3V0X21zGAQgASgNUgl0aW1lb3V0TXM=');
