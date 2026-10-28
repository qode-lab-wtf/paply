plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin { jvmToolchain(21) }

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}

tasks.withType<JavaCompile>().configureEach { options.release.set(17) }

dependencies {
    implementation(project(":core"))
    implementation("com.github.rholder:snowball-stemmer:1.3.0.581.1")
    implementation(libs.okhttp)
    implementation(libs.coroutines)
    implementation(libs.json)
    testImplementation(libs.junit)
    testImplementation(libs.mockwebserver)
}
