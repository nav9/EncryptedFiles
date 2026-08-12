allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// IMPORTANT: All Gradle build outputs are redirected to a local /tmp directory.
//
// This project is normally checked out inside a VirtualBox shared folder (e.g.
// /media/sf_shared). The vboxsf automount cannot reliably create the deep Gradle
// output tree (build/app/intermediates/...) and the build fails with
// "Failed to create parent directory '/media/sf_shared' ..." if outputs are
// written into the project directory. /tmp is always a local, writable filesystem,
// so building there succeeds.
//
// The Flutter tool expects the finished APKs at <project>/build/app/outputs/flutter-apk/,
// so the "publishFlutterApks" task in android/app/build.gradle.kts copies them there
// right after assembleRelease finishes.
val newBuildDir = File("/tmp/EncryptedFiles_build")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = File(newBuildDir, project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
