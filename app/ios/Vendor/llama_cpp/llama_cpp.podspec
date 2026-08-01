#
# Vendored xcframework for llama_cpp_dart on iOS / macOS.
#
# Usage from a Flutter app's iOS or macOS Podfile:
#
#   target 'Runner' do
#     ...
#     pod 'llama_cpp', :path => '../../llama_cpp_dart'   # adjust path
#   end
#
# This points the Flutter target at the prebuilt DYNAMIC xcframework so it
# gets embedded + signed automatically. App code calls
# `LlamaEngine.spawnFromProcess(...)`: dyld loads the embedded framework at
# launch, so its symbols are already in the process (no -force_load, no
# runtime dlopen path needed).
#
# DHRUVA NOTE: this copy is wired into app/ios/Podfile ONLY (iOS target).
# scripts/fetch-ios-xcframework.sh deliberately drops the macos-arm64 slice
# from the upstream zip (32MB of 53MB) — Dhruva's macOS dev/test build loads
# raw dylibs from app/.dev-native/macos instead of this pod (see
# test/native_test_config.dart), so a macOS slice here would be dead weight.
# If this pod is ever wired into a macOS Podfile too, re-run the fetch script
# with DROP_SLICES=() and re-vendor before doing so.
#
Pod::Spec.new do |s|
  s.name             = 'llama_cpp'
  s.version          = '0.9.0-dev.9'
  s.summary          = 'llama.cpp xcframework for iOS / macOS via llama_cpp_dart.'
  s.description      = <<-DESC
    Prebuilt llama.cpp + ggml + mtmd as an xcframework, vendored for use from
    Flutter apps that depend on the llama_cpp_dart binding. Upstream ships
    three slices (ios-arm64, ios-arm64-simulator, macos-arm64); Dhruva vendors
    only the two iOS slices (see DHRUVA NOTE above).
  DESC
  s.homepage         = 'https://github.com/netdur/llama_cpp_dart'
  s.license          = { :type => 'MIT' }
  s.author           = { 'netdur' => 'noreply@netdur.dev' }
  s.source           = { :path => '.' }

  s.ios.deployment_target = '14.0'

  s.vendored_frameworks = 'build/apple/llama.xcframework'

  # System frameworks the dynamic llama.framework links against. They are
  # already recorded as load commands inside the dylib, so dyld pulls them
  # in automatically; declaring them here is belt-and-suspenders.
  s.frameworks = 'Metal', 'MetalKit', 'Foundation', 'Accelerate'

  # NOTE: llama.framework is a *dynamic* framework (self-contained dylib with
  # @rpath/llama.framework/llama install name). CocoaPods embeds + signs it,
  # dyld loads it at launch, and its symbols are visible to
  # DynamicLibrary.process(). No -force_load — that was only needed back when
  # the framework shipped as a static archive, and it actively breaks a
  # dynamic one.
end
