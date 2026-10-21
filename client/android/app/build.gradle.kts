import java.util.Properties
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
val signing = Properties().apply {
    rootProject.file("key.properties").inputStream().use { load(it) }
}
android {
    namespace = "com.xdl.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.xdl.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        create("existing") {
            storeFile = file(signing.getProperty("storeFile"))
            storePassword = signing.getProperty("storePassword")
            keyAlias = signing.getProperty("keyAlias")
            keyPassword = signing.getProperty("keyPassword")
        }
    }
    flavorDimensions += "distribution"
    productFlavors {
        create("production") { dimension = "distribution" }
        create("probe") {
            dimension = "distribution"
            applicationIdSuffix = ".probe"
        }
    }
    buildTypes {
        debug { signingConfig = signingConfigs.getByName("existing") }
        release { signingConfig = signingConfigs.getByName("existing") }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }

dependencies { implementation("androidx.core:core:1.17.0") }
