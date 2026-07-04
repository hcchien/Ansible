plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// Cargokit builds libansible_rust_core.so per ABI during the Gradle build and
// wires it into this library's jniLibs — the Android twin of the iOS
// build_pod.sh static link. Without it the APK ships no Rust core and every
// identity/signing FFI call fails at runtime.
apply(from = "../cargokit/gradle/plugin.gradle")

extensions.getByName("cargokit").withGroovyBuilder {
    setProperty("manifestDir", "../../../ansible_rust_core")
    setProperty("libname", "ansible_rust_core")
}

android {
    namespace = "io.trisaura.ansible_did"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}
