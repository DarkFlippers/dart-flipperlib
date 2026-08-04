// This is a generated file - do not edit.
//
// Generated from gps.proto.

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

@$core.Deprecated('Use streamStartRequestDescriptor instead')
const StreamStartRequest$json = {
  '1': 'StreamStartRequest',
  '2': [
    {'1': 'frequency', '3': 1, '4': 1, '5': 13, '10': 'frequency'},
  ],
};

/// Descriptor for `StreamStartRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamStartRequestDescriptor =
    $convert.base64Decode(
        'ChJTdHJlYW1TdGFydFJlcXVlc3QSHAoJZnJlcXVlbmN5GAEgASgNUglmcmVxdWVuY3k=');

@$core.Deprecated('Use streamStopRequestDescriptor instead')
const StreamStopRequest$json = {
  '1': 'StreamStopRequest',
};

/// Descriptor for `StreamStopRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List streamStopRequestDescriptor =
    $convert.base64Decode('ChFTdHJlYW1TdG9wUmVxdWVzdA==');

@$core.Deprecated('Use locationRequestDescriptor instead')
const LocationRequest$json = {
  '1': 'LocationRequest',
};

/// Descriptor for `LocationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List locationRequestDescriptor =
    $convert.base64Decode('Cg9Mb2NhdGlvblJlcXVlc3Q=');

@$core.Deprecated('Use locationDescriptor instead')
const Location$json = {
  '1': 'Location',
  '2': [
    {'1': 'latitude', '3': 1, '4': 1, '5': 17, '10': 'latitude'},
    {'1': 'longitude', '3': 2, '4': 1, '5': 17, '10': 'longitude'},
    {'1': 'heading', '3': 3, '4': 1, '5': 13, '10': 'heading'},
    {'1': 'speed', '3': 4, '4': 1, '5': 13, '10': 'speed'},
    {'1': 'altitude', '3': 5, '4': 1, '5': 17, '10': 'altitude'},
    {'1': 'accuracy', '3': 6, '4': 1, '5': 13, '10': 'accuracy'},
    {'1': 'satellites', '3': 7, '4': 1, '5': 13, '10': 'satellites'},
  ],
};

/// Descriptor for `Location`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List locationDescriptor = $convert.base64Decode(
    'CghMb2NhdGlvbhIaCghsYXRpdHVkZRgBIAEoEVIIbGF0aXR1ZGUSHAoJbG9uZ2l0dWRlGAIgAS'
    'gRUglsb25naXR1ZGUSGAoHaGVhZGluZxgDIAEoDVIHaGVhZGluZxIUCgVzcGVlZBgEIAEoDVIF'
    'c3BlZWQSGgoIYWx0aXR1ZGUYBSABKBFSCGFsdGl0dWRlEhoKCGFjY3VyYWN5GAYgASgNUghhY2'
    'N1cmFjeRIeCgpzYXRlbGxpdGVzGAcgASgNUgpzYXRlbGxpdGVz');
