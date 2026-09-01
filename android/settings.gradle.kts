pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Processes android/app/google-services.json into the resources
    // Firebase Cloud Messaging looks for at runtime. firebase_core itself
    // initialises from lib/firebase_options.dart, but FCM on Android does
    // not - without this, push registration fails on a device while
    // everything else works, which is a hard failure to place.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
