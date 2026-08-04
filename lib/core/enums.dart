part of '../flipper_client.dart';

enum FlipperLink { 
  usb, 
  ble 
}

enum FlipperMode { 
  disconnected, 
  cli, 
  rpc 
}

enum FlipperRequestPriority {
  rightNow,
  foreground,
  defaultPriority,
  background,
}
