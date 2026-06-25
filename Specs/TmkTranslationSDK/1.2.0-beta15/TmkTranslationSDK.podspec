Pod::Spec.new do |s|
  version = '1.2.0-beta15'
  tag = 'v1.2.0-beta15'

  s.name             = 'TmkTranslationSDK'
  s.version          = version
  s.summary          = 'Timekettle Translation SDK'
  s.description      = 'Timekettle Translation SDK binary distribution.'
  s.homepage         = 'https://github.com/timekettle/tmk-translation-sdk'
  s.license          = { :type => 'Proprietary', :text => 'Internal use only.' }
  s.author           = { 'timekettle' => 'dev@timekettle.co' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'

  s.source           = { :git => 'git@github.com:timekettle/TmkTranslationSDK-xcframework.git', :tag => tag }
  s.vendored_frameworks = 'TmkTranslationSDK.xcframework'
  s.frameworks       = 'AVFoundation', 'AudioToolbox', 'UIKit', 'Foundation'
  s.libraries        = 'z'

  s.dependency       'AgoraAudio_Special_iOS', '~> 4.5.2.4'
  s.dependency       'AgoraRtm/RtmKit', '2.2.6'
end
