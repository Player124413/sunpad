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

        // Pin the same NDK that scripts/android-build-core.sh uses for the
        // core; AGP's default NDK (26.1, clang 17) does not accept
        // -std=c++23.
        ndkVersion = "26.3.11579264"

        ndk {
            // The runtime and game module are arm64 only (AOT recompiled
            // host code; no 32-bit or x86 product path).
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                // No -std flag here: app/src/main/cpp/CMakeLists.txt sets
                // CMAKE_CXX_STANDARD 23 and CMake picks the right spelling
                // for the compiler (c++2b on NDK clang 17, c++23 on 18+).
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
