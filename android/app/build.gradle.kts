plugins { alias(libs.plugins.android.application) }
android {
    namespace = "com.paply.android"
    buildToolsVersion = "37.0.0"
    compileSdk { version = release(37) { minorApiLevel = 2 } }
    defaultConfig {
        applicationId = "com.paply.android"
        minSdk = 29
        targetSdk = 37
        versionCode = 1
        versionName = "0.0.1-phase0"
    }
    signingConfigs.getByName("debug") {
        // All generated credentials stay in the remote work directory, never SDK/user-home.
        storeFile = rootProject.file(".local/debug.keystore")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core)
    implementation(libs.coroutines.android)
}
