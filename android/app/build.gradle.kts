plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}
android {
    namespace = "com.paply.android"
    buildToolsVersion = "37.0.0"
    compileSdk { version = release(37) { minorApiLevel = 2 } }
    defaultConfig {
        applicationId = "com.paply.android"
        minSdk = 29
        targetSdk = 37
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        versionCode = 1
        versionName = "0.0.1-phase0"
    }
    signingConfigs.getByName("debug") {
        // All generated credentials stay in the remote work directory, never SDK/user-home.
        storeFile = rootProject.file(".local/debug.keystore")
    }
    buildFeatures { buildConfig = true; compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
dependencies {
    implementation(project(":core"))
    implementation(project(":thoughts"))
    implementation("androidx.work:work-runtime-ktx:2.12.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation(libs.junit)
    testImplementation(libs.junit)
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("org.json:json:20240303")
    implementation(libs.androidx.core)
    implementation(libs.coroutines.android)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.compose)
    implementation(libs.datastore)
}
