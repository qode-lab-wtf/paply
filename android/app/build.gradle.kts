import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}
// Signing material belongs to the MacBook user, never to a checkout.
val releaseProperties = Properties()
val releasePropertiesFile = File(System.getProperty("user.home"), "Android/keys/paply-release.properties")
if (releasePropertiesFile.isFile) releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
fun releaseSecret(property: String, environment: String): String? =
    providers.environmentVariable(environment).orNull?.takeIf { it.isNotBlank() }
        ?: releaseProperties.getProperty(property)?.takeIf { it.isNotBlank() }
val releaseStorePath = releaseSecret("storeFile", "PAPLY_RELEASE_STORE_FILE")
val releaseStorePassword = releaseSecret("storePassword", "PAPLY_RELEASE_STORE_PASSWORD")
val releaseAlias = releaseSecret("keyAlias", "PAPLY_RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseSecret("keyPassword", "PAPLY_RELEASE_KEY_PASSWORD") ?: releaseStorePassword
val releaseValues = listOf(releaseStorePath, releaseStorePassword, releaseAlias, releaseKeyPassword)
val releaseSigningReady = releaseValues.all { it != null }
require(releaseValues.all { it == null } || releaseSigningReady) {
    "Paply: Release-Signierung unvollständig. Properties oder PAPLY_RELEASE_* vervollständigen (siehe android/README.md)."
}
if (releaseSigningReady) {
    val configuredKeyFile = File(releaseStorePath!!)
    val keyFile = configuredKeyFile.canonicalFile
    val checkout = generateSequence(rootDir.canonicalFile) { it.parentFile }
        .firstOrNull { File(it, ".git").exists() } ?: rootDir.canonicalFile
    require(configuredKeyFile.isAbsolute && keyFile.isFile && !keyFile.toPath().startsWith(checkout.toPath())) {
        "Paply: Release-Keystore muss als absolute Datei außerhalb des Repositorys existieren."
    }
} else {
    logger.lifecycle("Paply: Keine Release-Signierung unter ~/Android/keys/paply-release.properties oder PAPLY_RELEASE_*; Release wird UNSIGNIERT gebaut, nicht weitergeben.")
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
        versionCode = 4
        versionName = "0.1.3"
    }
    signingConfigs.getByName("debug") {
        // All generated credentials stay in the remote work directory, never SDK/user-home.
        storeFile = rootProject.file(".local/debug.keystore")
    }
    if (releaseSigningReady) {
        signingConfigs.create("release") {
            storeFile = File(releaseStorePath!!)
            storePassword = releaseStorePassword
            keyAlias = releaseAlias
            keyPassword = releaseKeyPassword
        }
    }
    buildTypes {
        getByName("release") {
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (releaseSigningReady) signingConfig = signingConfigs.getByName("release")
        }
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
