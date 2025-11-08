Pod::Spec.new do |s|
  s.name             = 'llama'
  s.version          = '1.0.0'
  s.summary          = 'llama.cpp iOS framework'
  s.description      = 'llama.cpp framework for iOS'
  s.homepage         = 'https://github.com/ggerganov/llama.cpp'
  s.license          = { :type => 'MIT' }
  s.author           = { 'llama.cpp' => 'llama.cpp' }
  s.source           = { :path => '.' }
  
  s.ios.deployment_target = '13.0'
  
  # Use XCFramework for both device and simulator
  s.vendored_frameworks = 'llama.xcframework'
  s.frameworks = 'Foundation', 'Accelerate'
end
