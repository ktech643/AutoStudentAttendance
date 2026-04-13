Pod::Spec.new do |s|
  s.name             = 'ios_face_attendance_plugin'
  s.version          = '0.1.0'
  s.summary          = 'Native iOS face attendance plugin for Flutter.'
  s.description      = <<-DESC
Native iOS pipeline using AVFoundation + Vision with CoreML embedding integration point.
                       DESC
  s.homepage         = 'https://example.local/ios_face_attendance_plugin'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'School Engineering' => 'eng@school.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'AVFoundation', 'Vision', 'CoreImage', 'CoreML', 'Accelerate'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
