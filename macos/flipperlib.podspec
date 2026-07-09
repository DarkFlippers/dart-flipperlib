Pod::Spec.new do |s|
  s.name             = 'flipperlib'
  s.version          = '0.1.0'
  s.summary          = 'Vendored libusb for Flipper Zero DFU / recovery on macOS'
  s.description      = s.summary
  s.homepage         = 'https://github.com/apfxtech'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'apfxtech' => 'aperturefoxtechnology@gmail.com' }
  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'

  # Vendored libusb 1.0 for raw-USB DFU / recovery (STM32 bootloader access).
  # The dylib is bundled into the app and resolved at runtime via @rpath; the
  # FFI bindings live in lib/dfu/libusb.
  s.vendored_libraries = 'Libraries/libusb-1.0.0.dylib'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = {
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks',
  }
end
