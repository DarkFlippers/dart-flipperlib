Pod::Spec.new do |s|
  s.name             = 'flipperlib'
  s.version          = '1.0.0'
  s.summary          = 'libusb for Flipper Zero DFU / recovery on macOS, built from source'
  s.description      = s.summary
  s.homepage         = 'https://github.com/apfxtech'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'apfxtech' => 'aperturefoxtechnology@gmail.com' }
  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'

  # libusb 1.0 (darwin backend) compiled into this pod from the sources shared
  # with the Windows and Android builds in ../src/libusb. Podspecs can not
  # reference files outside the pod directory, so Classes/ holds one forwarder
  # per libusb translation unit that #includes the real file. Only the libusb
  # API is exported (visibility hidden otherwise); the Dart side resolves it
  # through DynamicLibrary.process() (see lib/src/dfu/libusb).
  s.source_files = 'Classes/**/*'
  s.frameworks = 'IOKit', 'CoreFoundation', 'Security'
  s.libraries = 'objc'
  s.compiler_flags = '-fvisibility=hidden'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/../src/libusb/darwin" "$(PODS_TARGET_SRCROOT)/../src/libusb/libusb"',
  }
end
