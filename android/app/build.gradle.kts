plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.encryptedfiles.encrypted_files"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.encryptedfiles.encrypted_files"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    externalNativeBuild {
        cmake {
            path("../../native/CMakeLists.txt")
        }
    }
}

flutter {
    source = "../.."
}

// The Gradle build directory is redirected to /tmp/EncryptedFiles_build (see
// android/build.gradle.kts) because the project lives on a VirtualBox shared
// folder, where creating the deep Gradle output tree fails. The Flutter tool,
// however, looks for the finished APKs at <project>/build/app/outputs/flutter-apk/.
// Publish a copy of the APKs there right after assemble* finishes.
val flutterProjectDir = rootProject.projectDir.parentFile

val publishFlutterApks = tasks.register("publishFlutterApks") {
    doLast {
        val sourceDir = File("/tmp/EncryptedFiles_build/app/outputs/flutter-apk")
        val targetDir = File(File(File(flutterProjectDir, "build/app"), "outputs"), "flutter-apk")
        val apks = sourceDir.listFiles { f -> f.isFile && f.extension == "apk" }
        if (apks.isNullOrEmpty()) {
            logger.warn("No APKs found in ${sourceDir.absolutePath}; nothing to publish.")
            return@doLast
        }
        if (!targetDir.isDirectory && !targetDir.mkdirs()) {
            throw GradleException(
                "Could not create ${targetDir.absolutePath}. " +
                    "The built APKs are available at ${sourceDir.absolutePath}.",
            )
        }
        apks.forEach { apk ->
            apk.copyTo(File(targetDir, apk.name), overwrite = true)
            logger.lifecycle("Published ${apk.name} to ${File(targetDir, apk.name).absolutePath}")
        }
    }
}

// AGP registers the assemble* variant tasks only during afterEvaluate, so an eager
// tasks.named(...) lookup here would fail with "Task with name 'assembleRelease' not
// found". Wire the finalizer lazily instead: configureEach applies to current and
// future tasks named assembleRelease/assembleDebug, whenever AGP creates them.
tasks.matching { it.name == "assembleRelease" || it.name == "assembleDebug" }
    .configureEach {
        finalizedBy(publishFlutterApks)
    }
