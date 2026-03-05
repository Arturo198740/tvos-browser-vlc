source 'https://cdn.cocoapods.org'
platform :tvos, '13.0'
use_frameworks!
inhibit_all_warnings!

target 'BrowserVLC' do
  pod 'VLCKit', '~> 3.6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['TVOS_DEPLOYMENT_TARGET'] = '13.0'
      config.build_settings['ARCHS'] = 'arm64 x86_64'
    end
  end
end
