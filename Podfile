platform :ios, '18.0'

target 'Yuanyuan' do
  use_frameworks!
  
  # 阿里云 OSS SDK
  pod 'AliyunOSSiOS', '~> 2.10.19'
  
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    end
  end
end

