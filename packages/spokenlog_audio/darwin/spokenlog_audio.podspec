Pod::Spec.new do |s|
  s.name             = 'spokenlog_audio'
  s.version          = '0.0.1'
  s.summary          = 'SpokenLog native audio picker, WAV decoder and file intake.'
  s.homepage         = 'https://github.com/Blue-B/SpokenLog'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'SpokenLog' => 'https://github.com/Blue-B/SpokenLog' }
  s.source           = { :path => '.' }
  s.source_files     = 'spokenlog_audio/Sources/spokenlog_audio/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
