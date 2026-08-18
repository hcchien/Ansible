import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

android {
    namespace = "io.trisaura.ansible_node"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.reviz.elix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let(::file)
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// The native ZK backend is a source-built, pinned Rust cdylib rather than an
// opaque downloaded binary.  Its ABI files are generated before every Android
// build and are never checked into the repository.
val buildZkPassportNative by tasks.registering(Exec::class) {
    workingDir = file("../zkpassport-prover")
    commandLine("bash", "scripts/build-android.sh")
    environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
}

tasks.configureEach {
    if (name.startsWith("pre") && name.endsWith("Build")) {
        dependsOn(buildZkPassportNative)
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
    // ICAO 9303 eMRTD protocol stack.  The reader uses only BAC/PACE plus
    // DG1/SOD; it never requests DG2 or other biometric data groups.
    implementation("org.jmrtd:jmrtd:0.8.6")
    implementation("net.sf.scuba:scuba-sc-android:0.0.26")
    implementation("org.bouncycastle:bcprov-jdk18on:1.84")
    implementation("org.bouncycastle:bcpkix-jdk18on:1.84")
}

flutter {
    source = "../.."
}
