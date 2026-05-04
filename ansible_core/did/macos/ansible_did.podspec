Pod::Spec.new do |s|
  s.name             = 'ansible_did'
  s.version          = '0.1.0'
  s.summary          = 'DID key management & DID-auth for Ansible (flutter_rust_bridge FFI plugin).'
  s.description      = 'Ed25519 DID operations, ZKP proof generation, and CRDT support via Rust.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Ansible' => 'ansible@example.com' }
  s.source           = { :path => '.' }

  # FFI plugins have no Objective-C/Swift sources — the Rust dylib is compiled
  # and linked by Flutter's build system.  CocoaPods only needs the podspec to
  # know the plugin exists and to pull in the FlutterMacOS dependency.
  s.source_files     = 'Classes/**/*.{h,m,swift}'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
