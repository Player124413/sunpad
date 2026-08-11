plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.sunpad.android"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.sunpad.android"
        minSdk = 26            // Android 8.0: Vulkan 1.0 + OpenSL ES baseline
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0-android-preview.1"

        ndk {
            // The runtime and game module are arm64 only (AOT recompiled
            // host code; no 32-bit or x86 product path).
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++23")
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        debug {
            isJniDebuggable = true
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
