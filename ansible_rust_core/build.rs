fn main() {
    // flutter_rust_bridge codegen is run separately via:
    //   flutter_rust_bridge_codegen generate
    // This file intentionally left minimal.
    println!("cargo:rerun-if-changed=src/");
}
