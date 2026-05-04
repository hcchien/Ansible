Pod::Spec.new do |s|
  s.name             = 'ansible_did'
  s.version          = '0.1.0'
  s.summary          = 'DID key management & DID-auth for Ansible (flutter_rust_bridge FFI plugin).'
  s.description      = 'Ed25519 DID operations, ZKP proof generation, and CRDT support via Rust.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Ansible' => 'ansible@example.com' }
  s.source           = { :path => '.' }

  # FFI plugins have no Objective-C/Swift implementation here. CocoaPods only
  # needs a pod target so Flutter can register the plugin on iOS.
  s.source_files     = 'Classes/**/*.{h,m,swift}'

  s.dependency 'Flutter'

  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
