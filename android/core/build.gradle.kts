plugins { alias(libs.plugins.kotlin.jvm) }
kotlin { jvmToolchain(21) }
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}
tasks.withType<JavaCompile>().configureEach { options.release.set(17) }
dependencies {
    implementation(libs.okhttp)
    implementation(libs.coroutines)
    implementation(libs.json)
    testImplementation(libs.junit)
    testImplementation(libs.mockwebserver)
}
