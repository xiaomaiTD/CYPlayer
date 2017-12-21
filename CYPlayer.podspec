
Pod::Spec.new do |s|

s.name         = "CYPlayer"
s.version      = "1.1.1"
s.summary      = 'A video player.'
s.description  = 'https://github.com/yellowei/CYPlayer'
s.homepage     = 'https://github.com/yellowei/CYPlayer'
s.license      = { :type => "MIT", :file => "FILE_LICENSE" }
s.author             = { "yellowei" => "hw0521@vip.qq.com" }
s.platform     = :ios, "8.0"
s.source       = { :git => 'https://github.com/yellowei/CYPlayer.git', :tag => "#{s.version}" }
s.resource     = 'CYPlayer/CYVideoPlayer/Resource/CYVideoPlayer.bundle'
s.frameworks  = "UIKit", "AVFoundation"
s.requires_arc = true
s.dependency 'Masonry'


s.subspec 'CYAttributesFactory' do |ss|
ss.source_files = 'CYPlayer/CYAttributesFactory/*.{*}'
end

s.subspec 'CYBorderLineView' do |ss|
ss.source_files = 'CYPlayer/CYBorderLineView/*.{h*}'
end

s.subspec 'CYObserverHelper' do |ss|
ss.source_files = 'CYPlayer/CYObserverHelper/*.{*}'
end

s.subspec 'CYOrentationObserver' do |ss|
ss.source_files = 'CYPlayer/CYOrentationObserver/*.{*}'
end

s.subspec 'CYPrompt' do |ss|
ss.source_files = 'CYPlayer/CYPrompt/*.{*}'
end

s.subspec 'CYSlider' do |ss|
ss.source_files = 'CYPlayer/CYSlider/*.{*}'
end

s.subspec 'CYUIFactory' do |ss|

ss.source_files = 'CYPlayer/CYUIFactory/*.{*}'

ss.subspec 'Category' do |sss|
sss.source_files = 'CYPlayer/CYUIFactory/Category/*.{*}'
end

end

# s.subspec 'CYVideoPlayerBackGR' do |ss|
# ss.source_files = 'CYPlayer/CYVideoPlayerBackGR/*.{*}'
# ss.dependency 'CYPlayer/CYObserverHelper'
# end

s.subspec 'CYVideoPlayer' do |ss|

ss.source_files = 'CYPlayer/CYVideoPlayer/*.{h}'

# # ss.dependency 'CYPlayer/CYUIFactory/Category'
ss.dependency 'CYPlayer/CYUIFactory'
ss.dependency 'CYPlayer/CYPrompt'
ss.dependency 'CYPlayer/CYAttributesFactory'
ss.dependency 'CYPlayer/CYOrentationObserver'
ss.dependency 'CYPlayer/CYSlider'
ss.dependency 'CYPlayer/CYBorderLineView'
ss.dependency 'CYPlayer/CYObserverHelper'
# ss.dependency 'CYPlayer/CYVideoPlayerBackGR'

# ########
ss.subspec 'Header' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Header/*.{h}'
end

ss.subspec 'Model' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Model/*.{h,m}'
end

ss.subspec 'Resource' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Resource/*.{h,m}'
end

ss.subspec 'Base' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Base/*.{h,m}'
sss.dependency 'CYPlayer/CYVideoPlayer/Header'
sss.dependency 'CYPlayer/CYVideoPlayer/Model'
sss.dependency 'CYPlayer/CYVideoPlayer/Resource'
# sss.dependency 'CYPlayer/CYUIFactory'
# # sss.dependency 'CYPlayer/CYUIFactory/Category'
# sss.dependency 'CYPlayer/CYPrompt'
# sss.dependency 'CYPlayer/CYSlider'
# sss.dependency 'CYPlayer/CYOrentationObserver'
# sss.dependency 'CYPlayer/CYAttributesFactory'
# sss.dependency 'CYPlayer/CYBorderLineView'
end

ss.subspec 'Other' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Other/*.{h,m}'
sss.dependency 'CYPlayer/CYVideoPlayer/Base'
end

ss.subspec 'Player' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Player/*.{h,m}'
sss.dependency 'CYPlayer/CYVideoPlayer/Control'
sss.dependency 'CYPlayer/CYVideoPlayer/Loading'
sss.dependency 'CYPlayer/CYVideoPlayer/MoreSetting'
sss.dependency 'CYPlayer/CYVideoPlayer/VolBrigControl'
sss.dependency 'CYPlayer/CYVideoPlayer/Present'
sss.dependency 'CYPlayer/CYVideoPlayer/Registrar'
sss.dependency 'CYPlayer/CYVideoPlayer/TimerControl'
sss.dependency 'CYPlayer/CYVideoPlayer/GestureControl'
# sss.dependency 'CYPlayer/CYUIFactory/Category'
# sss.dependency 'CYPlayer/CYUIFactory'
# sss.dependency 'CYPlayer/CYPrompt'
# sss.dependency 'CYPlayer/CYSlider'
# sss.dependency 'CYPlayer/CYAttributesFactory'
# sss.dependency 'CYPlayer/CYOrentationObserver'
end



ss.subspec 'Control' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Control/*.{h,m}'
sss.dependency 'CYPlayer/CYVideoPlayer/Other'
# sss.dependency 'CYPlayer/CYUIFactory/Category'
# sss.dependency 'CYPlayer/CYUIFactory'
# sss.dependency 'CYPlayer/CYSlider'
# sss.dependency 'CYPlayer/CYAttributesFactory'
end

ss.subspec 'GestureControl' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/GestureControl/*.{h,m}'
end

ss.subspec 'Loading' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Loading/*.{h,m}'
end

ss.subspec 'MoreSetting' do |sss|

sss.dependency 'CYPlayer/CYVideoPlayer/Other'
# sss.dependency 'CYPlayer/CYSlider'

sss.subspec 'MoreSetting' do |ssss|
ssss.source_files = 'CYPlayer/CYVideoPlayer/MoreSetting/MoreSetting/*.{h,m}'
end

sss.subspec 'Secondary' do |ssss|
ssss.source_files = 'CYPlayer/CYVideoPlayer/MoreSetting/Secondary/*.{h,m}'
end

end

ss.subspec 'VolBrigControl' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/VolBrigControl/*.{h,m}'
sss.dependency 'CYPlayer/CYVideoPlayer/Other'
# sss.dependency 'CYPlayer/CYSlider'
# sss.dependency 'CYPlayer/CYBorderLineView'
end



ss.subspec 'Present' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Present/*.{h,m}'
sss.dependency 'CYPlayer/CYVideoPlayer/Other'
end

ss.subspec 'Registrar' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/Registrar/*.{h,m}'
end

ss.subspec 'TimerControl' do |sss|
sss.source_files = 'CYPlayer/CYVideoPlayer/TimerControl/*.{h,m}'
end


# ########

end

end