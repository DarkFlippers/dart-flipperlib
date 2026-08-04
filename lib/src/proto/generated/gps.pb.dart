// This is a generated file - do not edit.
//
// Generated from gps.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class StreamStartRequest extends $pb.GeneratedMessage {
  factory StreamStartRequest({
    $core.int? frequency,
  }) {
    final result = create();
    if (frequency != null) result.frequency = frequency;
    return result;
  }

  StreamStartRequest._();

  factory StreamStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StreamStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gps'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'frequency', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamStartRequest copyWith(void Function(StreamStartRequest) updates) =>
      super.copyWith((message) => updates(message as StreamStartRequest))
          as StreamStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamStartRequest create() => StreamStartRequest._();
  @$core.override
  StreamStartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StreamStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamStartRequest>(create);
  static StreamStartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get frequency => $_getIZ(0);
  @$pb.TagNumber(1)
  set frequency($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFrequency() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrequency() => $_clearField(1);
}

class StreamStopRequest extends $pb.GeneratedMessage {
  factory StreamStopRequest() => create();

  StreamStopRequest._();

  factory StreamStopRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StreamStopRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamStopRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gps'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamStopRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamStopRequest copyWith(void Function(StreamStopRequest) updates) =>
      super.copyWith((message) => updates(message as StreamStopRequest))
          as StreamStopRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamStopRequest create() => StreamStopRequest._();
  @$core.override
  StreamStopRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StreamStopRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamStopRequest>(create);
  static StreamStopRequest? _defaultInstance;
}

class LocationRequest extends $pb.GeneratedMessage {
  factory LocationRequest() => create();

  LocationRequest._();

  factory LocationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LocationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gps'),
      createEmptyInstance: create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocationRequest copyWith(void Function(LocationRequest) updates) =>
      super.copyWith((message) => updates(message as LocationRequest))
          as LocationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocationRequest create() => LocationRequest._();
  @$core.override
  LocationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LocationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LocationRequest>(create);
  static LocationRequest? _defaultInstance;
}

class Location extends $pb.GeneratedMessage {
  factory Location({
    $core.int? latitude,
    $core.int? longitude,
    $core.int? heading,
    $core.int? speed,
    $core.int? altitude,
    $core.int? accuracy,
    $core.int? satellites,
  }) {
    final result = create();
    if (latitude != null) result.latitude = latitude;
    if (longitude != null) result.longitude = longitude;
    if (heading != null) result.heading = heading;
    if (speed != null) result.speed = speed;
    if (altitude != null) result.altitude = altitude;
    if (accuracy != null) result.accuracy = accuracy;
    if (satellites != null) result.satellites = satellites;
    return result;
  }

  Location._();

  factory Location.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Location.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Location',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'PB_Gps'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'latitude', fieldType: $pb.PbFieldType.OS3)
    ..aI(2, _omitFieldNames ? '' : 'longitude', fieldType: $pb.PbFieldType.OS3)
    ..aI(3, _omitFieldNames ? '' : 'heading', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'speed', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'altitude', fieldType: $pb.PbFieldType.OS3)
    ..aI(6, _omitFieldNames ? '' : 'accuracy', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'satellites', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Location clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Location copyWith(void Function(Location) updates) =>
      super.copyWith((message) => updates(message as Location)) as Location;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Location create() => Location._();
  @$core.override
  Location createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Location getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Location>(create);
  static Location? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get latitude => $_getIZ(0);
  @$pb.TagNumber(1)
  set latitude($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatitude() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatitude() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get longitude => $_getIZ(1);
  @$pb.TagNumber(2)
  set longitude($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLongitude() => $_has(1);
  @$pb.TagNumber(2)
  void clearLongitude() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get heading => $_getIZ(2);
  @$pb.TagNumber(3)
  set heading($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeading() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeading() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get speed => $_getIZ(3);
  @$pb.TagNumber(4)
  set speed($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSpeed() => $_has(3);
  @$pb.TagNumber(4)
  void clearSpeed() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get altitude => $_getIZ(4);
  @$pb.TagNumber(5)
  set altitude($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAltitude() => $_has(4);
  @$pb.TagNumber(5)
  void clearAltitude() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get accuracy => $_getIZ(5);
  @$pb.TagNumber(6)
  set accuracy($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAccuracy() => $_has(5);
  @$pb.TagNumber(6)
  void clearAccuracy() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get satellites => $_getIZ(6);
  @$pb.TagNumber(7)
  set satellites($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSatellites() => $_has(6);
  @$pb.TagNumber(7)
  void clearSatellites() => $_clearField(7);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
