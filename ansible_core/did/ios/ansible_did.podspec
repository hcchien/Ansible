Pod::Spec.new do |s|
  s.name             = 'ansible_did'
  s.version          = '0.1.0'
  s.summary          = 'DID key management & DID-auth for Ansible (flutter_rust_bridge FFI plugin).'
  s.description      = 'Ed25519 DID operations, ZKP proof generation, and CRDT support via Rust.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Ansible' => 'ansible@example.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*'

  s.dependency 'Flutter'

  s.platform = :ios, '13.0'
  s.swift_version = '5.0'

  # Build & link the Rust core (ansible_rust_core lives at the repo root).
  # cargokit cross-compiles a static lib for the active iOS arch(s);
  # -force_load links it so the flutter_rust_bridge FFI symbols are retained.
  #   $1 = path to the crate dir, relative to PODS_TARGET_SRCROOT (the plugin's
  #        ios/ dir): ../../../ansible_rust_core -> <repo>/ansible_rust_core
  #   $2 = static lib (crate [lib] name) -> libansible_rust_core.a
  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../ansible_rust_core ansible_rust_core',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${PODS_CONFIGURATION_BUILD_DIR}/ansible_did/libansible_rust_core.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/ansible_did/libansible_rust_core.a',
  }
end
