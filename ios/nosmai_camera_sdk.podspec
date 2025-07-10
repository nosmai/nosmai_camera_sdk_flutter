Pod::Spec.new do |s|
  s.name             = 'nosmai_camera_sdk'
  s.version          = '1.0.2+1'
  s.summary          = 'A Flutter plugin for applying real-time camera filters with live preview.'
  s.description      = <<-DESC
    Nosmai is a closed-source iOS SDK that allows developers to apply real-time visual filters on a live camera feed.
    It enables a seamless and interactive user experience through dynamic overlays and effects.

    To use the SDK, developers must register a project through the Nosmai portal and obtain a unique API key.
    The API key is used to initialize the camera view and enable filtering capabilities.
  DESC
  s.homepage         = 'https://github.com/nosmai/nosmai_camera_sdk_flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Nosmai' => 'admin@nosmai.com' }
  s.source           = { :git => 'https://github.com/nosmai/nosmai_camera_sdk_flutter.git', :tag => s.version.to_s }
  s.dependency 'Flutter'
  s.dependency 'NosmaiCameraSDK', '~> 1.0.7'
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  
  s.platform = :ios, '14.0'

  # Required frameworks
  s.frameworks = 'AVFoundation', 'CoreMedia', 'CoreVideo', 'OpenGLES', 'QuartzCore', 'UIKit', 'Foundation'

  # Pod target configuration
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_TARGET_SRCROOT)',
    'HEADER_SEARCH_PATHS' => '$(inherited) $(PODS_TARGET_SRCROOT)/nosmai.framework/Headers',
    'OTHER_LDFLAGS' => '$(inherited) -framework nosmai'
  }

  # Additional compiler flags if needed
  s.compiler_flags = '-Dnosmai_camera_sdk_PLUGIN=1'
end