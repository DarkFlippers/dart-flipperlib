Pod::Spec.new do |s|
  s.name             = 'flipperlib'
  s.version          = '1.0.0'
  s.summary          = 'Flipper Zero client for Flutter — iOS support'
  s.description      = s.summary
  s.homepage         = 'https://github.com/apfxtech'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'apfxtech' => 'aperturefoxtechnology@gmail.com' }
  s.source           = { :path => '.' }
  s.dependency 'Flutter'

  # No vendored native code on iOS: BLE goes through universal_ble and there is
  # no raw-USB DFU path. The pod exists so the plugin declares iOS support.
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
