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
  s.swift_version = '5.0'

  # Build & link the Rust core, mirroring ios/ansible_did.podspec. Without this
  # the macOS app has no ansible_rust_core symbols and the frb loader fails with
  # "Failed to load dynamic library 'ansible_rust_core.framework/...'". cargokit
  # cross-compiles the static lib for the active macOS arch; -force_load keeps
  # the flutter_rust_bridge FFI symbols so the in-process loader resolves them.
  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../ansible_rust_core ansible_rust_core',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${PODS_CONFIGURATION_BUILD_DIR}/ansible_did/libansible_rust_core.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/ansible_did/libansible_rust_core.a',
  }
end
